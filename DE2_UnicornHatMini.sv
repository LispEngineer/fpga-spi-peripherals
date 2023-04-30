// Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.

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

endmodule

