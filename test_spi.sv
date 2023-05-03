// Copyright 2023 ⓒ Douglas P. Fields, Jr. All Rights Reserved.

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
localparam OUT_BYTES = 3;
localparam OUT_BYTES_SZ = $clog2(OUT_BYTES + 1);
localparam IN_BYTES = 4;
localparam IN_BYTES_SZ = $clog2(IN_BYTES + 1);

// 3-wire SPI interface
logic sck;
logic dio_o, dio_i, dio_e;
logic [NUM_SELECTS-1:0] cs;

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

spi_controller_ht16d35a #(
  .NUM_SELECTS(NUM_SELECTS),
  .OUT_BYTES(OUT_BYTES),
  .CLK_DIV(12), // Simulation shows this produces a 280ms clock
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
  .in_count
);


// initialize test with a reset for 22 ns
initial begin
  $display("Starting Simulation @ ", $time);
  clk <= 1'b0;
  dio_i <= '0;
  reset <= 1'b1; 
  #(RESET_DUR); 
  reset <= 1'b0;
  #(POST_RESET_DUR);

  activate <= '1;
  in_cs <= 2'b01;
  out_data[0] <= 8'hCC;
  out_data[1] <= 8'hDF;
  out_data[2] <= 8'b1010_0101;
  out_count <= OUT_BYTES;
  in_count <= 3'd4;
  #(CLOCK_DUR * 128)
  activate <= '0;

  #(CLOCK_DUR * 5000)
  $display("Ending simulation @ ", $time);
  $stop; // $stop = breakpoint
  // DO NOT USE $finish; it will exit Questa!!!
end

endmodule



`ifdef IS_QUARTUS
`default_nettype wire // Restore default
`endif