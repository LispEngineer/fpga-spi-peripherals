// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa/ModelSim for some reason.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


// Tick at 1ns (using #<num>) to a precision of 0.1ns (100ps)
`timescale 1 ns / 100 ps

// I use test_tpg because if I called this test_pixel_generator it would be only
// one character different from the DUT!!
module test_tpg();

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


logic toggle_restart = '0;
logic toggle_next = '0;

text_pixel_generator dut (
  .clk, .reset,

  .toggle_restart,
  .toggle_next,

  // For test purposes, we ignore these and look at the signals directly
  .cur_char(),
  .cur_pixels(),
  .clk_text_wr(),
  .text_wr_ena(),
  .text_wr_data(),
  .text_wr_addr()
);



// initialize test with a reset for 22 ns
initial begin
  $display("Starting Simulation @ ", $time);
  clk <= 1'b0;
  reset <= 1'b1; 
  #(RESET_DUR); 
  reset <= 1'b0;
  #(POST_RESET_DUR);
  #(HALF_CLOCK_DUR);

  toggle_restart <= ~toggle_restart;
  #(CLOCK_DUR * 10);

  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 10);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 9);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 8);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 7);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 6);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 5);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 4);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 3);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 2);
  toggle_next <= ~toggle_next;
  #(CLOCK_DUR * 1);


  #(CLOCK_DUR * 5000)
  $display("Ending simulation @ ", $time);
  $stop; // $stop = breakpoint
  // DO NOT USE $finish; it will exit Questa!!!
end

endmodule



`ifdef IS_QUARTUS
`default_nettype wire // Restore default
`endif