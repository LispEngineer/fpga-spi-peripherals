// Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.
//
// Pimoroni Unicorn Hat Mini Controller
//
// See Holtek ...
//


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module unicorn_hat_mini_controller #(
  // Parameters passed to 3-wire SPI controller
  // Settings for 50MHz clk
  parameter CLK_DIV = 16,
  parameter CLK_2us = 100, // 2µs at current clock rate (50MHz = 20ns => 100)

  // How long to wait before we start using the LED&KEY in clock cycles?
  parameter POWER_UP_START = 32'd10_000_000, // 2/50ths of a second or 40ms
  // DELAY_START of 460_000 causes the state machine to cycle about 107 times a second.
  // DELAY_START of 230_000 causes the state machine to cycle about 210 times a second.
  // The TM1638 only scans the keypad once every 4.7ms or about 212 times a second.
  // (v1.3 p8)
  parameter DELAY_START = 32'd0_460_000,

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
  output logic [NUM_SELECTS-1:0] cs, // Chip select (previously SS) - active low

  // Controller inputs
  input logic [NUM_COLORS-1:0] display_mem_b[NUM_COLS][NUM_ROWS]

  // TODO: Add brightness
);

localparam OUT_BYTES = 6;
localparam OUT_BYTES_SZ = $clog2(OUT_BYTES + 1);

logic busy;
logic activate;
logic [NUM_SELECTS-1:0] in_cs;
logic [7:0] out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] out_count;

logic [7:0] next_out_data [OUT_BYTES];
logic [OUT_BYTES_SZ-1:0] next_out_count;
logic [NUM_SELECTS-1:0] next_cs;


spi_3wire_controller #(
  .CLK_DIV(CLK_DIV),
  .CLK_2us(CLK_2us),
  .NUM_SELECTS(NUM_SELECTS),
  .OUT_BYTES(OUT_BYTES),
  .OUT_BYTES_SZ(OUT_BYTES_SZ)
) uhm_spi_inst (
  .clk,
  .reset,
  
  .sck,
  .dio_o(sdo),
  .dio_i(), .dio_e(), // Unused
  .cs,

  .busy,
  .activate,
  .in_cs,
  .out_data,
  .out_count,
  .in_data(), .in_count('0) // Unused
);


// Initialization. See README.md

/*
* COM output control
  * 41 ff
* ROW output Control
  * 42 ff ff ff ff
* Binary/Gray mode
  * 31 01 (binary mode, for now)
* Clear memory (binary) - it starts up with random contents
  80 00 00 00 00 00
  80 04 00 00 00 00
  80 08 00 00 00 00
  80 0b 00 00 00 00
  80 10 00 00 00 00
  80 14 00 00 00 00
  80 18 00 00 00 00
* System control - oscillator on & display on
  * 35 03
*/


typedef enum int unsigned {
  S_POWER_UP        = 0,
  S_SEND_COMMAND    = 1,
  S_AWAIT_COMMAND   = 2,
  S_INIT_COM        = 3,
  S_INIT_ROW        = 4,
  S_INIT_BINARY     = 5,
  S_INIT_CLEAR      = 6,
  S_INIT_ON         = 7,
  S_REFRESH_MEM     = 8,
  S_DELAY           = 9,
  S_IDLE            = 10
} state_t;
localparam state_t S_INIT_START = S_INIT_COM;

state_t state = S_POWER_UP;
state_t return_after_command;
logic send_busy_seen;
logic [2:0] xmit_4_count;
logic [31:0] power_up_counter = POWER_UP_START;
logic [4:0] init_step; // FIXME: Size
localparam LAST_CLEAR = 5'd6;

localparam BINARY_MEM_LEN = 28;
localparam BINARY_MEM_SZ = $clog2(BINARY_MEM_LEN + 1);
localparam LAST_BINARY_MEM_POS = 24; // If we update by 4 bytes each time, this is the last update
// We have two chips each with its own memory, so...
logic [7:0] binary_mem [28][NUM_SELECTS];
logic [BINARY_MEM_SZ - 1:0] binary_mem_pos;
logic chip_num;

// FIXME: Combine init_step & binary_mem_pos?


// Map display memory to binary memory
// This was entirely "brute forced" by figuring out one row for one color and then copy/pasting
// instead of doing a nice generative set of "for" loops.
always_comb begin: display_memory_mapping
  // Zero everything we're not using
  for (int c = 0; c < NUM_SELECTS; c++)
    for (int m = 0; m < BINARY_MEM_LEN; m++)
      binary_mem[m][c] = '0;

  // binary_mem[loc][chip][bit] = display_mem_b[x][y][rgb]

  // Red, first row                                // Second row                                    // Third  row                                    // Fourth row                                    // Fifth  row                                    // Sixth  row                                    // Seventh row                                  
  // Left chip                                                                                                                                                                                                                                                                                                                                          
  binary_mem[8'h1b][0][3] = display_mem_b[ 0][0][2]; binary_mem[8'h1b][0][0] = display_mem_b[ 0][1][2]; binary_mem[8'h1b][0][2] = display_mem_b[ 0][2][2]; binary_mem[8'h1b][0][1] = display_mem_b[ 0][3][2]; binary_mem[8'h1b][0][4] = display_mem_b[ 0][4][2]; binary_mem[8'h1b][0][6] = display_mem_b[ 0][5][2]; binary_mem[8'h1b][0][5] = display_mem_b[ 0][6][2];
  binary_mem[8'h18][0][3] = display_mem_b[ 1][0][2]; binary_mem[8'h18][0][0] = display_mem_b[ 1][1][2]; binary_mem[8'h18][0][2] = display_mem_b[ 1][2][2]; binary_mem[8'h18][0][1] = display_mem_b[ 1][3][2]; binary_mem[8'h18][0][4] = display_mem_b[ 1][4][2]; binary_mem[8'h18][0][6] = display_mem_b[ 1][5][2]; binary_mem[8'h18][0][5] = display_mem_b[ 1][6][2];
  binary_mem[8'h01][0][3] = display_mem_b[ 2][0][2]; binary_mem[8'h01][0][0] = display_mem_b[ 2][1][2]; binary_mem[8'h01][0][2] = display_mem_b[ 2][2][2]; binary_mem[8'h01][0][1] = display_mem_b[ 2][3][2]; binary_mem[8'h01][0][4] = display_mem_b[ 2][4][2]; binary_mem[8'h01][0][6] = display_mem_b[ 2][5][2]; binary_mem[8'h01][0][5] = display_mem_b[ 2][6][2];
  binary_mem[8'h04][0][3] = display_mem_b[ 3][0][2]; binary_mem[8'h04][0][0] = display_mem_b[ 3][1][2]; binary_mem[8'h04][0][2] = display_mem_b[ 3][2][2]; binary_mem[8'h04][0][1] = display_mem_b[ 3][3][2]; binary_mem[8'h04][0][4] = display_mem_b[ 3][4][2]; binary_mem[8'h04][0][6] = display_mem_b[ 3][5][2]; binary_mem[8'h04][0][5] = display_mem_b[ 3][6][2];
  binary_mem[8'h07][0][3] = display_mem_b[ 4][0][2]; binary_mem[8'h07][0][0] = display_mem_b[ 4][1][2]; binary_mem[8'h07][0][2] = display_mem_b[ 4][2][2]; binary_mem[8'h07][0][1] = display_mem_b[ 4][3][2]; binary_mem[8'h07][0][4] = display_mem_b[ 4][4][2]; binary_mem[8'h07][0][6] = display_mem_b[ 4][5][2]; binary_mem[8'h07][0][5] = display_mem_b[ 4][6][2];
  binary_mem[8'h0a][0][3] = display_mem_b[ 5][0][2]; binary_mem[8'h0a][0][0] = display_mem_b[ 5][1][2]; binary_mem[8'h0a][0][2] = display_mem_b[ 5][2][2]; binary_mem[8'h0a][0][1] = display_mem_b[ 5][3][2]; binary_mem[8'h0a][0][4] = display_mem_b[ 5][4][2]; binary_mem[8'h0a][0][6] = display_mem_b[ 5][5][2]; binary_mem[8'h0a][0][5] = display_mem_b[ 5][6][2];
  binary_mem[8'h0d][0][3] = display_mem_b[ 6][0][2]; binary_mem[8'h0d][0][0] = display_mem_b[ 6][1][2]; binary_mem[8'h0d][0][2] = display_mem_b[ 6][2][2]; binary_mem[8'h0d][0][1] = display_mem_b[ 6][3][2]; binary_mem[8'h0d][0][4] = display_mem_b[ 6][4][2]; binary_mem[8'h0d][0][6] = display_mem_b[ 6][5][2]; binary_mem[8'h0d][0][5] = display_mem_b[ 6][6][2];
  binary_mem[8'h10][0][3] = display_mem_b[ 7][0][2]; binary_mem[8'h10][0][0] = display_mem_b[ 7][1][2]; binary_mem[8'h10][0][2] = display_mem_b[ 7][2][2]; binary_mem[8'h10][0][1] = display_mem_b[ 7][3][2]; binary_mem[8'h10][0][4] = display_mem_b[ 7][4][2]; binary_mem[8'h10][0][6] = display_mem_b[ 7][5][2]; binary_mem[8'h10][0][5] = display_mem_b[ 7][6][2];
  binary_mem[8'h13][0][3] = display_mem_b[ 8][0][2]; binary_mem[8'h13][0][0] = display_mem_b[ 8][1][2]; binary_mem[8'h13][0][2] = display_mem_b[ 8][2][2]; binary_mem[8'h13][0][1] = display_mem_b[ 8][3][2]; binary_mem[8'h13][0][4] = display_mem_b[ 8][4][2]; binary_mem[8'h13][0][6] = display_mem_b[ 8][5][2]; binary_mem[8'h13][0][5] = display_mem_b[ 8][6][2];
  // Right Chip                                    // Right Chip        0                    1      // Right Chip        2                    2      // Right Chip        1                    3      // Right Chip        4                    4      // Right Chip        6                    5      // Right Chip        5                    6     
  binary_mem[8'h1b][1][3] = display_mem_b[ 9][0][2]; binary_mem[8'h1b][1][0] = display_mem_b[ 9][1][2]; binary_mem[8'h1b][1][2] = display_mem_b[ 9][2][2]; binary_mem[8'h1b][1][1] = display_mem_b[ 9][3][2]; binary_mem[8'h1b][1][4] = display_mem_b[ 9][4][2]; binary_mem[8'h1b][1][6] = display_mem_b[ 9][5][2]; binary_mem[8'h1b][1][5] = display_mem_b[ 9][6][2];
  binary_mem[8'h18][1][3] = display_mem_b[10][0][2]; binary_mem[8'h18][1][0] = display_mem_b[10][1][2]; binary_mem[8'h18][1][2] = display_mem_b[10][2][2]; binary_mem[8'h18][1][1] = display_mem_b[10][3][2]; binary_mem[8'h18][1][4] = display_mem_b[10][4][2]; binary_mem[8'h18][1][6] = display_mem_b[10][5][2]; binary_mem[8'h18][1][5] = display_mem_b[10][6][2];
  binary_mem[8'h01][1][3] = display_mem_b[11][0][2]; binary_mem[8'h01][1][0] = display_mem_b[11][1][2]; binary_mem[8'h01][1][2] = display_mem_b[11][2][2]; binary_mem[8'h01][1][1] = display_mem_b[11][3][2]; binary_mem[8'h01][1][4] = display_mem_b[11][4][2]; binary_mem[8'h01][1][6] = display_mem_b[11][5][2]; binary_mem[8'h01][1][5] = display_mem_b[11][6][2];
  binary_mem[8'h04][1][3] = display_mem_b[12][0][2]; binary_mem[8'h04][1][0] = display_mem_b[12][1][2]; binary_mem[8'h04][1][2] = display_mem_b[12][2][2]; binary_mem[8'h04][1][1] = display_mem_b[12][3][2]; binary_mem[8'h04][1][4] = display_mem_b[12][4][2]; binary_mem[8'h04][1][6] = display_mem_b[12][5][2]; binary_mem[8'h04][1][5] = display_mem_b[12][6][2];
  binary_mem[8'h07][1][3] = display_mem_b[13][0][2]; binary_mem[8'h07][1][0] = display_mem_b[13][1][2]; binary_mem[8'h07][1][2] = display_mem_b[13][2][2]; binary_mem[8'h07][1][1] = display_mem_b[13][3][2]; binary_mem[8'h07][1][4] = display_mem_b[13][4][2]; binary_mem[8'h07][1][6] = display_mem_b[13][5][2]; binary_mem[8'h07][1][5] = display_mem_b[13][6][2];
  binary_mem[8'h0a][1][3] = display_mem_b[14][0][2]; binary_mem[8'h0a][1][0] = display_mem_b[14][1][2]; binary_mem[8'h0a][1][2] = display_mem_b[14][2][2]; binary_mem[8'h0a][1][1] = display_mem_b[14][3][2]; binary_mem[8'h0a][1][4] = display_mem_b[14][4][2]; binary_mem[8'h0a][1][6] = display_mem_b[14][5][2]; binary_mem[8'h0a][1][5] = display_mem_b[14][6][2];
  binary_mem[8'h0d][1][3] = display_mem_b[15][0][2]; binary_mem[8'h0d][1][0] = display_mem_b[15][1][2]; binary_mem[8'h0d][1][2] = display_mem_b[15][2][2]; binary_mem[8'h0d][1][1] = display_mem_b[15][3][2]; binary_mem[8'h0d][1][4] = display_mem_b[15][4][2]; binary_mem[8'h0d][1][6] = display_mem_b[15][5][2]; binary_mem[8'h0d][1][5] = display_mem_b[15][6][2];
  binary_mem[8'h10][1][3] = display_mem_b[16][0][2]; binary_mem[8'h10][1][0] = display_mem_b[16][1][2]; binary_mem[8'h10][1][2] = display_mem_b[16][2][2]; binary_mem[8'h10][1][1] = display_mem_b[16][3][2]; binary_mem[8'h10][1][4] = display_mem_b[16][4][2]; binary_mem[8'h10][1][6] = display_mem_b[16][5][2]; binary_mem[8'h10][1][5] = display_mem_b[16][6][2];
  // No 9th column on Right                        // No 9th column on R0ght                 1      // No 9th column on R2ght                 2      // No 9th column on R1ght                 3      // No 9th column on R4ght                 4      // No 9th column on R6ght                 5      // No 9th column on R5ght                 6     
  // Green, first row                              // Green, first row  0                    1      // Green, first row  2                    2      // Green, first row  1                    3      // Green, first row  4                    4      // Green, first row  6                    5      // Green, first row  5                    6     
  // Left chip                                     // Left chip         0                    1      // Left chip         2                    2      // Left chip         1                    3      // Left chip         4                    4      // Left chip         6                    5      // Left chip         5                    6     
  binary_mem[8'h1a][0][3] = display_mem_b[ 0][0][1]; binary_mem[8'h1a][0][0] = display_mem_b[ 0][1][1]; binary_mem[8'h1a][0][2] = display_mem_b[ 0][2][1]; binary_mem[8'h1a][0][1] = display_mem_b[ 0][3][1]; binary_mem[8'h1a][0][4] = display_mem_b[ 0][4][1]; binary_mem[8'h1a][0][6] = display_mem_b[ 0][5][1]; binary_mem[8'h1a][0][5] = display_mem_b[ 0][6][1];
  binary_mem[8'h17][0][3] = display_mem_b[ 1][0][1]; binary_mem[8'h17][0][0] = display_mem_b[ 1][1][1]; binary_mem[8'h17][0][2] = display_mem_b[ 1][2][1]; binary_mem[8'h17][0][1] = display_mem_b[ 1][3][1]; binary_mem[8'h17][0][4] = display_mem_b[ 1][4][1]; binary_mem[8'h17][0][6] = display_mem_b[ 1][5][1]; binary_mem[8'h17][0][5] = display_mem_b[ 1][6][1];
  binary_mem[8'h03][0][3] = display_mem_b[ 2][0][1]; binary_mem[8'h03][0][0] = display_mem_b[ 2][1][1]; binary_mem[8'h03][0][2] = display_mem_b[ 2][2][1]; binary_mem[8'h03][0][1] = display_mem_b[ 2][3][1]; binary_mem[8'h03][0][4] = display_mem_b[ 2][4][1]; binary_mem[8'h03][0][6] = display_mem_b[ 2][5][1]; binary_mem[8'h03][0][5] = display_mem_b[ 2][6][1];
  binary_mem[8'h06][0][3] = display_mem_b[ 3][0][1]; binary_mem[8'h06][0][0] = display_mem_b[ 3][1][1]; binary_mem[8'h06][0][2] = display_mem_b[ 3][2][1]; binary_mem[8'h06][0][1] = display_mem_b[ 3][3][1]; binary_mem[8'h06][0][4] = display_mem_b[ 3][4][1]; binary_mem[8'h06][0][6] = display_mem_b[ 3][5][1]; binary_mem[8'h06][0][5] = display_mem_b[ 3][6][1];
  binary_mem[8'h09][0][3] = display_mem_b[ 4][0][1]; binary_mem[8'h09][0][0] = display_mem_b[ 4][1][1]; binary_mem[8'h09][0][2] = display_mem_b[ 4][2][1]; binary_mem[8'h09][0][1] = display_mem_b[ 4][3][1]; binary_mem[8'h09][0][4] = display_mem_b[ 4][4][1]; binary_mem[8'h09][0][6] = display_mem_b[ 4][5][1]; binary_mem[8'h09][0][5] = display_mem_b[ 4][6][1];
  binary_mem[8'h0c][0][3] = display_mem_b[ 5][0][1]; binary_mem[8'h0c][0][0] = display_mem_b[ 5][1][1]; binary_mem[8'h0c][0][2] = display_mem_b[ 5][2][1]; binary_mem[8'h0c][0][1] = display_mem_b[ 5][3][1]; binary_mem[8'h0c][0][4] = display_mem_b[ 5][4][1]; binary_mem[8'h0c][0][6] = display_mem_b[ 5][5][1]; binary_mem[8'h0c][0][5] = display_mem_b[ 5][6][1];
  binary_mem[8'h0f][0][3] = display_mem_b[ 6][0][1]; binary_mem[8'h0f][0][0] = display_mem_b[ 6][1][1]; binary_mem[8'h0f][0][2] = display_mem_b[ 6][2][1]; binary_mem[8'h0f][0][1] = display_mem_b[ 6][3][1]; binary_mem[8'h0f][0][4] = display_mem_b[ 6][4][1]; binary_mem[8'h0f][0][6] = display_mem_b[ 6][5][1]; binary_mem[8'h0f][0][5] = display_mem_b[ 6][6][1];
  binary_mem[8'h12][0][3] = display_mem_b[ 7][0][1]; binary_mem[8'h12][0][0] = display_mem_b[ 7][1][1]; binary_mem[8'h12][0][2] = display_mem_b[ 7][2][1]; binary_mem[8'h12][0][1] = display_mem_b[ 7][3][1]; binary_mem[8'h12][0][4] = display_mem_b[ 7][4][1]; binary_mem[8'h12][0][6] = display_mem_b[ 7][5][1]; binary_mem[8'h12][0][5] = display_mem_b[ 7][6][1];
  binary_mem[8'h15][0][3] = display_mem_b[ 8][0][1]; binary_mem[8'h15][0][0] = display_mem_b[ 8][1][1]; binary_mem[8'h15][0][2] = display_mem_b[ 8][2][1]; binary_mem[8'h15][0][1] = display_mem_b[ 8][3][1]; binary_mem[8'h15][0][4] = display_mem_b[ 8][4][1]; binary_mem[8'h15][0][6] = display_mem_b[ 8][5][1]; binary_mem[8'h15][0][5] = display_mem_b[ 8][6][1];
  // Right Chip                                    // Right Chip        0                    1      // Right Chip        2                    2      // Right Chip        1                    3      // Right Chip        4                    4      // Right Chip        6                    5      // Right Chip        5                    6     
  binary_mem[8'h1a][1][3] = display_mem_b[ 9][0][1]; binary_mem[8'h1a][1][0] = display_mem_b[ 9][1][1]; binary_mem[8'h1a][1][2] = display_mem_b[ 9][2][1]; binary_mem[8'h1a][1][1] = display_mem_b[ 9][3][1]; binary_mem[8'h1a][1][4] = display_mem_b[ 9][4][1]; binary_mem[8'h1a][1][6] = display_mem_b[ 9][5][1]; binary_mem[8'h1a][1][5] = display_mem_b[ 9][6][1];
  binary_mem[8'h17][1][3] = display_mem_b[10][0][1]; binary_mem[8'h17][1][0] = display_mem_b[10][1][1]; binary_mem[8'h17][1][2] = display_mem_b[10][2][1]; binary_mem[8'h17][1][1] = display_mem_b[10][3][1]; binary_mem[8'h17][1][4] = display_mem_b[10][4][1]; binary_mem[8'h17][1][6] = display_mem_b[10][5][1]; binary_mem[8'h17][1][5] = display_mem_b[10][6][1];
  binary_mem[8'h03][1][3] = display_mem_b[11][0][1]; binary_mem[8'h03][1][0] = display_mem_b[11][1][1]; binary_mem[8'h03][1][2] = display_mem_b[11][2][1]; binary_mem[8'h03][1][1] = display_mem_b[11][3][1]; binary_mem[8'h03][1][4] = display_mem_b[11][4][1]; binary_mem[8'h03][1][6] = display_mem_b[11][5][1]; binary_mem[8'h03][1][5] = display_mem_b[11][6][1];
  binary_mem[8'h06][1][3] = display_mem_b[12][0][1]; binary_mem[8'h06][1][0] = display_mem_b[12][1][1]; binary_mem[8'h06][1][2] = display_mem_b[12][2][1]; binary_mem[8'h06][1][1] = display_mem_b[12][3][1]; binary_mem[8'h06][1][4] = display_mem_b[12][4][1]; binary_mem[8'h06][1][6] = display_mem_b[12][5][1]; binary_mem[8'h06][1][5] = display_mem_b[12][6][1];
  binary_mem[8'h09][1][3] = display_mem_b[13][0][1]; binary_mem[8'h09][1][0] = display_mem_b[13][1][1]; binary_mem[8'h09][1][2] = display_mem_b[13][2][1]; binary_mem[8'h09][1][1] = display_mem_b[13][3][1]; binary_mem[8'h09][1][4] = display_mem_b[13][4][1]; binary_mem[8'h09][1][6] = display_mem_b[13][5][1]; binary_mem[8'h09][1][5] = display_mem_b[13][6][1];
  binary_mem[8'h0c][1][3] = display_mem_b[14][0][1]; binary_mem[8'h0c][1][0] = display_mem_b[14][1][1]; binary_mem[8'h0c][1][2] = display_mem_b[14][2][1]; binary_mem[8'h0c][1][1] = display_mem_b[14][3][1]; binary_mem[8'h0c][1][4] = display_mem_b[14][4][1]; binary_mem[8'h0c][1][6] = display_mem_b[14][5][1]; binary_mem[8'h0c][1][5] = display_mem_b[14][6][1];
  binary_mem[8'h0f][1][3] = display_mem_b[15][0][1]; binary_mem[8'h0f][1][0] = display_mem_b[15][1][1]; binary_mem[8'h0f][1][2] = display_mem_b[15][2][1]; binary_mem[8'h0f][1][1] = display_mem_b[15][3][1]; binary_mem[8'h0f][1][4] = display_mem_b[15][4][1]; binary_mem[8'h0f][1][6] = display_mem_b[15][5][1]; binary_mem[8'h0f][1][5] = display_mem_b[15][6][1];
  binary_mem[8'h12][1][3] = display_mem_b[16][0][1]; binary_mem[8'h12][1][0] = display_mem_b[16][1][1]; binary_mem[8'h12][1][2] = display_mem_b[16][2][1]; binary_mem[8'h12][1][1] = display_mem_b[16][3][1]; binary_mem[8'h12][1][4] = display_mem_b[16][4][1]; binary_mem[8'h12][1][6] = display_mem_b[16][5][1]; binary_mem[8'h12][1][5] = display_mem_b[16][6][1];
  // No 9th column on Right                        // No 9th column on R0ght                 1      // No 9th column on R2ght                 2      // No 9th column on R1ght                 3      // No 9th column on R4ght                 4      // No 9th column on R6ght                 5      // No 9th column on R5ght                 6     
  // Blue, first row                               // Blue, first row   0                    1      // Blue, first row   2                    2      // Blue, first row   1                    3      // Blue, first row   4                    4      // Blue, first row   6                    5      // Blue, first row   5                    6     
  // Left chip                                     // Left chip         0                    1      // Left chip         2                    2      // Left chip         1                    3      // Left chip         4                    4      // Left chip         6                    5      // Left chip         5                    6     
  binary_mem[8'h19][0][3] = display_mem_b[ 0][0][0]; binary_mem[8'h19][0][0] = display_mem_b[ 0][1][0]; binary_mem[8'h19][0][2] = display_mem_b[ 0][2][0]; binary_mem[8'h19][0][1] = display_mem_b[ 0][3][0]; binary_mem[8'h19][0][4] = display_mem_b[ 0][4][0]; binary_mem[8'h19][0][6] = display_mem_b[ 0][5][0]; binary_mem[8'h19][0][5] = display_mem_b[ 0][6][0];
  binary_mem[8'h16][0][3] = display_mem_b[ 1][0][0]; binary_mem[8'h16][0][0] = display_mem_b[ 1][1][0]; binary_mem[8'h16][0][2] = display_mem_b[ 1][2][0]; binary_mem[8'h16][0][1] = display_mem_b[ 1][3][0]; binary_mem[8'h16][0][4] = display_mem_b[ 1][4][0]; binary_mem[8'h16][0][6] = display_mem_b[ 1][5][0]; binary_mem[8'h16][0][5] = display_mem_b[ 1][6][0];
  binary_mem[8'h02][0][3] = display_mem_b[ 2][0][0]; binary_mem[8'h02][0][0] = display_mem_b[ 2][1][0]; binary_mem[8'h02][0][2] = display_mem_b[ 2][2][0]; binary_mem[8'h02][0][1] = display_mem_b[ 2][3][0]; binary_mem[8'h02][0][4] = display_mem_b[ 2][4][0]; binary_mem[8'h02][0][6] = display_mem_b[ 2][5][0]; binary_mem[8'h02][0][5] = display_mem_b[ 2][6][0];
  binary_mem[8'h05][0][3] = display_mem_b[ 3][0][0]; binary_mem[8'h05][0][0] = display_mem_b[ 3][1][0]; binary_mem[8'h05][0][2] = display_mem_b[ 3][2][0]; binary_mem[8'h05][0][1] = display_mem_b[ 3][3][0]; binary_mem[8'h05][0][4] = display_mem_b[ 3][4][0]; binary_mem[8'h05][0][6] = display_mem_b[ 3][5][0]; binary_mem[8'h05][0][5] = display_mem_b[ 3][6][0];
  binary_mem[8'h08][0][3] = display_mem_b[ 4][0][0]; binary_mem[8'h08][0][0] = display_mem_b[ 4][1][0]; binary_mem[8'h08][0][2] = display_mem_b[ 4][2][0]; binary_mem[8'h08][0][1] = display_mem_b[ 4][3][0]; binary_mem[8'h08][0][4] = display_mem_b[ 4][4][0]; binary_mem[8'h08][0][6] = display_mem_b[ 4][5][0]; binary_mem[8'h08][0][5] = display_mem_b[ 4][6][0];
  binary_mem[8'h0b][0][3] = display_mem_b[ 5][0][0]; binary_mem[8'h0b][0][0] = display_mem_b[ 5][1][0]; binary_mem[8'h0b][0][2] = display_mem_b[ 5][2][0]; binary_mem[8'h0b][0][1] = display_mem_b[ 5][3][0]; binary_mem[8'h0b][0][4] = display_mem_b[ 5][4][0]; binary_mem[8'h0b][0][6] = display_mem_b[ 5][5][0]; binary_mem[8'h0b][0][5] = display_mem_b[ 5][6][0];
  binary_mem[8'h0e][0][3] = display_mem_b[ 6][0][0]; binary_mem[8'h0e][0][0] = display_mem_b[ 6][1][0]; binary_mem[8'h0e][0][2] = display_mem_b[ 6][2][0]; binary_mem[8'h0e][0][1] = display_mem_b[ 6][3][0]; binary_mem[8'h0e][0][4] = display_mem_b[ 6][4][0]; binary_mem[8'h0e][0][6] = display_mem_b[ 6][5][0]; binary_mem[8'h0e][0][5] = display_mem_b[ 6][6][0];
  binary_mem[8'h11][0][3] = display_mem_b[ 7][0][0]; binary_mem[8'h11][0][0] = display_mem_b[ 7][1][0]; binary_mem[8'h11][0][2] = display_mem_b[ 7][2][0]; binary_mem[8'h11][0][1] = display_mem_b[ 7][3][0]; binary_mem[8'h11][0][4] = display_mem_b[ 7][4][0]; binary_mem[8'h11][0][6] = display_mem_b[ 7][5][0]; binary_mem[8'h11][0][5] = display_mem_b[ 7][6][0];
  binary_mem[8'h14][0][3] = display_mem_b[ 8][0][0]; binary_mem[8'h14][0][0] = display_mem_b[ 8][1][0]; binary_mem[8'h14][0][2] = display_mem_b[ 8][2][0]; binary_mem[8'h14][0][1] = display_mem_b[ 8][3][0]; binary_mem[8'h14][0][4] = display_mem_b[ 8][4][0]; binary_mem[8'h14][0][6] = display_mem_b[ 8][5][0]; binary_mem[8'h14][0][5] = display_mem_b[ 8][6][0];
  // Right Chip                                    // Right Chip        0                    1      // Right Chip        2                    2      // Right Chip        1                    3      // Right Chip        4                    4      // Right Chip        6                    5      // Right Chip        5                    6     
  binary_mem[8'h19][1][3] = display_mem_b[ 9][0][0]; binary_mem[8'h19][1][0] = display_mem_b[ 9][1][0]; binary_mem[8'h19][1][2] = display_mem_b[ 9][2][0]; binary_mem[8'h19][1][1] = display_mem_b[ 9][3][0]; binary_mem[8'h19][1][4] = display_mem_b[ 9][4][0]; binary_mem[8'h19][1][6] = display_mem_b[ 9][5][0]; binary_mem[8'h19][1][5] = display_mem_b[ 9][6][0];
  binary_mem[8'h16][1][3] = display_mem_b[10][0][0]; binary_mem[8'h16][1][0] = display_mem_b[10][1][0]; binary_mem[8'h16][1][2] = display_mem_b[10][2][0]; binary_mem[8'h16][1][1] = display_mem_b[10][3][0]; binary_mem[8'h16][1][4] = display_mem_b[10][4][0]; binary_mem[8'h16][1][6] = display_mem_b[10][5][0]; binary_mem[8'h16][1][5] = display_mem_b[10][6][0];
  binary_mem[8'h02][1][3] = display_mem_b[11][0][0]; binary_mem[8'h02][1][0] = display_mem_b[11][1][0]; binary_mem[8'h02][1][2] = display_mem_b[11][2][0]; binary_mem[8'h02][1][1] = display_mem_b[11][3][0]; binary_mem[8'h02][1][4] = display_mem_b[11][4][0]; binary_mem[8'h02][1][6] = display_mem_b[11][5][0]; binary_mem[8'h02][1][5] = display_mem_b[11][6][0];
  binary_mem[8'h05][1][3] = display_mem_b[12][0][0]; binary_mem[8'h05][1][0] = display_mem_b[12][1][0]; binary_mem[8'h05][1][2] = display_mem_b[12][2][0]; binary_mem[8'h05][1][1] = display_mem_b[12][3][0]; binary_mem[8'h05][1][4] = display_mem_b[12][4][0]; binary_mem[8'h05][1][6] = display_mem_b[12][5][0]; binary_mem[8'h05][1][5] = display_mem_b[12][6][0];
  binary_mem[8'h08][1][3] = display_mem_b[13][0][0]; binary_mem[8'h08][1][0] = display_mem_b[13][1][0]; binary_mem[8'h08][1][2] = display_mem_b[13][2][0]; binary_mem[8'h08][1][1] = display_mem_b[13][3][0]; binary_mem[8'h08][1][4] = display_mem_b[13][4][0]; binary_mem[8'h08][1][6] = display_mem_b[13][5][0]; binary_mem[8'h08][1][5] = display_mem_b[13][6][0];
  binary_mem[8'h0b][1][3] = display_mem_b[14][0][0]; binary_mem[8'h0b][1][0] = display_mem_b[14][1][0]; binary_mem[8'h0b][1][2] = display_mem_b[14][2][0]; binary_mem[8'h0b][1][1] = display_mem_b[14][3][0]; binary_mem[8'h0b][1][4] = display_mem_b[14][4][0]; binary_mem[8'h0b][1][6] = display_mem_b[14][5][0]; binary_mem[8'h0b][1][5] = display_mem_b[14][6][0];
  binary_mem[8'h0e][1][3] = display_mem_b[15][0][0]; binary_mem[8'h0e][1][0] = display_mem_b[15][1][0]; binary_mem[8'h0e][1][2] = display_mem_b[15][2][0]; binary_mem[8'h0e][1][1] = display_mem_b[15][3][0]; binary_mem[8'h0e][1][4] = display_mem_b[15][4][0]; binary_mem[8'h0e][1][6] = display_mem_b[15][5][0]; binary_mem[8'h0e][1][5] = display_mem_b[15][6][0];
  binary_mem[8'h11][1][3] = display_mem_b[16][0][0]; binary_mem[8'h11][1][0] = display_mem_b[16][1][0]; binary_mem[8'h11][1][2] = display_mem_b[16][2][0]; binary_mem[8'h11][1][1] = display_mem_b[16][3][0]; binary_mem[8'h11][1][4] = display_mem_b[16][4][0]; binary_mem[8'h11][1][6] = display_mem_b[16][5][0]; binary_mem[8'h11][1][5] = display_mem_b[16][6][0];
  // No 9th column on Right
end: display_memory_mapping


////////////////////////////////////////////////////////////////////////////
// Main UHM state machine

always_ff @(posedge clk) begin: uhm_main
  // NOTE: Reset logic at end

  case (state)

  S_POWER_UP: begin: pwr_up
    // Give the module a moment to power up
    // The datasheet may say a required startup time but I didn't quickly find it
    if (power_up_counter == 0) begin
      state <= S_INIT_START;
      init_step <= '0;
    end else
      power_up_counter <= power_up_counter - 1'd1;
  end: pwr_up

  ////////////////////////////////////////////////////////////////////////////////
  // Initialization

  S_INIT_COM: begin: do_init_com
    next_out_count       <= (OUT_BYTES_SZ)'(2);
    next_out_data[0]     <= 8'h41;
    next_out_data[1]     <= 8'hff;
    next_cs              <= '1; // Both chips
    state                <= S_SEND_COMMAND;
    return_after_command <= S_INIT_ROW;
  end: do_init_com

  S_INIT_ROW: begin: do_init_row
    next_out_count       <= (OUT_BYTES_SZ)'(5);
    next_out_data[0]     <= 8'h42;
    next_out_data[1]     <= 8'hff;
    next_out_data[2]     <= 8'hff;
    next_out_data[3]     <= 8'hff;
    next_out_data[4]     <= 8'hff;
    next_cs              <= '1; // Both chips
    state                <= S_SEND_COMMAND;
    return_after_command <= S_INIT_BINARY;
  end: do_init_row

  S_INIT_BINARY: begin: do_init_binary
    next_out_count       <= (OUT_BYTES_SZ)'(2);
    next_out_data[0]     <= 8'h31;
    next_out_data[1]     <= 8'h01;
    next_cs              <= '1; // Both chips
    state                <= S_SEND_COMMAND;
    return_after_command <= S_INIT_CLEAR;
    init_step            <= '0;
  end: do_init_binary

  S_INIT_CLEAR: begin: do_init_clear
    // Binary data has 28 bytes to clear
    next_out_count       <= (OUT_BYTES_SZ)'(6);
    next_out_data[0]     <= 8'h80;
    next_out_data[1]     <= 8'(init_step) << 2;
    next_out_data[2]     <= 8'h00;
    next_out_data[3]     <= 8'h00;
    next_out_data[4]     <= 8'h00;
    next_out_data[5]     <= 8'h00;
    next_cs              <= '1; // Both chips
    state                <= S_SEND_COMMAND;
    init_step            <= init_step + 1'd1;
    if (init_step == LAST_CLEAR)
      return_after_command <= S_INIT_ON;
    else
      return_after_command <= S_INIT_CLEAR;
  end: do_init_clear

  S_INIT_ON: begin: do_init_on
    next_out_count       <= (OUT_BYTES_SZ)'(2);
    next_out_data[0]     <= 8'h35;
    next_out_data[1]     <= 8'h03;
    next_cs              <= '1; // Both chips
    state                <= S_SEND_COMMAND;
    return_after_command <= S_DELAY;
    power_up_counter     <= DELAY_START;
  end: do_init_on

  ////////////////////////////////////////////////////////////////////////////////
  // Memory refresher
  //
  // FIXME: This is super inefficient but works

  S_REFRESH_MEM: begin: do_refresh_mem
    // Binary data has 28 bytes to clear
    next_out_count       <= (OUT_BYTES_SZ)'(6);
    next_out_data[0]     <= 8'h80;
    next_out_data[1]     <= 8'(binary_mem_pos);
    next_out_data[2]     <= binary_mem[binary_mem_pos + 0][chip_num];
    next_out_data[3]     <= binary_mem[binary_mem_pos + 1][chip_num];
    next_out_data[4]     <= binary_mem[binary_mem_pos + 2][chip_num];
    next_out_data[5]     <= binary_mem[binary_mem_pos + 3][chip_num];
    next_cs              <= chip_num ? 2'b10 : 2'b01; // Chip 0 == left half
    state                <= S_SEND_COMMAND;
    binary_mem_pos       <= binary_mem_pos + (BINARY_MEM_SZ)'(4);
    if (binary_mem_pos >= LAST_BINARY_MEM_POS) begin
      if (chip_num) begin
        return_after_command <= S_DELAY;
        power_up_counter <= DELAY_START;
      end else begin
        chip_num <= '1; // Do the other chip
        binary_mem_pos <= '0;
        return_after_command <= S_REFRESH_MEM;
      end
    end else begin
      return_after_command <= S_REFRESH_MEM;
    end
  end: do_refresh_mem


  S_DELAY: begin: do_delay
    // FIXME: Combine this with the power up step as a subroutine?
    if (power_up_counter == 0) begin
      state <= S_REFRESH_MEM;
      binary_mem_pos <= '0;
      chip_num <= '0;
    end else
      power_up_counter <= power_up_counter - 1'd1;
  end: do_delay


  S_IDLE: begin end

  ////////////////////////////////////////////////////////////////////////////////
  // Send subroutine

  S_SEND_COMMAND: begin: send_command
    // Send a specific I2C command, and return to the specified state
    // after it is done.
    if (busy) begin
      // Wait for un-busy
      activate <= '0;
    end else begin
      out_data       <= next_out_data;
      out_count      <= next_out_count;
      in_cs          <= next_cs;
      activate       <= '1;
      state          <= S_AWAIT_COMMAND;
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
      state <= return_after_command;
    end: busy_ending
    endcase
  end: await_command

  endcase // state_case

  // RESET //////////////////////////////////////////////////////////

  if (reset) begin: do_reset
    power_up_counter <= POWER_UP_START;
    state <= S_POWER_UP;
  end: do_reset

end: uhm_main




endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
