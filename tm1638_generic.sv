// Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.
// Generic TM1638 controller that uses 3-wire SPI controller

// This can be used for the LED & KEY board and others based on the
// Titan Micro Electronics TM1638.
//
// See Titan Micro Electronics TM1638 Datasheet v1.3.

// This refreshes the whole state (input & output) from the specified
// inputs every specified interval (in clocks).

// For Quartus/Intel/Altera:
// Example: Two-way I/O buffer - DO NOT USE OPEN DRAIN (it does not work with LED & KEY module).
// DO use "Weak Pull Up Resistor" in the Assignment Editor; see this in .qsf file:
//   set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to GPIO[21]
// Datain means IN TO THE BUFFER, which would be OUT FROM THIS MODULE
// and hence OUT TO THE EXTERNAL PIN
`ifdef DO_NOT_USE_THIS_EXAMPLE_HERE
altiobuf_dio	altiobuf_dio_inst (
	.dataio (GPIO[21]),
	.oe     (dio_e),
	.datain (dio_o),
	.dataout(dio_i)
);
`endif // DO_NOT_USE_THIS_EXAMPLE_HERE

// TODOs:
// 1. Adjustable brightness
// 2. Display off and on


module tm1638_generic #(
  // Parameters passed to 3-wire SPI controller
  // Settings for 50MHz clk
  parameter CLK_DIV = 20,
  parameter CLK_2us = 100, // 2µs at current clock rate (50MHz = 20ns => 100)

  // How many bytes we read and write total to the TM1638
  parameter TM1638_OUT_COUNT = 16,
  parameter TM1638_IN_COUNT = 4,

  // How long to wait before we start using the LED&KEY in clock cycles?
  parameter POWER_UP_START = 32'd2_000_000, // 2/50ths of a second or 40ms
  // DELAY_START of 460_000 causes the state machine to cycle about 107 times a second.
  // DELAY_START of 230_000 causes the state machine to cycle about 210 times a second.
  // The TM1638 only scans the keypad once every 4.7ms or about 212 times a second.
  // (v1.3 p8)
  parameter DELAY_START = 32'd0_460_000
) (
  input  logic clk,
  input  logic reset,

  // SPI interface
  output logic sck,   // Serial Clock
  // These must be wired to an ALTIOBUF with weak pull-up if you want to read keys
  output logic dio_o, // data in/out - OUT
  input  logic dio_i, // data in/out - IN
  output logic dio_e, // data in/out - enable for in/out buffer
  output logic cs,    // Chip select (previously SS) - active low

  // LED outputs
  input  logic [7:0] tm1638_out [TM1638_OUT_COUNT],
  // Key/switch inputs
  output logic [7:0] tm1638_in  [TM1638_IN_COUNT]

  // TODO: Take brightness
);

// How many bytes we want to output at a time with
// the underlying SPI 3-wire controller
localparam OUT_BYTES = 5;
localparam OUT_BYTES_SZ = $clog2(OUT_BYTES + 1);
localparam IN_BYTES_SZ = $clog2(TM1638_IN_COUNT + 1);

logic [7:0] next_out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] next_out_count;
logic [IN_BYTES_SZ-1:0] next_in_count;

logic busy;
logic activate;
logic [OUT_BYTES_SZ-1:0] out_count;
logic [IN_BYTES_SZ-1:0] in_count;
logic [7:0] out_data [OUT_BYTES];
logic in_cs;

spi_controller_ht16d35a #(
  .CLK_DIV(CLK_DIV), // 20ns/50MHz system clock -> 400ns/2.5MHz TM1638 clock
  .CLK_2us(CLK_2us),
  .OUT_BYTES(OUT_BYTES),
  .IN_BYTES(TM1638_IN_COUNT), // Read all memory in one fell swoop, just 4 bytes
  .NUM_SELECTS(1),
  .ALL_DONE_DELAY(1),
  .LSB_FIRST(1)
) ledNkey_inst (
  .clk,
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_i, .dio_o, .dio_e,
  .cs,  // Chip select (previously SS) - active low

  // Controller interface
  .busy,
  .activate,
  .in_cs, // Active high for which chip(s) you want enabled
  .out_data,
  .out_count,
  .in_data(tm1638_in),
  .in_count
);

typedef enum int unsigned {
  S_POWER_UP        = 0,
  S_SEND_COMMAND    = 1,
  S_AWAIT_COMMAND   = 2,
  // TODO: Make a memory to do initialization
  S_AUTO_INCREMENT  = 3,
  S_XMIT_4          = 4,
  S_MAX_BRIGHT      = 5,
  S_READ_BYTES      = 6
} state_t;

state_t state = S_POWER_UP;
state_t return_after_command;
logic send_busy_seen;
logic [2:0] xmit_4_count;
logic [31:0] power_up_counter = POWER_UP_START;


////////////////////////////////////////////////////////////////////////////
// Main TM1638 state machine

always_ff @(posedge clk) begin: tm1638_main
  // NOTE: Reset logic at end

  case (state)

  S_POWER_UP: begin: pwr_up
    // Give the module a moment to power up
    // The datasheet may say a required startup time but I didn't quickly find it
    if (power_up_counter == 0)
      state <= S_AUTO_INCREMENT;
    else
      power_up_counter <= power_up_counter - 1'd1;
  end: pwr_up

  S_AUTO_INCREMENT: begin: auto_incr
    next_out_data[0] <= 8'h40; // see README
    next_out_count <= 1'd1;
    next_in_count <= '0;
    state <= S_SEND_COMMAND;
    return_after_command <= S_XMIT_4;
    xmit_4_count <= 0;
  end: auto_incr

  S_XMIT_4: begin: xmit_4
    // FIXME: Make this handle any amount of data instead of being
    // hard coded to exactly 16 bytes in 4 sets of 4
    next_out_data[0] <= 8'hC0 + ((8)'(xmit_4_count) << 2); // see README - ADDRESS SETTING
    next_out_data[1] <= tm1638_out[((4)'(xmit_4_count) << 2) + 0];
    next_out_data[2] <= tm1638_out[((4)'(xmit_4_count) << 2) + 1];
    next_out_data[3] <= tm1638_out[((4)'(xmit_4_count) << 2) + 2];
    next_out_data[4] <= tm1638_out[((4)'(xmit_4_count) << 2) + 3];
    next_out_count <= 3'd5;
    next_in_count <= '0;
    state <= S_SEND_COMMAND;

    if (xmit_4_count == 3) begin
      return_after_command <= S_MAX_BRIGHT;
    end else begin
      return_after_command <= S_XMIT_4;
      xmit_4_count <= xmit_4_count + 1'd1;
    end
  end: xmit_4

  S_MAX_BRIGHT: begin: max_brt
    // TODO: Adjustable brightness
    next_out_data[0] <= 8'h8F; // see README
    next_out_count <= 1'd1;
    next_in_count <= '0;
    state <= S_SEND_COMMAND;
    // return_after_command <= S_ROTATE;
    return_after_command <= S_READ_BYTES;
  end: max_brt

  S_READ_BYTES: begin: read_bytes
    next_out_data[0] <= 8'b01_00_00_10; // see README: Read key scanning data
    next_out_count <= 1'd1;
    next_in_count <= (IN_BYTES_SZ)'(TM1638_IN_COUNT); // Read all the (4) bytes
    state <= S_SEND_COMMAND;
    // return_after_command <= S_ROTATE;
    return_after_command <= S_POWER_UP;
    power_up_counter <= DELAY_START; // Do our inter-refresh delay
  end: read_bytes


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
      in_count       <= next_in_count;
      in_cs          <= '1; // Only one chip
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

