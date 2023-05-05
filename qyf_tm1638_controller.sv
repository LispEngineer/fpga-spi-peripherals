// Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.
//
// QYF-TM1638 controller
//
// See Titan Micro Electronics TM1638 Datasheet v1.3.
//
// Use a two-way I/O buffer.
// TODO: Open drain?
// TODO: Weak pull-up?
// TODO: External pull-up?


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module qyf_tm1638_controller #(
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

  // TODO: Add a pulse when we start refreshing and end refreshing?
  // Or maybe just a "refreshing" flag?

  // The UI of the QYF-TM1638 device.
  // Logic high is lit up or key pressed.
  // Hex 7 is the first hex (leftmost) and Hex 0 is the last hex (rightmost)
  input  logic  [6:0] hexes [8],
  // Decimal 7 is the first display (leftmost) and decimal 0 is the last one (rightmost)
  input  logic  [7:0] decimals,
  output logic [15:0] keys, // The keys on the device - 1 is pressed

  // TODO: Take brightness

  // DEBUG outputs
  output logic [7:0] d_in_data [4]
);


//////////////////////////////////////////////////////////////////////
// QYF-TM1618 memory mapping

localparam NUM_LED_BYTES = 16;
// How many bytes of key data we read from TM1618
localparam IN_BYTES = 4;
localparam IN_BYTES_SZ = $clog2(IN_BYTES + 1);

// Raw data read input from the TM1638
logic [7:0] in_data [IN_BYTES];
assign d_in_data = in_data;

// Raw TM1618 output memory (16 bytes)
logic [7:0] out_memory [NUM_LED_BYTES];

always_comb begin: qyf_memory_model
  // The bits in a byte are MSB - MS7-seg to LSB - LS7-seg
  for (int i = 0; i < 8; i++) begin: for1
    // First one is all the top segments
    out_memory[ 0][i] = hexes[i][0];
    out_memory[ 2][i] = hexes[i][1];
    out_memory[ 4][i] = hexes[i][2];
    out_memory[ 6][i] = hexes[i][3];
    out_memory[ 8][i] = hexes[i][4];
    out_memory[10][i] = hexes[i][5];
    out_memory[12][i] = hexes[i][6];
    out_memory[14][i] = decimals[i];
    out_memory[(i << 1) + 1] = '0; // Every other byte not used
  end: for1
  for (int i = 0; i < 4; i++) begin: for2
    keys[(i << 1) + 0] = in_data[i][2]; // 04
    keys[(i << 1) + 1] = in_data[i][6]; // 40
    keys[(i << 1) + 8] = in_data[i][1]; // 02 
    keys[(i << 1) + 9] = in_data[i][5]; // 20
  end: for2
end: qyf_memory_model

/*
// Figure out the encoding
always_comb begin
  for (int i = 0; i < NUM_LED_BYTES; i++)
    out_memory[i] = '0;
  // Byte 0 is all the top "a" LEDs in the 7-seg
  // Bit 7 is the first (left-most), bit 0 is the last (right-most)
  out_memory[0] = 8'b1100_1010;
  // Byte 1 not used
  // Byte 2 is the top-right "b" LEDs in the 7 segs
  out_memory[2] = 8'b0011_1010;
  // Byte 4 is "c" LED
  out_memory[4] = 8'b1010_1100;
  // Byte 6 is "d" LED
  out_memory[6] = 8'b0110_1001;
end
*/

// END memory mapping
//////////////////////////////////////////////////////////////////////

tm1638_generic #(
  .CLK_DIV(CLK_DIV),
  .CLK_2us(CLK_2us),
  .POWER_UP_START(POWER_UP_START),
  .DELAY_START(DELAY_START)
) qyf_tm1638_inst (
  .clk,
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_i, .dio_o, .dio_e,
  .cs,  // Chip select (previously SS) - active low

  .tm1638_out(out_memory),
  .tm1638_in(in_data)
);

/////////////////////////////////////////////////////////////////////
// Demo

/*
localparam SLEEP_DELAY = 32'd5_000_000;
logic [31:0] sleep_count;

always_ff @(posedge clk) begin: rotate_periodically

  if (!reset) begin
    if (sleep_count == 0) begin
      sleep_count <= SLEEP_DELAY;

      // Rotate everything in our display for fun
      for (int i = 0; i < NUM_LED_BYTES; i++) begin
        out_memory[i] <= 
          {out_memory[i][6:0], out_memory[i + 1 >= NUM_LED_BYTES ? i + 1 - NUM_LED_BYTES : i + 1][7]};
      end

    end else begin
      sleep_count <= sleep_count - 1'd1;
    end
  end
end: rotate_periodically
*/

endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
