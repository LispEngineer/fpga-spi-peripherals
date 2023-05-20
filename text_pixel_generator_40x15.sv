// Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer
// Licensed under Solderpad Hardware License 2.1 - see LICENSE
//
// Text pixel delivery from character memory.
//
// Font used is IBM Code Page 437 https://en.wikipedia.org/wiki/Code_page_437
// with two additions:
// Char 8'h00 = empty box, except for the last column
// Char 8'hFF = five full-width horizontal lines
// (these are blank in the original font)
//
// The font size is 8x16 for ease of display, rather than

// When the inputs TOGGLE, it will then (with appropriate latency)
// output the next character and the pixels for the row for those
// characters.
//
// This is done because this may be called from a module which uses
// a divider of the input clock (here) such that it can't easily use
// a single-cycle ready signal or any other single-cycle live signal
// (as in an AXI stream, or an Altera FIFO read).

// TODO: Figure out how to parameterize a 2-port RAM to have different
// size according to TEXT_WIDTH & _HEIGHT.

// TODO: Add color to each text character

// For testing: Characters

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module text_pixel_generator_40x15 #(
  // DO NOT CHANGE THESE
  parameter TEXT_WIDTH  = 40,
  parameter TEXT_HEIGHT = 15,
  parameter TEXT_LEN = TEXT_WIDTH * TEXT_HEIGHT,
  parameter TEXT_SZ = $clog2(TEXT_LEN)
) (
  input  logic clk,
  input  logic reset,

  // Inputs to the text pixel generator.
  // If these both toggle at the same time, only restart will be actioned.
  input  logic toggle_restart,
  input  logic toggle_next,

  // Outputs from the text pixel generator
  output logic [7:0] cur_char,   // One (extended) ASCII character
  output logic [7:0] cur_pixels, // One character's width of pixels

  // Memory write interface to text RAM
  input logic               clk_text_wr,
  input logic               text_wr_ena,
  input logic         [7:0] text_wr_data,
  input logic [TEXT_SZ-1:0] text_wr_addr
);

// The screen is this & each character is this big
localparam CHAR_WIDTH = 8;
localparam CHAR_HEIGHT = 16;
localparam CHAR_HEIGHT_SZ = $clog2(CHAR_HEIGHT);

localparam TEXT_WIDTH_SZ = $clog2(TEXT_WIDTH);
localparam TEXT_HEIGHT_SZ = $clog2(TEXT_HEIGHT);


/////////////////////////////////////////////////////////////////////
// Text RAM
//
// Currently does not use a registered output

logic [TEXT_SZ-1:0] text_rd_address;
logic [7:0] char; // Character we will show
assign cur_char = char;

text_ram_40x15 text_ram_inst (
  // RAM has two clock domains
	.wrclock  (clk_text_wr),
	.data     (text_wr_data),
	.wraddress(text_wr_addr),
	.wren     (text_wr_ena),

	.rdclock  (clk),
	.rdaddress(text_rd_address),
	.q        (char)
);

/////////////////////////////////////////////////////////////////////
// Character ROM
//
// Output is not registered

// 4096 byte ROM = 16 height x 256 characters (x 8 width_bits)

localparam ROM_ADDR_SZ = 12;

logic [ROM_ADDR_SZ-1:0] rom_rd_addr;
logic [7:0] rom_data;
assign cur_pixels = rom_data;

character_rom	character_rom_inst (
	.clock  (clk),
	.address(rom_rd_addr),
	.q      (rom_data)
);

/////////////////////////////////////////////////////////////////////
// Character pixel generator state machine

// Count height pixel rows before moving to the next text memory row
localparam LAST_TEXT_COL = (TEXT_WIDTH_SZ)'(TEXT_WIDTH - 1);
localparam LAST_PIXEL_ROW = (CHAR_HEIGHT_SZ)'(CHAR_HEIGHT - 1);

// Registers
logic [CHAR_HEIGHT_SZ:0] pixel_row; // 0-15
logic [TEXT_WIDTH_SZ-1:0] text_col;
logic [TEXT_HEIGHT_SZ-1:0] text_row;
logic [TEXT_SZ-1:0] text_rd_row_start;
logic last_restart = '0;
logic last_next = '0;

// Combinational
logic [TEXT_SZ-1:0] next_text_rd_row_start;

// We always read the ROM address for the specific character
// (which has a number of ROM addresses) for the specific
// pixel row we're reading from now.
always_comb begin: calc_rom_addr
  rom_rd_addr = (ROM_ADDR_SZ)'((char * CHAR_HEIGHT) + pixel_row); // (*16) == (<<4)
  next_text_rd_row_start = (TEXT_SZ)'(text_rd_row_start + TEXT_WIDTH);
end: calc_rom_addr


always_ff @(posedge clk) begin: text_gen_main
  last_restart <= toggle_restart;
  last_next <= toggle_next;

  if (last_restart != toggle_restart || reset) begin: do_restart
    text_rd_address <= '0;
    text_rd_row_start <= '0;
    pixel_row <= '0;
    text_col <= '0;
    text_row <= '0;
    // FIXME: More to do

  end: do_restart else if (last_next != toggle_next) begin: do_next

    // Get the next character to read
    if (text_col == LAST_TEXT_COL) begin: next_pixel_row
      // We've finished a whole row of characters's pixels
      text_col <= '0; // X

      if (pixel_row == LAST_PIXEL_ROW) begin: next_text_row
        // And we've finished the last row of the current characters.
        // Advance to the next text row for reading.
        // FIXME: Do we want to intentionally wrap if we don't get the restart?
        text_rd_address <= next_text_rd_row_start;
        text_rd_row_start <= next_text_rd_row_start;
        text_row <= text_row + 1'd1; // Y
        pixel_row <= '0; // Pixel Y

      end: next_text_row else begin: same_text_row
        // We've reached JUST the last column, but there are still more
        // rows of pixels for the current row's characters to look at.
        text_rd_address <= text_rd_row_start; // So rewind to re-see the same text
        pixel_row <= pixel_row + 1'd1;

      end: same_text_row

    end: next_pixel_row else begin: same_pixel_row
      // Get the next character for the current row of text
      // and the pixels for the same row of pixels.
      text_col <= text_col + 1'd1;
      text_rd_address <= text_rd_address + 1'd1;
    end: same_pixel_row

  end: do_next

end: text_gen_main


endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
