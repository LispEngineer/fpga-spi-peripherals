// Copyright 2022 Douglas P. Fields, Jr. All Rights Reserved.

/*
Implementation of an SPI Controller,
LIMITED in these ways:
* Does not handle incoming data
* Targeted to the HT16D35A which uses a 3-wire SPI interface

Future:
* Use a FIFO for transmit data, and stop the transaction once
  an end delimiter comes OR the FIFO is empty?

There are four official SPIP modes:
* 0: Clock idles at 0, out changes data on trailing edge and in captures at leading  edge
* 1: Clock idles at 0, out changes data on leading  edge and in captures at trailing edge
* 2: Clock idles at 1, out changes data on trailing edge and in captures at leading  edge
* 3: Clock idles at 1, out changes data on leading  edge and in captures at trailing edge
* When clock idles at 0, leading edge is a rising edge.
* When clock idles at 1, leading edge is a falling edge.

See Holtek HT16D35A Rev 1.22 Data sheet starting on page 51.
Looks like it uses a 3-pin SPI instead of 4-pin, and it can
drive the DIO pin for data output, sort of like I²C.

0. Looks like clock idles high
1. Chip select to low
2. Transfer data MSB of each byte first
   * Data is shifted into a register at the rising edge of SCK
   * Input data is loaded into a regiser every 8 bits
3. For "read mode" (omitted, we're not implementing it)
4. For a multi-byte command there has to be a 2µs clock held high
   between each byte. (2 1/1,000,000ths of a second, or one 500,000th of a second)

*/


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif

module spi_controller_ht16d35a #(
  // How many chip select outputs we want
  parameter NUM_SELECTS = 2,
  parameter SELECT_SZ = $clog2(NUM_SELECTS),

  // How fast do we run the output SPI clock, as a divider from the provided clock.
  // If we have 50 MHz and want <= 4 MHz sck output, we need 12.5x, 
  // call it 16 since we prefer an multiple of 4 value so we can halve or quarter it.
  parameter CLK_DIV = 16,
  parameter DIV_SZ = $clog2(CLK_DIV),
  parameter CLK_2us = 100, // 2µs at current clock rate (50MHz = 20ns => 100)
  parameter us2_SZ = $clog2(CLK_2us),

  // How many bytes do you want to be able to write at a time?
  parameter OUT_BYTES = 8,
  parameter OUT_BYTES_SZ = $clog2(OUT_BYTES)
) (
  input logic clk,
  input logic reset,

  // SPI interface
  output logic sck, // Serial Clock
  output logic dio, // data in/out (we use it only for out FOR NOW)
  output logic [NUM_SELECTS-1:0] cs,  // Chip select (previously SS) - active low
  // FUTURE: input logic sdi // Serial data in (previously MISO)

  // Controller interface
  output logic busy,
  input  logic activate,
  input  logic [NUM_SELECTS-1:0] in_cs, // Active high for which chip(s) you want enabled
  input  logic [7:0] out_data [OUT_BYTES],
  input  logic [OUT_BYTES_SZ-1:0] out_count
);


// Our half-bit times are half the CLK_DIV
localparam CLK_HALF_BIT = $ceil(CLK_DIV / 2);
localparam HALF_BIT_SZ = $clog2(CLK_BIT);

typedef enum int unsigned {
  S_IDLE              = 0,
  S_START_SENDING     = 1,
  S_INTER_BYTE        = 2,
  S_FINISH_SENDING    = 3
} state_t;

state_t state = S_IDLE;

logic [HALF_BIT_SZ-1:0] half_bit_counter = (HALF_BIT_SZ)'(CLK_HALF_BIT);

// Saved data from activation
logic  [NUM_SELECTS-1:0] r_in_cs; // Active high for which chip(s) you want enabled
logic              [7:0] r_out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] r_out_count;

logic [OUT_BYTES_SZ-1:0] current_byte;
logic [2:0] current_bit; // We send MSB first

localparam INTER_BYTE_DELAY = $ceil(CLK_2us / CLK_HALF_BIT);
localparam IB_DELAY_SZ = $clog2(INTER_BYTE_DELAY);
localparam IB_DELAY_START = (IB_DELAY_SZ)'(INTER_BYTE_DELAY);
logic [IB_DELAY_SZ-1:0] inter_byte_delay;

always_ff @(posedge clk) begin: main_spi_controller

  if (half_bit_counter != 0) begin: wait_half_bit_time
    // Don't do the main state machine except every half bit time
    half_bit_counter <= half_bit_counter - 1'd1;

  end: wait_half_bit_time else begin: do_state_machine
    // Restart our half-bit counter
    half_bit_counter <= (HALF_BIT_SZ)'(CLK_HALF_BIT);

    case (state)

    S_IDLE: begin: s_idle

      cs <= '1; // no chips selected (active low)
      sck <= '1; // clock idles high
      busy <= '0;

      if (activate) begin: activation
        r_in_cs <= in_cs;
        r_out_data <= out_data;
        r_out_count <= out_count;

        current_byte <= '0;
        current_bit <= 3'd7;

        // Enable the necessary chips for the very first thing we do
        cs <= ~in_cs;
        // Keep the clock high for a cycle (per tCSL)
        state <= S_START_SENDING;
        busy <= '1;
      end: activation

    end: s_idle

    S_START_SENDING: begin: start_sending

      sck <= ~sck;

      if (sck) begin
        // Clock is currently high, will transition low.
        // So, send our output bit for reading when it transitions high again
        dio <= r_out_data[current_byte][current_bit];

      end else begin
        // Clock is currently low, when it shifts high
        // the data will be read by the HT16D35A,
        // so we should get ready to send the next bit
        if (current_bit == 0) begin: last_bit
          // We sent our last bit.
          // Do we have more?
          if (current_byte == r_out_count) begin: last_byte
            state <= S_FINISH_SENDING;
          end: last_byte else begin: more_bytes
            state <= S_INTER_BYTE;
            inter_byte_delay <= IB_DELAY_START;
          end: more_bytes
        end: last_bit
      end // half bit

    end: start_sending

    endcase // state

  end: do_state_machine

  if (reset) begin: last_assignment_wins
    // Do reset per http://fpgacpu.ca/fpga/verilog.html#resets
    half_bit_counter <= (HALF_BIT_SZ)'(CLK_HALF_BIT);
    cs <= '1; // no chips selected (active low)
    sck <= '1; // clock idles high
    busy <= '1; // Busy while in reset
    state <= S_IDLE;
  end: last_assignment_wins

end: main_spi_controller

endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif




/*
localparam SPI_MODE = 0;

// From: russell-merrick at https://github.com/nandland/spi-master/blob/master/Verilog/source/SPI_Master.v
// CPOL: Clock Polarity
// CPOL=0 means clock idles at 0, leading edge is rising edge.
// CPOL=1 means clock idles at 1, leading edge is falling edge.
localparam CLOCK_IDLE_ZERO = (SPI_MODE == 2) | (SPI_MODE == 3);

// CPHA: Clock Phase
// CPHA=0 means the "out" side changes the data on trailing edge of clock
//              the "in" side captures data on leading edge of clock
// CPHA=1 means the "out" side changes the data on leading edge of clock
//              the "in" side captures data on the trailing edge of clock
localparam CHANGE_OUT_TRAILING = (SPI_MODE == 1) | (SPI_MODE == 3);
*/


