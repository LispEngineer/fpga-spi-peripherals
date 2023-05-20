// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE
//
// ST7789 SPI Display Controller for Waveshare 2.0" LCD Module
//
// See Sitronix ST7789VW Data Sheet v1.0 dated 2017/09
// See Waveshare sample code for initialization sequence


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module st7789_controller #(
  // Parameters passed to 3-wire SPI controller
  // Settings for 50MHz clk = 20ns
  parameter CLK_DIV = 4, // 12.5MHz - Datasheet shows 50ns minimum write cycle - 20MHz
  parameter CLK_INTER_BYTE = 0, // Clocks to put between bytes
  parameter CLK_5ms = 250, // 250 x 20ns = 5ms

  // How long to wait before we start using the device in clock cycles?
  parameter POWER_UP_START = 32'd10_000_000, // 2/50ths of a second or 40ms
  // How long between refreshes do we wait in clock cycles?
  parameter DELAY_START = 32'd00_800_000, // About 1/60th of a second

  // DO NOT CHANGE THESE - from text_pixel_generator
  parameter TEXT_WIDTH  = 40,
  parameter TEXT_HEIGHT = 15,
  parameter TEXT_LEN = TEXT_WIDTH * TEXT_HEIGHT,
  parameter TEXT_SZ = $clog2(TEXT_LEN)
) (
  input  logic clk,
  input  logic reset,

  // SPI 4-wire interface
  output logic sck,      // Serial Clock
  output logic sdi,      // In to ILI9488 from controller; Previously MOSI
  input  logic sdo,      // Out to ILI9488 from controller; UNUSED; previously MISO
  output logic cs,       // Chip select (previously SS) - active low
  output logic dcx,      // Parameter/Data (High)/Command (Low)

  // Character write interface to text RAM
  input logic               clk_text_wr,
  input logic               text_wr_ena,
  input logic         [7:0] text_wr_data,
  input logic [TEXT_SZ-1:0] text_wr_addr
);

localparam OUT_BYTES = 15; // Also exactly 5 pixels, but we will send 4 at a time = 12
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


////////////////////////////////////////////////////////////////////////////
// Initialization sequence

localparam NUM_INIT_BYTES = 16;
localparam NUM_INIT_STEPS = 19;
// Byte 0 = length
logic [7:0] init [NUM_INIT_STEPS][NUM_INIT_BYTES];

initial begin
  init = '{default: 8'd0};
  init[0][0] = 8'd2; init[0][1] = 8'h36; init[0][2] = 8'h70;
  init[1][0] = 8'd2; init[1][1] = 8'h3a; init[1][2] = 8'h03;

  init[2][0] = 8'd1; init[2][1] = 8'h21;

  init[3][0] = 8'd5; init[3][1] = 8'h2a; init[3][2] = 8'h00; init[3][3] = 8'h00; init[3][4] = 8'h01; init[3][5] = 8'h3F;
  init[4][0] = 8'd5; init[4][1] = 8'h2b; init[4][2] = 8'h00; init[4][3] = 8'h00; init[4][4] = 8'h00; init[4][5] = 8'hEF;

  init[5][0] = 8'd6; init[5][1] = 8'hb2; init[5][2] = 8'h0c; init[5][3] = 8'h0c; init[5][4] = 8'h00; init[5][5] = 8'h33; init[5][6] = 8'h33;

  init[6][0]  = 8'd2; init[6][1]  = 8'hb7; init[6][2]  = 8'h35;
  init[7][0]  = 8'd2; init[7][1]  = 8'hbb; init[7][2]  = 8'h1f;
  init[8][0]  = 8'd2; init[8][1]  = 8'hc0; init[8][2]  = 8'h2c;
  init[9][0]  = 8'd2; init[9][1]  = 8'hc2; init[9][2]  = 8'h01;
  init[10][0] = 8'd2; init[10][1] = 8'hc3; init[10][2] = 8'h12;
  init[11][0] = 8'd2; init[11][1] = 8'hc4; init[11][2] = 8'h20;
  init[12][0] = 8'd2; init[12][1] = 8'hc6; init[12][2] = 8'h0f;
  
  init[13][0] = 8'd3; init[13][1] = 8'hd0; init[13][2] = 8'ha4; init[13][3] = 8'ha1;

  init[14][0] = 8'd15; init[14][1] = 8'he0; init[14][2] = 8'hd0; init[14][3] = 8'h08; init[14][4] = 8'h11; init[14][5] = 8'h08; init[14][6] = 8'h0c; init[14][7] = 8'h15; init[14][8] = 8'h39; init[14][9] = 8'h33; init[14][10] = 8'h50; init[14][11] = 8'h36; init[14][12] = 8'h13; init[14][13] = 8'h14; init[14][14] = 8'h29; init[14][15] = 8'h2d;
  init[15][0] = 8'd15; init[15][1] = 8'he1; init[15][2] = 8'hd0; init[15][3] = 8'h08; init[15][4] = 8'h10; init[15][5] = 8'h08; init[15][6] = 8'h06; init[15][7] = 8'h06; init[15][8] = 8'h39; init[15][9] = 8'h44; init[15][10] = 8'h51; init[15][11] = 8'h0b; init[15][12] = 8'h16; init[15][13] = 8'h14; init[15][14] = 8'h2f; init[15][15] = 8'h31;

  init[16][0] = 8'd1; init[16][1] = 8'h11;
  init[17][0] = '0;   init[17][1] = '1;      // Special flag for a 5ms delay
  init[18][0] = 8'd1; init[18][1] = 8'h29;
end



////////////////////////////////////////////////////////////////////////////
// States


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
logic [5:0] init_step;

// Memory refresher
localparam SCREEN_WIDTH = 320;
localparam SCREEN_HEIGHT = 240;
localparam PIXEL_COUNT = SCREEN_WIDTH * SCREEN_HEIGHT;
localparam BYTES_PER_TWO_PIXELS_444 = 3;
localparam MEMORY_BYTES = PIXEL_COUNT * BYTES_PER_TWO_PIXELS_444 / 2;
localparam MEM_SZ = $clog2(MEMORY_BYTES + 1);
localparam LAST_MEMORY_BYTE = MEMORY_BYTES; // 8 bytes at a time
// See 8.8.41 p 104 - RGB 4-4-4: RRRRGGGG_BBBB|RRRR_GGGGBBBB = 3 bytes per 2 pixels
logic [MEM_SZ-1:0] refresh_mem_pos;

////////////////////////////////////////////////////////////////////////////
// Display characters

logic toggle_restart = '0;
logic toggle_next = '0;
logic [7:0] cur_pixels;

localparam fg_color = 12'hF00;
localparam bg_color = 12'h000;

text_pixel_generator_40x15 text_gen_inst (
  .clk, .reset,

  .toggle_restart,
  .toggle_next,

  .cur_pixels,

  // We're not using these signals... yet
  .cur_char(),

  .clk_text_wr,
  .text_wr_ena,
  .text_wr_data,
  .text_wr_addr
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

  S_INIT: begin: do_init
    next_dcx_start       <= '0;
    next_dcx_flip        <= 2'd1;
    init_step            <= init_step + 1'd1;
    next_out_count       <= (OUT_BYTES_SZ)'(init[init_step][0]);

    for (int i = 1; i < NUM_INIT_BYTES; i++)
      next_out_data[i-1] <= init[init_step][i];

    if (init[init_step][0] == '0 && init[init_step][1] == '1) begin
      // Wait 5ms before the next command when disabling sleep
      state                <= S_DELAY;
      power_up_counter     <= CLK_5ms;
    end else begin
      state                <= S_SEND_COMMAND;
    end

    return_after_command <= init_step == NUM_INIT_STEPS - 1 ? S_REFRESH_MEM_START : S_INIT;
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

    // Start generating character pixels now, 
    // it will be ready by the time we use cur_pixels
    // (takes about 3? cycles).
    toggle_restart       <= ~toggle_restart;
  end: start_refresh_mem

  S_REFRESH_MEM: begin: do_refresh_mem
    // Send 8 pixels (12 bytes) at a time until we're done
    next_out_count       <= (OUT_BYTES_SZ)'(12); // 4 pixels of 3 bytes each

    // See 8.8.41 p 104 - RGB 4-4-4: RRRRGGGG_BBBB|RRRR_GGGGBBBB = 3 bytes per 2 pixels
    next_out_data[0]       <= cur_pixels[7] ? fg_color[11:4] : bg_color[11:4];
    next_out_data[1][7:4]  <= cur_pixels[7] ? fg_color[ 3:0] : bg_color[ 3:0];
    next_out_data[1][3:0]  <= cur_pixels[6] ? fg_color[11:8] : bg_color[11:8];
    next_out_data[2]       <= cur_pixels[6] ? fg_color[ 7:0] : bg_color[ 7:0];
 
    next_out_data[3]       <= cur_pixels[5] ? fg_color[11:4] : bg_color[11:4];
    next_out_data[4][7:4]  <= cur_pixels[5] ? fg_color[ 3:0] : bg_color[ 3:0];
    next_out_data[4][3:0]  <= cur_pixels[4] ? fg_color[11:8] : bg_color[11:8];
    next_out_data[5]       <= cur_pixels[4] ? fg_color[ 7:0] : bg_color[ 7:0];
 
    next_out_data[6]       <= cur_pixels[3] ? fg_color[11:4] : bg_color[11:4];
    next_out_data[7][7:4]  <= cur_pixels[3] ? fg_color[ 3:0] : bg_color[ 3:0];
    next_out_data[7][3:0]  <= cur_pixels[2] ? fg_color[11:8] : bg_color[11:8];
    next_out_data[8]       <= cur_pixels[2] ? fg_color[ 7:0] : bg_color[ 7:0];

    next_out_data[9]       <= cur_pixels[1] ? fg_color[11:4] : bg_color[11:4];
    next_out_data[10][7:4] <= cur_pixels[1] ? fg_color[ 3:0] : bg_color[ 3:0];
    next_out_data[10][3:0] <= cur_pixels[0] ? fg_color[11:8] : bg_color[11:8];
    next_out_data[11]      <= cur_pixels[0] ? fg_color[ 7:0] : bg_color[ 7:0];

    next_dcx_start       <= '1; // Data
    next_dcx_flip        <= '0; // Do not flip
    refresh_mem_pos      <= refresh_mem_pos + (MEM_SZ)'((8 * BYTES_PER_TWO_PIXELS_444) / 2);
    state                <= S_SEND_COMMAND;

    toggle_next          <= ~toggle_next; // Prepare the next set of character pixels

    // If we're drawing the last 8 pixels, we should be done now
    if (refresh_mem_pos >= (LAST_MEMORY_BYTE - ((8 * BYTES_PER_TWO_PIXELS_444) / 2))) begin // FIXME: is this the off by one(-ish) error?
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
