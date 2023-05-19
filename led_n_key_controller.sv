// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE
//
// LED&KEY controller - an 8 LED, 8 7-seg with decimal, 8 button device
// based on the TM1638.
// This also works with the JY-MCU/JY-LKM138/V:1.2 with the addition of the
// optional lk_bicolor. "big" will be red, and "bicolor" will be green.
//
// See Titan Micro Electronics TM1638 Datasheet v1.3.
//
// Use a two-way I/O buffer - DO NOT USE OPEN DRAIN (it does not work with LED & KEY module)
// with dio_o/i/e. Use a weak pull-up resistor on it (seems to require it for reading
// key switch inputs).
//
// Maximum useful refresh rate is about 200 Hz, although it can run a lot faster than
// that. The LED display & KEY scan rate is only about 200 Hz.


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module led_n_key_controller #(
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
  parameter DELAY_START = 32'd0_460_000,

  // DO NOT EDIT THESE
  // How many bytes of key data we read from TM1618
  parameter IN_BYTES = 4,
  parameter IN_BYTES_SZ = $clog2(IN_BYTES + 1)

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

  // TODO: Add a pulse when we start refreshing and end refreshing?
  // Or maybe just a "refreshing" flag?

  // The UI of the LED & KEY device.
  // Logic high is lit up or key pressed.
  input  logic [6:0] lk_hexes [8],
  input  logic [7:0] lk_decimals,
  input  logic [7:0] lk_big, // The big LEDs on top (green on JY-MCU)
  input  logic [7:0] lk_bicolor, // Optional: For JY-MCU/JY-LKM1638/V:1.2 this is the second color LED (red)
  output logic [7:0] lk_keys, // The keys on the LED&KEY - 1 is pressed

  // TODO: Take brightness

  // Debug outputs
  output logic [7:0] raw_data [IN_BYTES]
);


//////////////////////////////////////////////////////////////////////
// LED & KEY TM1618 memory mapping

// how many bytes we WRITE to the LED&KEY
localparam NUM_LED_BYTES = 16;

// Raw data read input from the TM1638
logic [7:0] in_data [IN_BYTES];
assign raw_data = in_data;

// Raw TM1618 output memory (16 bytes)
logic [7:0] lk_memory [NUM_LED_BYTES] = '{ default: 8'd0 };

// Handle the LED & KEY memory layout from the raw data above
always_comb begin
  for (int i = 0; i < 8; i++) begin: for1
    lk_memory[i * 2][6:0] = lk_hexes[i];
    lk_memory[i * 2][7] = lk_decimals[i];
    lk_memory[i * 2 + 1][0] = lk_big[i];     // Bit 0 for LED&KEY big red LEDs; for JY-MCU: Bit 0 = Green, Bit 1 = Red
    lk_memory[i * 2 + 1][1] = lk_bicolor[i]; // Bit 0 for LED&KEY big red LEDs; for JY-MCU: Bit 0 = Green, Bit 1 = Red
  end: for1
  // Keys are mapped: 1-4 are the 0 bits of the 4 bytes
  // 5-8 are the 4 bits of the 4 bytes
  for (int i = 0; i < 4; i++) begin: for2
    lk_keys[0 + i] = in_data[i][0];
    lk_keys[4 + i] = in_data[i][4];
  end: for2
end

// END LED & KEY TM1618 memory mapping
//////////////////////////////////////////////////////////////////////

tm1638_generic #(
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

  .tm1638_out(lk_memory),
  .tm1638_in(in_data)
);

endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
