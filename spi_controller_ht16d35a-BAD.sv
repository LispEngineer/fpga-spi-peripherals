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
drive the DIO_O pin for data output, sort of like I²C.

0. Looks like clock idles high
1. Chip select to low
2. Transfer data MSB of each byte first OR LSB if the parameter is set for LSB_FIRST
   * Data is shifted into a register on the receiver at the rising edge of SCK
   * Input data is loaded into a regiser every 8 bits
3. For "read mode" (omitted, we're not implementing it)
4. For a multi-byte command there has to be a 2µs clock held high
   between each byte. (2 1/1,000,000ths of a second, or one 500,000th of a second)
   * This has to also happen after the final bit before releasing CS
5. After writing each byte, if we have any to read, wait the inter-byte delay
6. "Output serial data at falling edge of the clock, starting from lower bits.
   During output, this is a PMOS open drain output."
7. Some devices need the inter-byte delay before releasing chip select

FIXME: Power up reset has to wait either 1 or 10ms - have that done
outside this module?

-----------------

Note: The TM1638 chip uses the same protocol with slightly different
timings.

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
  parameter DIV_SZ = $clog2(CLK_DIV + 1),
  parameter CLK_2us = 100, // 2µs at current clock rate (50MHz = 20ns => 100)
  parameter us2_SZ = $clog2(CLK_2us + 1),

  // How many bytes do you want to be able to write at a time?
  parameter OUT_BYTES = 8,
  parameter OUT_BYTES_SZ = $clog2(OUT_BYTES + 1),
  parameter IN_BYTES = 4,
  parameter IN_BYTES_SZ = $clog2(IN_BYTES + 1),

  // Do we need to wait after releasing CS (to high, since it is active low)?
  parameter ALL_DONE_DELAY = 0,

  // We default to MSB first
  parameter LSB_FIRST = 0
) (
  input logic clk,
  input logic reset,

  // SPI interface
  output logic sck, // Serial Clock
  output logic dio_o, // data in/out - OUT
  input  logic dio_i, // data in/out - IN
  output logic dio_e, // data in/out - enable for in/out buffer
  output logic [NUM_SELECTS-1:0] cs,  // Chip select (previously SS) - active low

  // Controller interface
  output logic busy,
  input  logic activate,
  input  logic [NUM_SELECTS-1:0] in_cs, // Active high for which chip(s) you want enabled
  input  logic [7:0] out_data [OUT_BYTES],
  output logic [7:0]  in_data [IN_BYTES],
  input  logic [OUT_BYTES_SZ-1:0] out_count,
  input  logic  [IN_BYTES_SZ-1:0] in_count
);

// FIXME: Do not allow reads with multiple chip selects enabled?


// Our half-bit times are half the CLK_DIV
localparam CLK_HALF_BIT = (CLK_DIV + 1) >> 1; // $ceil not working for QUESTA
localparam HALF_BIT_SZ = $clog2(CLK_HALF_BIT) + 1; // This should be 4 but is coming out 3
localparam HALF_BIT_START = (HALF_BIT_SZ)'(CLK_HALF_BIT);

localparam INTER_BYTE_END_SZ = IN_BYTES_SZ > OUT_BYTES_SZ ? IN_BYTES_SZ : OUT_BYTES_SZ;

typedef enum int unsigned {
  S_IDLE              = 0,
  S_SEND_BITS         = 1,
  S_INTER_BYTE        = 2,
  S_READ_BITS         = 3,
  S_ALL_DONE          = 4
} state_t;

state_t state = S_IDLE;
state_t inter_byte_return;

logic [HALF_BIT_SZ-1:0] half_bit_counter = HALF_BIT_START;

// Saved data from activation
logic  [NUM_SELECTS-1:0] r_in_cs; // Active high for which chip(s) you want enabled
logic              [7:0] r_out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] r_out_count;
logic  [IN_BYTES_SZ-1:0] r_in_count;

logic [OUT_BYTES_SZ-1:0] current_byte;
logic [2:0] current_bit; // We send MSB first
logic [INTER_BYTE_END_SZ-1:0] current_last_byte;

// Calculate a 2µs delay
localparam INTER_BYTE_DELAY = ((CLK_2us + CLK_DIV - 1) / CLK_DIV) * 2; // $ceil not working for Questa
localparam IB_DELAY_SZ = $clog2(INTER_BYTE_DELAY + 1);
localparam IB_DELAY_START = (IB_DELAY_SZ)'(INTER_BYTE_DELAY - 3); // This -3 was found with simulation but still results in a 2,380µs clock peak
logic [IB_DELAY_SZ-1:0] inter_byte_delay;

always_ff @(posedge clk) begin: main_spi_controller

  if (half_bit_counter != 0) begin: wait_half_bit_time
    // Don't do the main state machine except every half bit time
    half_bit_counter <= half_bit_counter - 1'd1;

  end: wait_half_bit_time else begin: do_state_machine
    // Restart our half-bit counter
    half_bit_counter <= HALF_BIT_START;

    case (state)

    S_IDLE: begin: s_idle

      cs <= '1; // no chips selected (active low)
      sck <= '1; // clock idles high
      dio_e <= '0;
      busy <= '0;

      // FIXME: If activated with no chip selects, should we
      // just pulse the busy and go back to idle?
      // Or just assert busy while it's activated and no chip selects?
      // Same with zero out_count.

      // FIXME: Allow reads with zero out first? Probably not.

      if (activate && in_cs != '0 && out_count != '0) begin: activation
        r_in_cs <= in_cs;
        r_out_data <= out_data;
        r_out_count <= out_count;
        r_in_count <= in_count;

        current_byte <= '0;
        current_last_byte <= out_count - 1'd1;
        current_bit <= 3'd7;
        dio_e <= '1; // Enable output

        // Enable the necessary chips for the very first thing we do
        cs <= ~in_cs;
        // Keep the clock high for a cycle (per tCSL)
        state <= S_SEND_BITS;
        busy <= '1;
      end: activation

    end: s_idle

    S_SEND_BITS: begin: start_sending
      // Always enter this state with the sck high!!

      sck <= ~sck;
      inter_byte_return <= S_SEND_BITS;

      if (sck) begin
        // Clock is currently high, will transition low.
        // So, send our output bit for reading when it transitions high again
          dio_o <= r_out_data[current_byte][LSB_FIRST ? 3'd7 - current_bit : current_bit];

      end else begin
        // Clock is currently low, when it shifts high
        // the data will be read by the HT16D35A,
        // so we should get ready to send the next bit
        if (current_bit == 0) begin: last_bit
          // We sent our last bit. We need to delay
          // before our next bit or releasing CS.
          state <= S_INTER_BYTE;
          // Check if we're receiving OR if we need a delay before deasserting CS,
          // and set inter_byte_delay correctly.
          if (current_byte == current_last_byte) begin: on_last_write_byte

            // Should we delay or go straight to done?
            if (r_in_count != 0 || ALL_DONE_DELAY)
              inter_byte_delay <= IB_DELAY_START;
            else
              inter_byte_delay <= 0;

            // Should we read or go straight to done?
            if (r_in_count != 0) begin
              inter_byte_return <= S_READ_BITS;
              current_byte      <= current_byte + 1'd1;
              current_bit       <= 3'd7;
            end else begin
              inter_byte_return <= S_IDLE;
            end
          end: on_last_write_byte
        end: last_bit else begin: more_bits
          current_bit <= current_bit - 1'd1;
        end: more_bits
      end // half bit

    end: start_sending

    S_INTER_BYTE: begin: inter_byte
      // During the inter byte, we hold the clock high and the chip select low
      // for a desired 2µs (page 51). If we have more bytes, we keep the CS low,
      // and send bytes, but if not, we release the CS after.
      // See timing diagram on page 6 for tCSH.

      // ASSERT: sck is high

      if (inter_byte_delay == 0) begin
        // Are we done sending
        if (current_byte != current_last_byte) begin
          // We have more bytes to send.
          state <= inter_byte_return;
          current_byte <= current_byte + 1'd1;
          current_bit <= 3'd7;
        end else begin
          // No more bytes. We have to hold CS high for tCSW
          // (which is conveniently 2/5ths of a clock cycle time).
          // See pages 5-6.
          if (inter_byte_return == S_SEND_BITS && r_in_count != 0) begin
            // We are done sending bytes, but now we have to receive them
            current_byte <= '0;
            current_last_byte <= r_in_count - 1'd1;
            current_bit <= 3'd7;
            state <= S_READ_BITS;
          end else begin
            state <= S_IDLE;
          end 
          
          /*
          else begin
            // MAY need a post-CS deassert delay
            state <= S_ALL_DONE;
            inter_byte_delay <= 0; // (ALL_DONE_DELAY == 0) ? 0 : IB_DELAY_START;
            // Yes, this adds a half-bit cycle before we go to IDLE if there is no IB_DELAY
            // but that won't hurt anything.
          end
          */
        end
      end
      // We don't care if this underflows
      inter_byte_delay <= inter_byte_delay - 1'd1;
    end: inter_byte

    S_READ_BITS: begin: start_receiving
      // Always enter this state with the sck high!!

      sck <= ~sck;
      inter_byte_return <= S_READ_BITS;

      if (sck) begin
        // Clock is currently high, will transition low.
        // So, send our output bit for reading when it transitions high again.
        // The peripheral will send serial data at the falling edge of this clock,
        // so do nothing for now

      end else begin
        // Clock is low, just transitioned from high, so read the data
        in_data[current_byte][LSB_FIRST ? 3'd7 - current_bit : current_bit] <= dio_i;

        if (current_bit == 0) begin: last_bit
          // We got our last bit. We need to delay
          // before our next bit or releasing CS.
          state <= S_INTER_BYTE;
          inter_byte_delay <= IB_DELAY_START;
        end: last_bit else begin: more_bits
          current_bit <= current_bit - 1'd1;
        end: more_bits
      end // half bit

    end: start_receiving

    S_ALL_DONE: begin: all_done
      // Some implementations have a long inter-packet delay after CS high

      if (inter_byte_delay == 0) begin
        state <= S_IDLE;
        cs <= '1;
        dio_e <= '0;
        busy <= '0;
      end else begin
        // We don't care if this underflows
        inter_byte_delay <= inter_byte_delay - 1'd1;
      end
    end: all_done

    endcase // state

  end: do_state_machine

  if (reset) begin: last_assignment_wins_reset
    // Do reset per http://fpgacpu.ca/fpga/verilog.html#resets
    half_bit_counter <= (HALF_BIT_SZ)'(CLK_HALF_BIT);
    cs <= '1; // no chips selected (active low)
    sck <= '1; // clock idles high
    busy <= '1; // Busy while in reset
    state <= S_IDLE;
    dio_e <= '0; // Disable output
  end: last_assignment_wins_reset

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


