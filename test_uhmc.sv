// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa/ModelSim for some reason.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


// Tick at 1ns (using #<num>) to a precision of 0.1ns (100ps)
`timescale 1 ns / 100 ps

module test_uhmc();

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

// 3-wire SPI interface
logic sck;
logic sdo;
logic [NUM_SELECTS-1:0] cs;


// Controller interface

// FIXME: It is not necessary for the sck to stay high
// for a while before deasserting cs (to inactive high)
// per the pages 51-52 of the datasheet (Holtek HT16D35A rev 1.22).

unicorn_hat_mini_controller #(
  .CLK_DIV(16),
  .CLK_2us(100),
  .POWER_UP_START(32'd1_000),
  .DELAY_START(32'd1_000)
) dut (
  .clk, .reset,

  .sck, .sdo, .cs
);



// initialize test with a reset for 22 ns
initial begin
  $display("Starting Simulation @ ", $time);
  clk <= 1'b0;
  reset <= 1'b1; 
  #(RESET_DUR); 
  reset <= 1'b0;
  #(POST_RESET_DUR);

  #(CLOCK_DUR * 20000)
  $display("Ending simulation @ ", $time);
  $stop; // $stop = breakpoint
  // DO NOT USE $finish; it will exit Questa!!!
end

endmodule



`ifdef IS_QUARTUS
`default_nettype wire // Restore default
`endif