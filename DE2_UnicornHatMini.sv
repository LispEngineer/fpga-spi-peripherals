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

/*
See Titan Micro Electronics TM1638 Datasheet v1.3:
*/



// How many bytes we want to output at a time
parameter OUT_BYTES = 5;
parameter OUT_BYTES_SZ = $clog2(OUT_BYTES + 1);

logic reset;
assign reset = ~KEY[3];

logic sck; // Serial Clock
logic dio; // data in/out (we use it only for out FOR NOW)
logic cs;  // Chip select (previously SS) - active low

logic busy;
logic activate;
logic in_cs; // Active high for which chip(s) you want enabled
logic [7:0] out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] out_count;

logic [7:0] next_out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] next_out_count;

localparam NUM_LED_BYTES = 16;
logic [7:0] lk_leds [NUM_LED_BYTES];
logic [7:0] rotated_lk_leds [NUM_LED_BYTES];

initial begin
  for (int i = 0; i < NUM_LED_BYTES; i += 2) begin
    lk_leds[i] = '1; // Start with 1 bit set
    lk_leds[i + 1] = '0;
  end
end

// Pre-calculate our rotated LEDs
always_comb begin
  rotated_lk_leds[0] = {lk_leds[0][6:0], lk_leds[NUM_LED_BYTES - 1][7]};
  for (int i = 1; i < NUM_LED_BYTES; i++)
    rotated_lk_leds[i] = {lk_leds[i][6:0], lk_leds[i - 1][7]};
end


// Assign our physical interface to TM1638 chip
assign GPIO[25] = cs;
assign GPIO[23] = sck;
assign GPIO[21] = dio; // In the future this needs an ALTIOBUF for I/O

assign LEDG[8] = busy;
assign LEDG[7] = activate;
assign LEDG[2:0] = {dio, sck, cs};

spi_controller_ht16d35a #(
  .NUM_SELECTS(1),
  .CLK_DIV(20), // 20ns/50MHz system clock -> 400ns/2.5MHz TM1638 clock
  .OUT_BYTES(OUT_BYTES),
  .ALL_DONE_DELAY(1),
  .LSB_FIRST(1)
) ledNkey_inst (
  .clk(CLOCK_50),
  .reset,

  // SPI interface
  .sck, // Serial Clock
  .dio, // data in/out (we use it only for out FOR NOW)
  .cs,  // Chip select (previously SS) - active low

  // Controller interface
  .busy,
  .activate,
  .in_cs, // Active high for which chip(s) you want enabled
  .out_data,
  .out_count
);

localparam POWER_UP_START = 32'd50_000_000;
localparam DELAY_START = 32'd10_000_000;
logic [31:0] power_up_counter = POWER_UP_START;

typedef enum int unsigned {
  S_POWER_UP        = 0,
  S_IDLE            = 1,
  S_SEND_COMMAND    = 2,
  S_AWAIT_COMMAND   = 3,
  // TODO: Make a memory to do initialization
  S_AUTO_INCREMENT  = 4,
  S_XMIT_4          = 5,
  S_MAX_BRIGHT      = 6,
  S_ROTATE          = 7,
  S_DELAY           = 8
} state_t;

state_t lk_state = S_POWER_UP;
state_t return_after_command;
logic send_busy_seen;
logic [2:0] xmit_4_count;

assign hex_display[7:0] = lk_state;

// debug
logic [17:0] states_seen = 0;

assign LEDR = states_seen;

always_ff @(posedge CLOCK_50) begin: tm1638_main
  // NOTE: Reset logic at end

  if (!reset) states_seen[lk_state] <= '1;

  case (lk_state)

  S_POWER_UP: begin: pwr_up
    // Give the module a moment to power up
    // The datasheet may say a required startup time but I didn't quickly find it
    if (power_up_counter == 0)
      lk_state <= S_AUTO_INCREMENT;
    else
      power_up_counter <= power_up_counter - 1'd1;
  end: pwr_up

  // FIXME: I should make this send/await command into a standard module
  // that can be used for any of my interfaces. See: ScrollHatMini.
  // Maybe make it a "task"?

  S_IDLE: begin: do_idle
  end: do_idle

  S_AUTO_INCREMENT: begin: auto_incr
    next_out_data[0] <= 8'h40; // see README
    next_out_count <= 1'd1;
    lk_state <= S_SEND_COMMAND;
    return_after_command <= S_XMIT_4;
    xmit_4_count <= 0;
  end: auto_incr

  S_XMIT_4: begin: xmit_4
    next_out_data[0] <= 8'hC0 + ((8)'(xmit_4_count) << 2); // see README - ADDRESS SETTING
    next_out_data[1] <= lk_leds[(4'd1 << xmit_4_count)];
    next_out_data[2] <= lk_leds[(4'd1 << xmit_4_count) + 1];
    next_out_data[3] <= lk_leds[(4'd1 << xmit_4_count) + 2];
    next_out_data[4] <= lk_leds[(4'd1 << xmit_4_count) + 3];
    next_out_count <= 3'd5;
    lk_state <= S_SEND_COMMAND;

    if (xmit_4_count == 3) begin
      return_after_command <= S_MAX_BRIGHT;
    end else begin
      return_after_command <= S_XMIT_4;
      xmit_4_count <= xmit_4_count + 1'd1;
    end
  end: xmit_4

  S_MAX_BRIGHT: begin: max_brt
    next_out_data[0] <= 8'h8F; // see README
    next_out_count <= 1'd1;
    lk_state <= S_SEND_COMMAND;
    // return_after_command <= S_ROTATE;
    return_after_command <= S_ROTATE;
  end: max_brt

  ////////////////////////////////////////////////////////////////////////////////
  // Shifting LED pattern

  S_ROTATE: begin: do_rotate
    lk_state <= S_POWER_UP;
    lk_leds <= rotated_lk_leds;
    power_up_counter <= DELAY_START;
  end: do_rotate

  ////////////////////////////////////////////////////////////////////////////////
  // Send subroutine

  S_SEND_COMMAND: begin: send_command
    // Send a specific I2C command, and return to the specified state
    // after it is done.
    if (busy) begin
      // Wait for un-busy
      activate <= '0;
    end else begin
      out_data    <= next_out_data;
      out_count   <= next_out_count;
      in_cs       <= '1; // Only one chip
      activate    <= '1;
      lk_state       <= S_AWAIT_COMMAND;
      send_busy_seen <= '0;
    end
  end: send_command

  S_AWAIT_COMMAND: begin: await_command
    // Wait for busy to go true, then go false
    case ({send_busy_seen, busy})
    2'b01: begin: busy_starting
      // We are seeing busy for the first time
      send_busy_seen <= '1;
      activate <= '0;
    end: busy_starting
    2'b10: begin: busy_ending
      // Busy is now ending
      lk_state <= return_after_command;
    end: busy_ending
    endcase
  end: await_command

  endcase // lk_state_case

  if (reset) begin: do_reset
    power_up_counter <= POWER_UP_START;
    lk_state <= S_POWER_UP;
    states_seen <= '0;
  end: do_reset

end: tm1638_main

endmodule

