// Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.
//
// Pimoroni Unicorn Hat Mini Controller
//
// See Holtek ...
//


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module unicorn_hat_mini_controller #(
  // Parameters passed to 3-wire SPI controller
  // Settings for 50MHz clk
  parameter CLK_DIV = 16,
  parameter CLK_2us = 100, // 2µs at current clock rate (50MHz = 20ns => 100)

  // How long to wait before we start using the LED&KEY in clock cycles?
  parameter POWER_UP_START = 32'd10_000_000, // 2/50ths of a second or 40ms
  // DELAY_START of 460_000 causes the state machine to cycle about 107 times a second.
  // DELAY_START of 230_000 causes the state machine to cycle about 210 times a second.
  // The TM1638 only scans the keypad once every 4.7ms or about 212 times a second.
  // (v1.3 p8)
  parameter DELAY_START = 32'd0_460_000
) (
  input  logic clk,
  input  logic reset,

  // SPI interface
  output logic sck,      // Serial Clock
  output logic sdo,      // Previously MOSI
  output logic [1:0] cs // Chip select (previously SS) - active low
);

localparam NUM_SELECTS = 2;
localparam OUT_BYTES = 6;
localparam OUT_BYTES_SZ = $clog2(OUT_BYTES + 1);

logic busy;
logic activate;
logic [NUM_SELECTS-1:0] in_cs;
logic [7:0] out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] out_count;

logic [7:0] next_out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] next_out_count;



spi_3wire_controller #(
  .CLK_DIV(CLK_DIV),
  .CLK_2us(CLK_2us),
  .NUM_SELECTS(NUM_SELECTS),
  .OUT_BYTES(OUT_BYTES),
  .OUT_BYTES_SZ(OUT_BYTES_SZ)
) uhm_spi_inst (
  .clk,
  .reset,
  
  .sck,
  .dio_o(sdo),
  .dio_i(), .dio_e(), // Unused
  .cs,

  .busy,
  .activate,
  .in_cs,
  .out_data,
  .out_count,
  .in_data(), .in_count('0) // Unused
);

/*
// Initialization. See: https://github.com/pimoroni/unicornhatmini-python/blob/master/library/unicornhatmini/__init__.py

localparam INIT_LEN = 8;
localparam LAST_INIT = INIT_LEN - 1;
localparam INIT_WID = 6;

logic [7:0] init [INIT_LEN][INIT_WID];

initial begin
  // Length, then the actual data
  init[0][0] = 8'd1; init[0][1] = 8'hCC; // Soft reset
  init[1][0] = 8'd2; init[1][1] = 8'h37; init[1][2] = 8'h01; // Global brigthness
  init[2][0] = 8'd2; init[2][1] = 8'h20; init[2][2] = 8'h00; // Scroll control
  init[3][0] = 8'd2; init[3][1] = 8'h35; init[3][2] = 8'h00; // System control
  // Write display...
  init[4][0] = 8'd5; init[4][1] = 8'h80; init[4][2] = 8'h00; init[4][3] = 8'hFF; init[4][4] = 8'hFF; init[4][5] = 8'hFF; // Write Display
  init[5][0] = 8'd2; init[5][1] = 8'h41; init[5][2] = 8'hFF; // Com Pin Control
  init[6][0] = 8'd5; init[6][1] = 8'h42; init[6][2] = 8'hFF; init[6][3] = 8'hFF; init[6][4] = 8'hFF; init[6][5] = 8'hFF; // Row Pin Control
  init[7][0] = 8'd2; init[7][1] = 8'h35; init[7][2] = 8'h03; // System Control
end
*/

// Initialization. See README.md

localparam INIT_LEN = 4;
localparam LAST_INIT = INIT_LEN - 1;
localparam INIT_WID = 6;

/*
* COM output control
  * 41 ff
* ROW output Control
  * 42 ff ff ff ff
* Binary/Gray mode
  * 31 01 (binary mode, for now)
* Clear memory (binary) - it starts up with random contents
  80 00 00 00 00 00
  80 04 00 00 00 00
  80 08 00 00 00 00
  80 0b 00 00 00 00
  80 10 00 00 00 00
  80 14 00 00 00 00
  80 18 00 00 00 00
* System control - oscillator on & display on
  * 35 03
*/

logic [7:0] init [INIT_LEN][INIT_WID];

initial begin
  // Maybe: soft reset?
  // Maybe: Oscillator & display off
  // COM/ROW output controls
  init[0][0] = 8'd2; init[0][1] = 8'h41; init[0][2] = 8'hFF; // Com Pin Control
  init[1][0] = 8'd5; init[1][1] = 8'h42; init[1][2] = 8'hFF; init[1][3] = 8'hFF; init[1][4] = 8'hFF; init[1][5] = 8'hFF; // Row Pin Control
  // Binary/Gray mode
  init[2][0] = 8'd2; init[2][1] = 8'h31; init[2][2] = 8'h01; // Binary mode
  // Oscillator & display on
  init[3][0] = 8'd2; init[3][1] = 8'h35; init[3][2] = 8'h03; // System Control
end



typedef enum int unsigned {
  S_POWER_UP        = 0,
  S_SEND_COMMAND    = 1,
  S_AWAIT_COMMAND   = 2,
  S_INIT            = 3,
  S_IDLE            = 4
} state_t;

state_t state = S_POWER_UP;
state_t return_after_command;
logic send_busy_seen;
logic [2:0] xmit_4_count;
logic [31:0] power_up_counter = POWER_UP_START;
logic [4:0] init_step; // FIXME: Size


////////////////////////////////////////////////////////////////////////////
// Main TM1638 state machine

always_ff @(posedge clk) begin: tm1638_main
  // NOTE: Reset logic at end

  case (state)

  S_POWER_UP: begin: pwr_up
    // Give the module a moment to power up
    // The datasheet may say a required startup time but I didn't quickly find it
    if (power_up_counter == 0) begin
      state <= S_INIT;
      init_step <= '0;
    end else
      power_up_counter <= power_up_counter - 1'd1;
  end: pwr_up

  S_INIT: begin: do_init
    // Initialize from our initialization ROM
    next_out_count <= (OUT_BYTES_SZ)'(init[init_step][0]);
    for (int i = 1; i < INIT_WID; i++)
      next_out_data[i - 1] <= init[init_step][i];
    state <= S_SEND_COMMAND;
    init_step <= init_step + 1'd1;
    if (init_step == LAST_INIT)
      return_after_command <= S_IDLE;
    else
      return_after_command <= S_INIT;
  end: do_init

  S_IDLE: begin end

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
      in_cs          <= 2'b01; // FIXME: Just the first chip for now
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

  // RESET //////////////////////////////////////////////////////////

  if (reset) begin: do_reset
    power_up_counter <= POWER_UP_START;
    state <= S_POWER_UP;
  end: do_reset

end: tm1638_main




endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
