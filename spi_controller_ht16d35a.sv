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

  // How fast do we run the output SPI clock, as
  // a divider from the provided clock.
  // If we have 50 MHz and want <= 4 MHz sck output, we need 12.5x, 
  // call it 16 since we prefer an multiple of 4 value so we can halve or quarter it
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
  input  logic [NUM_SELECTS-1:0] in_cs,
  input  logic [7:0] out_data [OUT_BYTES],
  input  logic [OUT_BYTES_SZ-1:0] out_count
);


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


