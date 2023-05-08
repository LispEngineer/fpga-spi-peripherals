// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE
//
// Little demo to flick the lights and use the keys on the QYF-TM1638 board.
//
// 1. Buttons change the digits up or down
// 2. decimals rotate around


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module qyf_tm1638_demo #(
  // Parameters passed to 3-wire SPI controller
  // Settings for 50MHz clk
  parameter CLK_DIV = 20,
  parameter CLK_2us = 100, // 2µs at current clock rate (50MHz = 20ns => 100)

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
  output logic cs     // Chip select (previously SS) - active low
);

logic [6:0] qyf_hexes [8];
logic [7:0] qyf_dots = 8'b1;
logic [31:0] qyf_num = 32'h1234_CDEF;
logic [15:0] qyf_keys;
logic [7:0] d_in_data [4];

seven_segment ssqhex0 (.num(qyf_num[3:0]),   .hex(qyf_hexes[0]));
seven_segment ssqhex1 (.num(qyf_num[7:4]),   .hex(qyf_hexes[1]));
seven_segment ssqhex2 (.num(qyf_num[11:8]),  .hex(qyf_hexes[2]));
seven_segment ssqhex3 (.num(qyf_num[15:12]), .hex(qyf_hexes[3]));
seven_segment ssqhex4 (.num(qyf_num[19:16]), .hex(qyf_hexes[4]));
seven_segment ssqhex5 (.num(qyf_num[23:20]), .hex(qyf_hexes[5]));
seven_segment ssqhex6 (.num(qyf_num[27:24]), .hex(qyf_hexes[6]));
seven_segment ssqhex7 (.num(qyf_num[31:28]), .hex(qyf_hexes[7]));

qyf_tm1638_controller /* #(
  // All parameters default
) */ qyf_inst (
  .clk,
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_i, .dio_o, .dio_e,
  .cs,  // Chip select (previously SS) - active low

  // QYF-TM1638 interface
  .hexes(qyf_hexes),
  .decimals(qyf_dots),
  .keys(qyf_keys),

  // Debug
  .d_in_data
);

/////////////////////////////////////////////////////////////////////
// Demo

localparam SLEEP_DELAY = 32'd5_000_000;
logic [31:0] sleep_count;

always_ff @(posedge clk) begin: rotate_periodically

  if (!reset) begin
    if (sleep_count == 0) begin
      sleep_count <= SLEEP_DELAY;

      qyf_dots <= {qyf_dots[0], qyf_dots[7:1]};

    end else begin
      sleep_count <= sleep_count - 1'd1;
    end
  end
end: rotate_periodically

// Handle keyppresses

logic [15:0] last_keys;

always_ff @(posedge clk) begin: handle_keypresses

  // Check if a key was just pressed
  last_keys <= qyf_keys;

  if (!reset) begin
    for (int i = 0, j = 8; i < 8; i++, j++) begin
      if (qyf_keys[7 - i] && qyf_keys[7 - i] != last_keys[7 - i]) begin
        // Make the digit go up
        qyf_num[(i << 2) +: 4] <= qyf_num[(i << 2) +: 4] + 4'd1;
      end else if (qyf_keys[15 - i] && qyf_keys[15 - i] != last_keys[15 - i]) begin
        // Make the digit go down
        qyf_num[(i << 2) +: 4] <= qyf_num[(i << 2) +: 4] - 4'd1;
      end
    end
  end

end: handle_keypresses

endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
