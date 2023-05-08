// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module DE2_SPI_Peripherals (
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

  // GPIO 21 is configured to Weak Pull-Up
  // \--> Used for LED&KEY DIO as a required pull-up
  // TODO: TRY EX_IO with the 2.2KΩ external pull up
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

logic reset;
assign reset = ~KEY[3];




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

logic sck, sdo;
logic [1:0] cs;

assign GPIO[32] = cs[0];
assign GPIO[34] = cs[1];
assign GPIO[30] = sck;
assign GPIO[28] = sdo;

assign LEDG[3:0] = {sdo, ~sck, ~cs[1], ~cs[0]}; // These signal idle high so show them when low

unicorn_hat_mini_demo /* #(
  .CLK_DIV(32)
) */ uhm_inst (
  .clk(CLOCK_50),
  .reset,

  .sck, .sdo, .cs
);


///////////////////////////////////////////////////////////////////////////////
// LED & KEY (TM1638)
// See Titan Micro Electronics TM1638 Datasheet v1.3:


`ifdef USE_LEDnKEY_TOP_LEVEL

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
// LED & KEY TM1618 demo

led_n_key_demo /* #(
  // All parameters default
) */ led_n_key_inst (
  .clk(CLOCK_50),
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_i, .dio_o, .dio_e,
  .cs  // Chip select (previously SS) - active low
);

// END LED & KEY TM1618 memory mapping
/////////////////////////////////////////////////////////////////////

assign LEDG[4:0] = {dio_i, dio_o, dio_e, sck, cs};

`endif // USE_LEDnKEY_TOP_LEVEL



///////////////////////////////////////////////////////////////////////////////
// QYF-TM1638

`ifdef USE_QYF_TM1638_TOP_LEVEL

//////////////////////////////////////////////////////////////////////
// Assign our physical interface to TM1638 chip for QYF-TM1638

logic sck; // Serial Clock
logic dio_i, dio_o, dio_e;
logic cs;  // Chip select (previously SS) - active low

// Two-way I/O buffer - NOT OPEN DRAIN
// Datain means IN TO THE BUFFER, which would be OUT FROM THIS MODULE
// and hence OUT TO THE EXTERNAL PIN 
altiobuf_dio	altiobuf_dio_inst (
	.dataio (GPIO[20]),
	.oe     (dio_e),
	.datain (dio_o),
	.dataout(dio_i)
);

assign GPIO[24] = cs;
assign GPIO[22] = sck;

// END - physical interface to TM1638 chip for QYF-TM1638
//////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////
// QYF-TM1618 demo

qyf_tm1638_demo /* #(
  // All parameters default
) */ qyf_inst (
  .clk(CLOCK_50),
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio_i, .dio_o, .dio_e,
  .cs
);

assign LEDG[4:0] = {dio_i, dio_o, dio_e, sck, cs};

`endif // USE_QYF_TM1638_TOP_LEVEL


endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
