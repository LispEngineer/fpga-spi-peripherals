// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE
//
// Little demo to flick the lights and use the switches on the LED&KEY board.


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module led_n_key_demo #(
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
  output logic cs,    // Chip select (previously SS) - active low

  // Debug outputs
  output logic [7:0] raw_data [4]  
);

//////////////////////////////////////////////////////////////////////
// LED & KEY TM1618 controller, display outputs & key inputs

// Easy UI to the LED & KEY outputs
logic [6:0] lk_hexes [8];
logic [7:0] lk_decimals;
logic [7:0] lk_big; // The big LEDs on top
logic [7:0] lk_keys; // The keys on the LED&KEY - 1 is pressed

`ifdef IS_QUARTUS
// QuestaSim doesn't like initial blocks (vlog-7061)
initial begin
  for (int i = 0; i < 7; i++)
    lk_hexes[i] = 7'b1 << i;
  lk_hexes[7]   = 7'b1;
  lk_decimals   = 8'b1;
end
`endif // IS_QUARTUS

assign lk_big = lk_keys;

led_n_key_controller #(
  .CLK_DIV(CLK_DIV),
  .CLK_2us(CLK_2us),
  .POWER_UP_START(POWER_UP_START),
  .DELAY_START(DELAY_START)
) led_n_key_inst (
  .clk,
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_i, .dio_o, .dio_e,
  .cs,  // Chip select (previously SS) - active low

  .lk_hexes,
  .lk_decimals,
  .lk_big,
  .lk_keys,

  .raw_data
);

/////////////////////////////////////////////////////////////////////
// Demo

localparam SLEEP_DELAY = 32'd5_000_000;
logic [31:0] sleep_count;

always_ff @(posedge clk) begin: rotate_periodically

  if (!reset) begin
    if (sleep_count == 0) begin
      sleep_count <= SLEEP_DELAY;

      // Rotate everything in our display for fun
      for (int i = 0; i < 8; i++) begin
        // Make the outside circle around
        lk_hexes[i][5:0] <= {lk_hexes[i][4:0], lk_hexes[i][5]};
        // Make center dash move around
        lk_hexes[i + 1 >= 8 ? i + 1 - 8 : i + 1][6] <= lk_hexes[i][6];
      end
      lk_decimals <= {lk_decimals[0], lk_decimals[7:1]};

    end else begin
      sleep_count <= sleep_count - 1'd1;
    end
  end
end: rotate_periodically

endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
