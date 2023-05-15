// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE
//
// ILI9488 SPI Display Controller
//
// See Ilitek ILI9488 Datasheet V100
// ILI9488_IDT_V100_20121128
//
// Unconnected pins to the controller:
// RESET - not use, tie high
// LED - not used, tie high (backlight)


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module ili9488_controller #(
  // Parameters passed to 3-wire SPI controller
  // Settings for 50MHz clk = 20ns
  parameter CLK_DIV = 4, // 12.5MHz - Datasheet shows 50ns minimum write cycle - 20MHz
  parameter CLK_INTER_BYTE = 0, // Clocks to put between bytes
  parameter CLK_5ms = 250, // 250 x 20ns = 5ms

  // How long to wait before we start using the device in clock cycles?
  parameter POWER_UP_START = 32'd10_000_000, // 2/50ths of a second or 40ms
  // How long between refreshes do we wait in clock cycles?
  parameter DELAY_START = 32'd50_000_000
) (
  input  logic clk,
  input  logic reset,

  // SPI 4-wire interface
  output logic sck,      // Serial Clock
  output logic sdi,      // In to ILI9488 from controller; Previously MOSI
  input  logic sdo,      // Out to ILI9488 from controller; UNUSED; previously MISO
  output logic cs,       // Chip select (previously SS) - active low
  output logic dcx       // Parameter/Data (High)/Command (Low)
);

localparam OUT_BYTES = 8;
localparam OUT_BYTES_SZ = $clog2(OUT_BYTES + 1);

// Controller interface
logic busy;
logic activate;
logic in_cs;
logic [7:0] out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] out_count;
logic dcx_start;
logic [1:0] dcx_flip;

logic [7:0] next_out_data [OUT_BYTES] = '{ default: 8'h00 };
logic [OUT_BYTES_SZ-1:0] next_out_count;
logic next_dcx_start;
logic [1:0] next_dcx_flip;

spi_3wire_controller #(
  .CLK_DIV(CLK_DIV),
  .CLK_2us(CLK_INTER_BYTE),
  .NUM_SELECTS(1),
  .OUT_BYTES(OUT_BYTES),
  .OUT_BYTES_SZ(OUT_BYTES_SZ),
  // We always flip after the first byte (at most)
  .DCX_FLIP_MAX(1)
) uhm_spi_inst (
  .clk,
  .reset,
  
  .sck,
  .dio_o(sdi), // Data out from controller and IN to ILI9488
  .dio_i(sdo), // Data in TO controller FROM ILI9488
  .dio_e(), // Unused - it has two non-multiplexed SDI/SDO lines not a DIO line
  .cs,

  .busy,
  .activate,
  .in_cs,
  .out_data,
  .out_count,
  .in_data(), .in_count('0), // Unused

  // D/CX pin on ILI9488
  .dcx,
  .dcx_start, 
  .dcx_flip
);


// Initialization. See README.md

/*
.\spicl COM3 s a 0 w 0x36 a 1 w 0xE8 u
.\spicl COM3 s a 0 w 0x2A a 1 w 0,0,1,0xDF u
.\spicl COM3 s a 0 w 0x2B a 1 w 0,0,1,0x3F u
.\spicl COM3 s a 0 w 0x11 u
.\spicl COM3 s a 0 w 0x29 u
*/


typedef enum int unsigned {
  S_POWER_UP        = 0,
  S_SEND_COMMAND    = 1,
  S_AWAIT_COMMAND   = 2,
  S_INIT            = 3,
  S_REFRESH_MEM_START = 4,
  S_REFRESH_MEM     = 5,
  S_END_REFRESH     = 6,
  S_DELAY           = 7
} state_t;
localparam state_t S_INIT_START = S_INIT;

state_t state = S_POWER_UP;
state_t return_after_command;
logic send_busy_seen;
logic [2:0] xmit_4_count;
logic [31:0] power_up_counter = POWER_UP_START;
logic [4:0] init_step;

// Memory refresher
localparam SCREEN_WIDTH = 480;
localparam SCREEN_HEIGHT = 320;
localparam PIXEL_COUNT = 480 * 320;
localparam PIXELS_PER_BYTE_111 = 2;
localparam MEMORY_BYTES = PIXEL_COUNT / PIXELS_PER_BYTE_111;
localparam MEM_SZ = $clog2(MEMORY_BYTES + 1);
localparam LAST_MEMORY_BYTE = MEMORY_BYTES; // 8 bytes at a time
// See 4.7.2.1 p 121 - RGB 1-1-1: xxRGBRGB - two pixels per byte
// localparam MEM_BYTE = 8'b00_100_100;
logic [MEM_SZ-1:0] refresh_mem_pos;

////////////////////////////////////////////////////////////////////////////
// Display characters

logic toggle_restart = '0;
logic toggle_next = '0;
logic [7:0] cur_pixels;

text_pixel_generator text_gen_inst (
  .clk, .reset,

  .toggle_restart,
  .toggle_next,

  .cur_pixels,

  // We're not using these signals... yet
  .cur_char(),

  .clk_text_wr(),
  .text_wr_ena(),
  .text_wr_data(),
  .text_wr_addr()
);


////////////////////////////////////////////////////////////////////////////
// Main ILI9488 state machine

always_ff @(posedge clk) begin: uhm_main
  // NOTE: Reset logic at end

  case (state)

  S_POWER_UP: begin: pwr_up
    // Give the module a moment to power up
    // The datasheet may say a required startup time but I didn't quickly find it
    power_up_counter     <= POWER_UP_START;
    state                <= S_DELAY;
    return_after_command <= S_INIT_START;
    init_step            <= '0;
  end: pwr_up

  ////////////////////////////////////////////////////////////////////////////////
  // Initialization
/*
.\spicl COM3 s a 0 w 0x36 a 1 w 0xE8 u
3A 8'bx110_x001 - 3 bits/pixel
3A 8'bx110_x101 - 16 bits/pixel (theoretical, see p 121)
3A 8'bx110_x110 - 18 bits/pixel
.\spicl COM3 s a 0 w 0x2A a 1 w 0,0,1,0xDF u
.\spicl COM3 s a 0 w 0x2B a 1 w 0,0,1,0x3F u
.\spicl COM3 s a 0 w 0x11 u
!WAIT 5ms!
.\spicl COM3 s a 0 w 0x29 u
*/

  S_INIT: begin: do_init
    next_dcx_start       <= '0;
    next_dcx_flip        <= 2'd1;
    state                <= S_SEND_COMMAND;
    return_after_command <= S_INIT;
    init_step            <= init_step + 1'd1;
    case (init_step)
    0: begin: init_0
      // Memory Access Control 5.2.30 p 192
      next_out_count       <= (OUT_BYTES_SZ)'(2);
      next_out_data[0]     <= 8'h36;
      next_out_data[1]     <= 8'hE8;
    end: init_0
    1: begin: init_1
      // Interface Pixel Format 5.2.34 p 200
      next_out_count       <= (OUT_BYTES_SZ)'(2);
      next_out_data[0]     <= 8'h3A;
      next_out_data[1]     <= 8'b0110_0001; // 18 bits per pixel RGP; 3 bits per pixel MCU
    end: init_1
    2: begin: init_2
      // Column address set 5.2.22 p 175
      next_out_count       <= (OUT_BYTES_SZ)'(5);
      next_out_data[0]     <= 8'h2A;
      next_out_data[1]     <= 8'h00;
      next_out_data[2]     <= 8'h00;
      next_out_data[3]     <= 8'h01;
      next_out_data[4]     <= 8'hDF;
    end: init_2
    3: begin: init_3
      // Page address set 5.2.23 p 177
      next_out_count       <= (OUT_BYTES_SZ)'(5);
      next_out_data[0]     <= 8'h2B;
      // Skip the next 3 as they are the same as step 1
      // next_out_data[1]     <= 8'h00;
      // next_out_data[2]     <= 8'h00;
      // next_out_data[3]     <= 8'h01;
      next_out_data[4]     <= 8'h3F;
    end: init_3
    4: begin: init_4
      // Disable sleep - 5.2.13 p 166
      // Must wait 5ms before the next command
      next_out_count       <= (OUT_BYTES_SZ)'(1);
      next_out_data[0]     <= 8'h11;
    end: init_4
    5: begin: init_5
      // Wait 5ms before the next command
      state                <= S_DELAY;
      power_up_counter     <= CLK_5ms;
      // return_after_command <= S_INIT;
    end: init_5
    6: begin: init_6
      // Display on - 5.2.21 p 174
      next_out_count       <= (OUT_BYTES_SZ)'(1);
      next_out_data[0]     <= 8'h29;
      return_after_command <= S_REFRESH_MEM_START;
    end: init_6
    endcase // init_step
  end: do_init

  ////////////////////////////////////////////////////////////////////////////////
  // Memory refresher
  
  /*
  To write the memory:
  .\spicl COM3 s a 0 w 0x2C a 1 w 0,255,0... u
  .\spicl COM3 s a 0 w 0x3C a 1 w 0,255,0... u

  1. Write command 2C and then just send all the data with D/CK 0
  2. If we get interrupted, continue the write with 3C then all the data
     (this is not possible currently)
  */

  S_REFRESH_MEM_START: begin: start_refresh_mem
    next_dcx_start       <= '0; // Command
    next_dcx_flip        <= 2'd1;
    state                <= S_SEND_COMMAND;
    return_after_command <= S_REFRESH_MEM;
    next_out_count       <= (OUT_BYTES_SZ)'(1);
    next_out_data[0]     <= 8'h2C;
    refresh_mem_pos      <= '0;

    // Start generating character pixels now
    toggle_restart       <= ~toggle_restart;
  end: start_refresh_mem

  S_REFRESH_MEM: begin: do_refresh_mem
    // Send 4 bytes at a time until we're done
    // Binary data has 28 bytes to clear
    next_out_count       <= (OUT_BYTES_SZ)'(4);
    next_out_data[0]     <= {1'b0, {3{cur_pixels[7]}}, 1'b0, {3{cur_pixels[6]}}};
    next_out_data[1]     <= {1'b0, {3{cur_pixels[5]}}, 1'b0, {3{cur_pixels[4]}}};
    next_out_data[2]     <= {1'b0, {3{cur_pixels[3]}}, 1'b0, {3{cur_pixels[2]}}};
    next_out_data[3]     <= {1'b0, {3{cur_pixels[1]}}, 1'b0, {3{cur_pixels[0]}}};
    next_dcx_start       <= '1; // Data
    next_dcx_flip        <= '0; // Do not flip
    refresh_mem_pos      <= refresh_mem_pos + (MEM_SZ)'(4);
    state                <= S_SEND_COMMAND;

    toggle_next          <= ~toggle_next; // Prepare the next set of character pixels

    if (refresh_mem_pos >= LAST_MEMORY_BYTE) begin
      return_after_command <= S_END_REFRESH;
    end else begin
      return_after_command <= S_REFRESH_MEM;
    end
  end: do_refresh_mem

  S_END_REFRESH: begin: end_refresh
    // Wait a bit, then do it all over again
    state                <= S_DELAY;
    return_after_command <= S_REFRESH_MEM_START;
    power_up_counter     <= DELAY_START;
  end: end_refresh

  ////////////////////////////////////////////////////////////////////////////////
  // Delay subroutine

  S_DELAY: begin: do_delay
    if (power_up_counter == 0)
      state <= return_after_command;
    else
      power_up_counter <= power_up_counter - 1'd1;
  end: do_delay

  ////////////////////////////////////////////////////////////////////////////////
  // Send subroutine

  S_SEND_COMMAND: begin: send_command
    // Send a specific I2C command, and return to the specified state
    // after it is done.
    if (busy) begin
      // Wait for un-busy
      activate <= '0;
    end else begin
      out_data       <= next_out_data;
      out_count      <= next_out_count;
      in_cs          <= '1;
      dcx_start      <= next_dcx_start;
      dcx_flip       <= next_dcx_flip;
      activate       <= '1;
      state          <= S_AWAIT_COMMAND;
      send_busy_seen <= '0;
    end
  end: send_command

  S_AWAIT_COMMAND: begin: await_command
    // Wait for busy to go true, then go false
    case ({send_busy_seen, busy})
    2'b01: begin: busy_starting
      // We are seeing busy for the first time
      send_busy_seen <= '1;
      activate <= '0;
    end: busy_starting
    2'b10: begin: busy_ending
      // Busy is now ending
      state <= return_after_command;
    end: busy_ending
    endcase
  end: await_command

  endcase // state_case

  // RESET /////////////////////////////////////////////////////////////////////

  if (reset) begin: do_reset
    state <= S_POWER_UP;
  end: do_reset

end: uhm_main




endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
