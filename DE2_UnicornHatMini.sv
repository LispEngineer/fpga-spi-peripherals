// Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module DE2_UnicornHatMini (
  //////////// CLOCK //////////
  input  logic        CLOCK_50,
  input  logic        CLOCK2_50,
  input  logic        CLOCK3_50,

  //////////// LED //////////
  output logic  [8:0] LEDG,
  output logic [17:0] LEDR,

  //////////// KEY //////////
  // These are logic 0 when pressed
  input  logic  [3:0] KEY,

  //////////// SW //////////
  input  logic [17:0] SW,

  //////////// SEG7 //////////
  // All of these use logic 0 to light up the segment
  // These are off with logic 1
  output logic  [6:0] HEX0,
  output logic  [6:0] HEX1,
  output logic  [6:0] HEX2,
  output logic  [6:0] HEX3,
  output logic  [6:0] HEX4,
  output logic  [6:0] HEX5,
  output logic  [6:0] HEX6,
  output logic  [6:0] HEX7,

	//////////// GPIO, GPIO connect to GPIO Default //////////
	inout        [35:0] GPIO
);


////////////////////////////////////////////////////////////////////////////////
// 7 Segment logic

logic [6:0] ihex0 = '0;
logic [6:0] ihex1 = '0;
logic [6:0] ihex2 = '0;
logic [6:0] ihex3 = '0;
logic [6:0] ihex4 = '0;
logic [6:0] ihex5 = '0;
logic [6:0] ihex6 = '0;
logic [6:0] ihex7 = '0;

logic [31:0] hex_display;

assign HEX0 = ~ihex0;
assign HEX1 = ~ihex1;
assign HEX2 = ~ihex2;
assign HEX3 = ~ihex3;
assign HEX4 = ~ihex4;
assign HEX5 = ~ihex5;
assign HEX6 = ~ihex6;
assign HEX7 = ~ihex7;

// Show the saved data on hex 0-3
seven_segment sshex0 (.num(hex_display[3:0]),   .hex(ihex0));
seven_segment sshex1 (.num(hex_display[7:4]),   .hex(ihex1));
seven_segment sshex2 (.num(hex_display[11:8]),  .hex(ihex2));
seven_segment sshex3 (.num(hex_display[15:12]), .hex(ihex3));
seven_segment sshex4 (.num(hex_display[19:16]), .hex(ihex4));
seven_segment sshex5 (.num(hex_display[23:20]), .hex(ihex5));
seven_segment sshex6 (.num(hex_display[27:24]), .hex(ihex6));
seven_segment sshex7 (.num(hex_display[31:28]), .hex(ihex7));

// END 7 Segment logic
/////////////////////////////////////////////////////////////////////////////////


/* 
See Holtek HT16D35A Datasheet Rev 1.22:
* Page 60 for Initialization
* Page 61 for Writing Display
* Page 5:
  * 10ms after power on reset to use the device
  * See page 8
* Page 5:
  * Clock cycle time 250ns minimum = 4MHz tCLK
  * Clock pulse width miniumum = 100ns tCW
  * Data setup/hold time = 50ns tDS/tDH
    * Input data must be stable for this long before rising clock edge
    * Starting at 10% and 90% of the voltage rise (so use fast transition times?)
  * CSB to clock time: 50ns (when starting transaction?) tCSL
    * Time after CSB goes low until the CLK can first go high
  * Clock to CSB time: 2µs (when ending transaction?) tCSH
    * Time after clock goes high (and stays high for idle) and the CSB can go high
  * "H" CBS Pulse Width: 100ns tCSW
    * Minimum time CSB can remain high after going high
  * (Omitting any data output discussion)
* Page 6: Timing diagram on the above timings
* Page 8: Data transfers on the I2C-bus or SPI 3-wire serial bus
  should be avoided for 1ms following a power-on to
  allow the reset initialisation operation to complete
* Page 19-20: Command table

Questions:
*/

///////////////////////////////////////////////////////////////////////////////
// LED & KEY (TM1638)
// See Titan Micro Electronics TM1638 Datasheet v1.3:

logic reset;
assign reset = ~KEY[3];

//////////////////////////////////////////////////////////////////////
// Assign our physical interface to TM1638 chip for LED & KEY

logic sck; // Serial Clock
logic dio_i, dio_o, dio_e;
logic cs;  // Chip select (previously SS) - active low

// Two-way I/O buffer - DO NOT USE OPEN DRAIN (it does not work with LED & KEY module)
// Datain means IN TO THE BUFFER, which would be OUT FROM THIS MODULE
// and hence OUT TO THE EXTERNAL PIN
altiobuf_dio	altiobuf_dio_inst (
	.dataio (GPIO[21]),
	.oe     (dio_e),
	.datain (dio_o),
	.dataout(dio_i)
);

assign GPIO[25] = cs;
assign GPIO[23] = sck;

// END - physical interface to TM1638 chip for LED & KEY
//////////////////////////////////////////////////////////////////////

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
  lk_big        = 8'h80;
end
`endif // IS_QUARTUS

led_n_key_controller /* #(
  // All parameters default
) */ led_n_key_inst (
  .clk(CLOCK_50),
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_i, .dio_o, .dio_e,
  .cs,  // Chip select (previously SS) - active low

  .lk_hexes,
  .lk_decimals,
  .lk_big,
  .lk_keys
);

// END LED & KEY TM1618 memory mapping
/////////////////////////////////////////////////////////////////////

// Do something fun

assign LEDR[17:10] = lk_keys;
assign LEDG[4:0] = {dio_i, dio_o, dio_e, sck, cs};
assign hex_display[7:0] = lk_keys;

localparam SLEEP_DELAY = 32'd5_000_000;
logic [31:0] sleep_count;

always_ff @(posedge CLOCK_50) begin: rotate_periodically

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
      lk_big <= {lk_big[6:0], lk_big[7]};
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
