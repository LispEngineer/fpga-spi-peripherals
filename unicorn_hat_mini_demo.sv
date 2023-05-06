// Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.
//
// Pimoroni Unicorn Hat Mini Demo


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module unicorn_hat_mini_demo #(
  // Parameters passed to 3-wire SPI controller
  // Settings for 50MHz clk
  parameter CLK_DIV = 16,
  parameter CLK_2us = 100, // 2µs at current clock rate (50MHz = 20ns => 100)

  // TODO: Add binary vs gray scale mode

  // DO NOT CHANGE THESE PARAMETERS
  parameter NUM_ROWS   = 7,
  parameter NUM_COLS   = 17,
  parameter NUM_COLORS = 3, // R, G, B [2:0]
  parameter NUM_SELECTS = 2

) (
  input  logic clk,
  input  logic reset,

  // SPI interface
  output logic sck,      // Serial Clock
  output logic sdo,      // Previously MOSI
  output logic [NUM_SELECTS-1:0] cs // Chip select (previously SS) - active low
);


logic [NUM_COLORS-1:0] display_mem[NUM_COLS][NUM_ROWS];


unicorn_hat_mini_controller #(
  .CLK_DIV(CLK_DIV),
  .CLK_2us(CLK_2us)
) uhm_spi_inst (
  .clk,
  .reset,
  
  .sck, .sdo, .cs,

  .display_mem_b(display_mem) // Binary display memory
);


initial begin: initial_display_mem
  for (int x = 0; x < NUM_COLS; x++)
    for (int y = 0; y < NUM_ROWS; y++)
      display_mem[x][y] = '0;
  display_mem[0][0] = 3'b100;
  display_mem[5][0] = 3'b010;
  display_mem[10][0] = 3'b001;
  display_mem[0][1] = 3'b010;
  display_mem[1][1] = 3'b100;
  display_mem[2][1] = 3'b001;
  display_mem[3][2] = 3'b001;
  display_mem[4][3] = 3'b011;
  display_mem[5][4] = 3'b101;
  display_mem[6][5] = 3'b110;
  display_mem[7][6] = 3'b111;
end: initial_display_mem


// Make a nice pattern rotation in display memory space

localparam STEP_DELAY = 32'd8_000_000;
logic [31:0] step_counter = STEP_DELAY;

always_ff @(posedge clk) begin

  if (!reset) begin

    if (step_counter == 0) begin

      step_counter <= STEP_DELAY;

      for (int x = 0; x < NUM_COLS; x++) begin: forx
        for (int y = 0; y < NUM_ROWS; y++) begin: fory
          display_mem[x][y] <= display_mem[x == 0 ? NUM_COLS - 1 : x - 1][y];
        end: fory
      end: forx

    end else begin
      step_counter <= step_counter - 1'd1;
    end
  end
end






endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
