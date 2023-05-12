// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa/ModelSim for some reason.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


// Tick at 1ns (using #<num>) to a precision of 0.1ns (100ps)
`timescale 1 ns / 100 ps

module test_spi();

// Simulator generated clock & reset
logic  clk;
logic  reset;


////////////////////////////////////////////////////////////////////////////////////

// generate clock to sequence tests
// 2.5 MHz = 200 (one full cycle every 400 ticks at 1ns per tick per above)
// 25 MHz = 20
// 50 MHz = 10
// 125 MHz = 4
localparam CLOCK_DUR = 20; // 50 MHz
localparam HALF_CLOCK_DUR = CLOCK_DUR / 2;
localparam RESET_DUR = $ceil(CLOCK_DUR * 2.2);
localparam POST_RESET_DUR = $ceil(10 * CLOCK_DUR - RESET_DUR);
always begin
  #(HALF_CLOCK_DUR) clk <= ~clk;
end

localparam NUM_SELECTS = 2;
localparam OUT_BYTES = 5;
localparam OUT_BYTES_SZ = $clog2(OUT_BYTES + 1);
localparam IN_BYTES = 4;
localparam IN_BYTES_SZ = $clog2(IN_BYTES + 1);

// 3-wire SPI interface PLUS dcx
logic sck;
logic dio_o, dio_i, dio_e;
logic [NUM_SELECTS-1:0] cs;
logic dcx;

// Make random data on dio_i
always begin
  #(CLOCK_DUR * 1.7737372771); dio_i <= ~dio_i;
end

// Controller interface
logic busy;
logic activate;
logic [NUM_SELECTS-1:0] in_cs;
logic [7:0] out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] out_count;
logic [7:0] in_data [IN_BYTES];
logic [IN_BYTES_SZ-1:0] in_count;

// Optional inputs
logic dcx_start;
logic [1:0] dcx_flip;

//`define TEST_SLOW_SPI
`undef TEST_SLOW_SPI
`ifdef TEST_SLOW_SPI

spi_3wire_controller #(
  .NUM_SELECTS(NUM_SELECTS),
  .OUT_BYTES(OUT_BYTES),
  .CLK_DIV(12), // Simulation shows this produces a 240ns clock (as expected)
  .CLK_2us(96), // 100 produces a 2400ns/2.4µs delay clock cycle; 84 produces a 1922ns delay; 96 does 2162ns
  .ALL_DONE_DELAY(1)
) dut (
  .clk,
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_o, // data in/out (we use it only for out FOR NOW)
  .dio_i,
  .dio_e,
  .cs,  // Chip select (previously SS) - active low
  // FUTURE: input logic sdi // Serial data in (previously MISO)

  // Controller interface
  .busy,
  .activate,
  .in_cs, // Active high for which chip(s) you want enabled
  .out_data,
  .out_count,
  .in_data,
  .in_count,

  // DCX is unused
  .dcx(),
  .dcx_start(),
  .dcx_flip()
);

`else // ifndef TEST_SLOW_SPI

spi_3wire_controller #(
  .NUM_SELECTS(NUM_SELECTS),
  .OUT_BYTES(OUT_BYTES),
  .CLK_DIV(4), // 12.5 MHz clock from 50 MHz input
  .CLK_2us(0), // We don't need any inter-byte delay in IPI9488 datasheet
  .ALL_DONE_DELAY(0),
  .DCX_FLIP_MAX(1) // We need to flip the DCX signal after every command
) dut (
  .clk,
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_o, // data out for DIO or SDO
  .dio_i, // data in  for DIO or SDI
  .dio_e, // dio_o when high, dio_i when low
  .cs,  // Chip select (previously SS) - active low
  .dcx,

  // Controller interface
  .busy,
  .activate,
  .in_cs, // Active high for which chip(s) you want enabled
  .out_data,
  .out_count,
  .in_data,
  .in_count,
  .dcx_start,
  .dcx_flip
);

`endif


// initialize test with a reset for 22 ns
initial begin
  $display("Starting Simulation @ ", $time);
  clk <= 1'b0;
  dio_i <= '0;
  reset <= 1'b1; 
  #(RESET_DUR); 
  reset <= 1'b0;
  #(POST_RESET_DUR);

`ifdef TEST_SLOW_SPI

  activate <= '1;
  in_cs <= 2'b01;
  out_data[0] <= 8'hCC;
  out_data[1] <= 8'hDF;
  out_data[2] <= 8'b1010_0101;
  out_count <= OUT_BYTES;
  in_count <= 3'd4;
  // This will be ignored for slow SPI
  dcx_start <= '1;
  dcx_flip <= 1'd0;
  #(CLOCK_DUR * 128)
  activate <= '0;

`else // `ifdef TEST_SLOW_SPI

  activate <= '1;
  in_cs <= 2'b01;
  // Column Address Set - SC15-8,7-0; EC15-8,7-0
  // D/CX starts at 0 for the first byte and is 1 for all subsequent bites
  // .\spicl COM3 s a 0 w 0x2A a 1 w 0,0,1,0xDF u
  out_data[0] <= 8'h2A;
  out_data[1] <= 8'h00;
  out_data[2] <= 8'h00;
  out_data[3] <= 8'h01;
  out_data[4] <= 8'hDF;

  out_count <= 5;
  in_count <= 3'd0;
  // This will be ignored for slow SPI
  dcx_start <= '0; // 0 = Command; 1 = Data
  dcx_flip <= 1'd1;
  #(CLOCK_DUR * 12)
  activate <= '0;

`endif // `ifdef TEST_SLOW_SPI



  #(CLOCK_DUR * 5000)
  $display("Ending simulation @ ", $time);
  $stop; // $stop = breakpoint
  // DO NOT USE $finish; it will exit Questa!!!
end

endmodule



`ifdef IS_QUARTUS
`default_nettype wire // Restore default
`endif