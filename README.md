# FPGA SPI & Peripheral Implementations

Copyright ⓒ 2023 Douglas P. Fields, Jr. symbolics@lisp.engineer

Code and documentation herein by Douglas P. Fields, Jr. is icensed under 
[Solderpad Hardware License 2.1](https://solderpad.org/licenses/SHL-2.1/),
which wraps the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0).

See licensing information in [`LICENSE`](LICENSE) and additional
notices in [`NOTICE`](NOTICE) files.

## Overview

Implpementation of 3-wire SPI including support for specific 3-wire peripherals
such as the TM1638-based LED&KEY I/O board, the QYF-TM1638 I/O board and the
Pimoroni Unicorn Hat Mini.

## Implemented

* 3-wire SPI controller
  * Testbench for this
* Generic TM1638 controller
* LED & KEY board-specific controller
* LED & KEY demo
* QYF-TM1638 board-specific controller
* QYF-TM1638 demo
* Unicorn Hat Mini-specific controller
  * Binary mode only (i.e., RGB non-grayscale)
* UHM demo
* ILI9488 480x320 LCD with 60x20 character interface

## Known Bugs

* Every now and then, upon download, the ILI9488 gets into an odd mode where
  it is off by a little bit
  * It seems to have a bad first row of pixels
  * It seems to rotate by one character position every refresh (which is currently
    set to 1 second for debugging)
* It seems to draw an extra row of pixels - maybe it's an off by one error in pixel count
  * Sometimes it seems it is ignoring the 0x2C Memory Write command
* Now it just doesn't work at all...!!!
  * Is my panel dead? Did I destroy it somehow? Are my GPIOs dead?

## TODO

* JY-MCU JY-LKM1638 V:1.2
  * Has 6 enables to daisy chain this module

* 3.5" SPI Display [product](http://www.lcdwiki.com/3.5inch_SPI_Module_ILI9488_SKU:MSP3520)
  *  [DONE] Update SPI controller:
    * [DONE] Add ability to set dcx signal during various bytes
      * Start high or low
      * Switch after N bytes
      * This can be used for the Command or Data pin
    * [DONE] Improve test bench to test this
    * [DONE] Fix off-by-one error in counting half-bits
    * Fix inter-byte delay due to above off-by-one error
  * [DONE] Implement basic ILI9488 controller on top of SPI controller
  * [DONE] Implement a 60x20 character interface (1,200 bytes)
    * Reuse the 8x16 font previously used in VGA interface
  * Make the 60x20 character interface allow choice of foreground and background
    colors by making each character 8 + 6 bits long
    * Add a "blink" bit that will swap foreground and background color every second
  * Implement 3-bit-per-pixel bitmap interface for ILI9488 display
    * 153,600 pixels x 3 bits per pixel = 460,800 bits for memory
    * 51,200 locations at 3 pixels of 3 bits each (fitting in our 9-bit block RAMs)
    * (This seems like an inconvenient memory structure; you can't write just one pixel.)
  * Implement 3-bit-per-pixel SPI interface
    * 2 pixels per byte in SPI interface
    * 76,800 bytes to refresh the screen
    * Provide a display memory from which we'll read the data
  * Enable full 20MHz speed on the SPI interface
    * Use a PLL to go from 50MHz to 80MHz
    * Use a 4x `CLK_DIV`
    * See how fast this chip can really go (despite 250ns limit in the docs)
  * Reduce delays 

* Unicorn Hat Mini
  * Brightness for binary mode
  * Grayscale mode


## Modules

* `seven_segment` - My usual combinational 7-segment driver
* `spi_3wire_controller` - a simple controller for a 3-wire SPI with
  `DIO` input/output
* `test_spi` - a Quartus test bench to show that the waveforms the
  SPI controller generates are as expected
  * (TODO) This does not do input testing
* `tm1638_generic` - a simple controller for TM1638 boards built on
  the 3-wire SPI. These boards have 16 bytes of output RAM
  (for LEDs), 4 bytes of input RAM (for keys), and a brightness
  setting (not implemented).
* `led_n_key_controller` - a simple controller specifically for the
  TM1638-based `LED&KEY` controller available all over the place
  inexpensively (such as [Amazon](https://www.amazon.com/dp/B0B7GMTMVB))
  * 8 7-segs (with decimal point), 8 LEDs, 8 buttons
  * no crosstalk/interference between any functions
* `qyf_tm1638_controller` - a simple controller for the QYF board
  also (obviously) based on the TM1638 (such as [Amazon](https://www.amazon.com/dp/B0BXDL1LG1))
  * Not as nice as the above, but has 16 keys which cannot be safely multi-
    pressed in any combination
* `unicorn_hat_mini_controller` - a simple controller for the 
  [Pimoroni Unicorn Hat Mini](https://shop.pimoroni.com/en-us/products/unicorn-hat-mini)
  which handles RGB color (without grayscale for now). Takes a 17x7 array of
  1-bit RGB pixels and refreshes the display regularly.
* `*_demo` - simple demo applications for the boards

## Implementation Notes

* Terasic DE2-115 has a 14-pin `EX_IO` that has some 3V3 I/Os that have pull-up and pull-down
  resistors.
  * `EX_IO[6]` has a 2.2KΩ pull-down resistor
  * `EX_IO[5:0]` have 2.2KΩ pull-up resistors
  * `EX_IO[4]` also has a 33Ω in-line resistor between the pin and the FPGA, after the pull-up (unknown reason)
  * These may be useful for I²C and 3-wire SPI implementations that need pull-ups

--------------------------------------------------------------------------------------------------------

# TM1638 Button/Display for FPGA

Copyright ⓒ Douglas P. Fields, Jr. All Rights Reserved.

# TODO

* [DONE] Implement the read side of the 3-wire SPI module
  * [DONE] Rename the module to 3-wire SPI or something not specific to HT16D35A
* [DONE] Create a generic TM1638 driver module that takes 16 bytes memory input
  and 4 bytes memory output and constantly refreshes that automatically
  * Include a pulse output for every time the input is sampled, or
    the system is busy, or when the outputs update
  * Synchronize the inputs if we care, or we can simply not care, as they
    will be sampled very frequently and a little bit error won't matter much
* [DONE] Create a specific module that works with LED & KEY, takes the hex inputs and
  the LED/decimal inputs, and outputs the 8 keys
  * (Currently done at the top level)
* [DONE] Create a specific module that works with the QYF 8-segment & 16 key version


# TM1638 References

Datasheet:
* [TM1638 English Translation](https://github.com/maxint-rd/TM16xx/blob/master/documents/LED%20driver%20TM1638en.pdf) - unknown version, marked updated 2011-04-09 on page 18
* [TM1638 English v1.3](https://futuranet.it/futurashop/image/catalog/data/Download/TM1638_V1.3_EN.pdf)

Implementations for FPGA:
* [GitHub 1](https://github.com/alangarf/tm1638-verilog)
* [GitHub 2](https://github.com/mangakoji/TM1638_LED_KEY_DRV)
* [GitHub 3](https://github.com/maxint-rd/TM16xx) - this has listings of all the TM16xx family
  and data sheets for each one in English, very super useful

Implementations for other platforms:
* [GitHub Arduino](https://github.com/codebeat-nl/xtm1638)
* [GitHub Arduino 2](https://github.com/maxint-rd/TM16xx) with translated data sheets for various TM16xx chips including the TM1638

Amazon links:
* [LED&KEY](https://www.amazon.com/dp/B0B7GMTMVB?psc=1&ref=ppx_yo2ov_dt_b_product_details)
* [QYF-TM1638](https://www.amazon.com/dp/B0BXDL1LG1?psc=1&ref=ppx_yo2ov_dt_b_product_details) "Digital Tube Module"

# Implementation notes

* This seems to use the same protocol as my Unicorn Hat Mini implementation
  (which was a write-only implementation of the protocol), with a few changes
  as noted on the 1.3 data sheet page 17
  * Clock minimum 400ns (i.e. 2.5 MHz)
  * 1µs between interactions (between active-low selects) - vs 2
  * 1µs between last transfer clock high and deasserting STB - vs 2
  * `DIO` transfers data LSB first (!!!!!)
* The same things:
  * `DIO` reads data at the rising edge
  * `DIO` writes data at the falling edge
  * ... "Read serial data at rising edge and output data at falling edge."
* Unusual differences:
  * After sending a read command, you have to wait `Twait` (minimum 2µs) per p9,
    but the timing diagram later shows 1µs (p 17).

* Looks like it can operate at 3.3V or 5V (p15 of v1.3) or even lower.
  * Confirmed that this works with Vcc of 5V and 3V3 from DE2-115 GPIO source.
    It is a little less bright on 3V3 but it's totally fine.

* It requires an external pull-up resistor
  * "When DIO outputs data, it is an NMOS open drain output. To read the keypad, 
    an external pull-up resistor should be provided to connect 1K-10K. The Company recommends a
    10K pull up resistor. At falling edge of the clock, DIO controls the operation of NMOS, at 
    which point, the reading is unstable until rising edge of the clock." (v1.3 p2)
  * This pull-up resistor is NOT provided on the LED&KEY board.
  * However, the built-in Weak Pull-Up seems to work fine:
    `set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to GPIO[21]`

* "TM1638 can be read up to four bytes only." (v1.3 p7)

* The TM1638 in the LED&KEY can refresh very, very fast.
  * The refresh based these basic settings:
    * `CLK_DIV = 20`
    * `ALL_DONE_DELAY = 1`
    * `OUT_BYTES = 5`
  * Speed with various `DELAY_START` settings

        DELAY_START (decimal)     Iterations per second hex/decimal
            1_000                 1462   / 5_217
           10_000                  898   / 2_200
          100_000                  1CD   /   461
          230_000                   D2   /   210
          260_000                   BA   /   186
          460_000                   6B   /   107

  * However, the maximum useful refresh rate is once every 4.7ms or about
    212 times a second, as that is how fast it internally refreshes its
    display and key state (see data sheet v1.3, page 8).
  * So recommended values for `DELAY_START` are `d230_000` or `d460_000`
    for the maximum useful speed or about 100Hz respectively.


## Writing to LEDs

See flowchart on p11 of v1.3 document:

1. Set auto-increment (0x40)
   * Table 5.1, 8'b01_00_0000 = Data command, write to display register, auto-increment, normal mode
2. Set starting address (0xC0)
   * Table 5.2, 8'b11_00_0000 = Display address 0x00
3. Transmit data (all 16 bytes)
4. Set brightness to maximum (0x8F)
   * Table 5.3, 8'b10_00_1_111 = Display on, Pulse width 14/16 (maximum)


# LED & KEY Details

* The `DIO` ALTIOBUF *cannot* be open-drain for the TM1638 in the LED&KEY
  * If set to open-drain in the FPGA, the TM1638 will miss bits on input.

* Requires "Weak pull-up resistor" on the `DIO` line (`GPIO[21]` in this code)


* See the code for mappings:
  * Keys: they use K3 only, and all 8 KS#s (see p7)
  * LEDs: i: 0..7

        lk_memory[i * 2    ][6:0] = lk_hexes[i];
        lk_memory[i * 2    ][7]   = lk_decimals[i];
        lk_memory[i * 2 + 1][0]   = lk_big[i];

* Works well with 3.3V

## LED Memory Mapping

7-segment displays:
* Every even byte, bits 6:0, map in the usual 7-segment way
* Bit 7 is the decimal pint

8 big LEDs:
* Every odd byte, bit 0, is the LED

# QYF-TM1638 Details

* I connected a QYF-1638 instead of an LED&KEY, using LED&KEY memory map
  * Key presses were not registered
  * Multiple key presses showed up on the LEDs
  * LEDs shown were "incorrect" in the pattern they made
  * ... therefore it needs a completely different "controller"

* Keys share LED lines without diodes as in the LED&KEY device
  * Pressing multiple keys may light LEDs

* Works fine with 3.3V

All in all, the LED&KEY is a nicer, safer to use device than QYF-TM1638.

## QYF-TM1638 Connection

* This has built-in pull-up resistors (see schematic) and also capacitors
  on the lines (I do not know why it has capacitors)
  * So it doesn't need an internal weak pull-up or external pull-up
* It does not need open-drain I/O buffers
* So, just use a standard ALTIOBUF

## QYF-TM1638 memory model

* Display: Looks like every other byte is used, starting with 0
  * One segment of all 8 displays are used for each input byte
  * The order is in the usual 7-seg order, with bit 7 being the decimal point

* Keys:
  * Keys 1-8/9-16 start at the lowest nibble for 1/9
    * 1-8 are the 4-value bit of each nibble
    * 9-16 are the 2-value bit of each nibble
  * Only two keys can be pressed simultaneously without display artifacts:
    * one of 1-8 and one of 9-16 
  * The two pressed keys can always be read correctly - the same combination above
    * Examples of incorrectly read keys:
      * 1, 2, 9 -> Read as 1, 2, 9, 10
      * 1, 2, 3, 11 -> Read as 1, 2, 3 and 9, 10, 11
  * One key from each of the 1-8 and 9-16 columns can be pressed and read correctly
    for 8 pressed keys read correctly if they are the exact correct 8
  * Maybe reject any keypresses that involve both 1-8 and corresponding 9-16
    simultaneously pressed
   
## QYF-TM1638 Demo

* Keys make the digits go up or down by one
* Decimal point goes around and around

--------------------------------------------------------------------------------------------------------


# Pimoroni Unicorn Hat Mini for FPGA

# Implementation notes

* 3.3V and 5V power (and Ground) required
* SCK & SDO pins required
* 2 CS pins required for each half of the display
* --> Total 7 pins required including power




## References

Unicorn Hat Mini References:
* [Pimoroni product page](https://shop.pimoroni.com/en-us/products/unicorn-hat-mini)
* [Chipset](https://www.holtek.com/productdetail/-/vg/ht16d35a_b) - Holtek HT16D35A x2
  * Datasheet version 1.22 dated November 15, 2021 is used for this analysis
* [Pinout](https://pinout.xyz/pinout/unicorn_hat_mini#)
* [Python](https://github.com/pimoroni/unicornhatmini-python)
* [Tutorial](https://learn.pimoroni.com/tutorial/hel/getting-started-with-unicorn-hat-mini)

SPI References:
* [SPI Spec](https://www.mouser.com/pdfdocs/tn15_spi_interface_specification.PDF)
* [Wikipedia](https://en.wikipedia.org/wiki/Serial_Peripheral_Interface)
* [Analog Devices Introduction](https://www.analog.com/en/analog-dialogue/articles/introduction-to-spi-interface.html)
* [SparkFun Introduction](https://learn.sparkfun.com/tutorials/serial-peripheral-interface-spi/all)
* [FPGA 4 FUN Introduction](https://www.fpga4fun.com/SPI1.html)
* [FPGA Research Paper](https://iopscience.iop.org/article/10.1088/1742-6596/1449/1/012027/pdf)
  * [Another one](https://www.ijitee.org/wp-content/uploads/papers/v2i2/B0350012213.pdf)
* [VHDL Implementation](https://github.com/jakubcabal/spi-fpga)
* [Verilog Implementation](https://alchitry.com/serial-peripheral-interface-spi-verilog)
* [NAND Land's Verilog](https://github.com/nandland/spi-master)
* [Hackaday's introduction](https://hackaday.io/project/119133-rops/log/144622-starting-with-verilog-and-spi)
* ["Super" SPI Controller](https://www.circuitden.com/blog/22)

Unicorn Hat Mini Pinout:
* Buttons A, B, C, D: GPIOs 5, 6, 36, 24: Pins 29, 31, 36, 18
* SPI SCLK, MOSI: GPIO 11, 10: Pins 23, 19
* SPI CE0, CE1: GPIO 8, 7: Pins 24, 26
* Power: 3v3 and 5v: Pins 1, 2 (both required)
* Ground: Pins 6, 9, 14, 20, 25, 30, 34, 39

Notes:
* Can run at SPI at [6 MHz](https://github.com/pimoroni/unicornhatmini-python/blob/master/library/unicornhatmini/__init__.py) at least (500 FPS)
  * Spec sheet says limiting clock to 250ns or 4MHz
* Run in binary mode or gray mode (6-bit)
* This runs a modified SPI, with 3-wires (clock, chip select, and data in/out),
  so the SPI controller may not be easily reusable to other chips

Initialization Sequence ([from here](https://github.com/pimoroni/unicornhatmini-python/blob/master/library/unicornhatmini/__init__.py)):
* Soft reset
  * 0xCC
* Global brightness
  * 0x37 0x01
* Scroll control
  * 0x20 0x00
* System control
  * 0x35 0x00
* Clear display with write display command
  * 0x80, 0x00 then [a lot more](https://github.com/pimoroni/unicornhatmini-python/blob/master/library/unicornhatmini/__init__.py#LL62C76-L62C76)
* "Com" pin control
  * 0x41 0xFF
* Row pin control
  * 0x42 0xFF 0xFF 0xFF 0xFF
* System control
  * 0x35 0x03

Shutdown Sequence:
* "Com" pin control
  * 0x41 0x00
* Row pin control
  * 0x42 0x00 0x00 0x00 0x00 
* System control
  * 0x35 0x00

## Notes from Datasheet

See Holtek HT16D35A Datasheet Rev 1.22

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
  should be avoided for *1ms* following a power-on to
  allow the reset initialisation operation to complete
* Page 19-20: Command table
* Page 60 for Initialization
* Page 61 for Writing Display

### Initialization

page 60 and [GitHub](https://github.com/pimoroni/unicornhatmini-python/blob/master/library/unicornhatmini/__init__.py)

* COM output control
  * 41 ff
* ROW output Control
  * 42 ff ff ff ff
* Binary/Gray mode
  * 31 00/01 (default 00 - gray, 01 - binary, see page 22)
* Number of COM output
  * 32 ?? (default 07 - this is NOT set by the Unicorn Hat Mini)
* Constant current ratio
  * 36 ?? (default 00 - this is NOT set by the Unicorn Hat Mini)
* Global brightness control
  * 37 01 (default 40 - maximum)
* System control - oscillator on
  * 35 02

### Screen display

page 61

* Set display RAM address
  * 80 00 ... (00-1b for binary, 00-fb for gray)
* Wrtie display RAM data
* Set system control - display on
  * 35 03

### My minimal initialization sequence

(Tested this out in SPIDriver)

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

...then repeatedly send 28 bytes of memory.

## Reverse engineering UHM

Used a [SPIDriver](https://spidriver.com/)
to test much of this out. Note that the SPIDriver
Windows application seems to need to run as Administrator
to get access to the "COM" port.

* CS0 = left half
* CS1 = right half

### Binary mode

* Memory 00-1b = 28 bytes (00-27 decimal)
* Mapping: for CS0/CE0 (left side chip)
  * 00 - nothing
  * 01 - column 3, red
  * 02 - column 3, blue
  * 03 - column 3, green
    * bit 0 - row 2
    * bit 1 - row 4
    * bit 2 - row 3
    * bit 3 - row 1
    * bit 4 - row 5
    * bit 5 - row 7
    * bit 6 - row 6
    * bit 7 - nothing
  * 04-06 - column 4, rgb
  * 07-09 - column 5
  * 0a-0c - column 6
  * 0d-0f - column 7
  * 10-12 - column 8
  * 13-15 - column 9
  * 16-18 - column 2, blue, green, red (!!)
  * 19-1b - column 1, blue, green, red (!!)
* Mapping for CS1/CE1 (right side chip)
 * 00 - nothing
 * 01 - column 13, red
 * 02 - column 13, blue
 * 03 - column 13, green
 * 04-06 - column 14
 * 07-09 - column 15
 * 0a-0c - column 16
 * 0d-0f - column 17
 * NOTE: BELOW HERE IS NOT QUITE ACCURATE
 * 10-12 - nothing (!!)
 * 13-15 - column 11, blue, green, red (!!)
 * 16-18 - column 10, blue, green, red
 * 19 - column 12, blue
 * 1a - column 12, green
 * 1b - column 12, red

 So for the display: binary_mem:bit
 THIS IS ACCURATE!

        RED
        LEFT                           || RIGHT
        1b:3 18 | 01 04 07 0a 0d 10 13 || 1b 18 | 01 04 07 0a 0d 10
        1b:0 18 | 01 04 07 0a 0d 10 13 ||
        1b:2 18 | 01 04 07 0a 0d 10 13 ||
        1b:1 18 | 01 04 07 0a 0d 10 13 ||
        1b:4 18 | 01 04 07 0a 0d 10 13 ||
        1b:6 18 | 01 04 07 0a 0d 10 13 ||
        1b:5 18 | 01 04 07 0a 0d 10 13 ||
         1    2 |  3  4  5  6  7  8  9 || 10 11 | 12 13 14 15 16 17

 ### Gray mode

 See page 41: it goes from 0 to 63

 (This is very incomplete)

 * Memory 00 - fb
 * Right Chip (CS1)
   * decimal 30 - first one @ column 12 row 6, red
   * blue
   * green
   * 33-35: column 13, row 6, red, blue, green
   * ...
   * column 17, row 6, rbg
   * 3 nothing
   * column 11, blue, green, red
   * column 10, bgr
   * 1 nothing
   * column 12, red, blue, green





--------------------------------------------------------------------------------------------------------


# SPI Implementation Notes

* It is a two-cycle implementation where I output the clock in two parts
  as opposed to the four parts I used in my earlier I²C implementation.

* The 3-wire SPI implementation is done and supports:
  * MSB and LSB-first data transmission.
  * Optional delay after releasing chip select.
  * WRITE ONLY (for now)
  * Parameter configured maximum write burst size.

## Open questions

* Are the two HT16D35A chips wired in sync mode? (page 3, SYNC pin)

--------------------------------------------------------------------------------------------------------



# ILI9488 480x320 LCD Display Module

[Amazon Product Page](https://www.amazon.com/dp/B08C7NPQZR)
* 3.5" display
* Pins for touch screen but apparently no touch screen (which is fine)
* Full size SD card reader with unpopulated header and 4-wire SPI interface
  * Presumably uses the power/ground from the LCD pins

[Board Site](http://www.lcdwiki.com/3.5inch_SPI_Module_ILI9488_SKU:MSP3520)

[Driver Chip Datasheet](https://focuslcds.com/content/ILI9488.pdf) - also in datasheets director
* Version V100, ILI9488_IDT_V100_20121128

[Module Datasheet](http://www.lcdwiki.com/res/MSP3520/3.5inch_SPI_Module_MSP3520_User_Manual_EN.pdf)

[Module Schematic](http://www.lcdwiki.com/res/MSP3520/3.5%E5%AF%B8SPI%E6%A8%A1%E5%9D%97%E5%8E%9F%E7%90%86%E5%9B%BE.pdf)


References:
* [GitHub ILI9488](https://github.com/topics/ili9488)
* [Espressif](https://components.espressif.com/components/atanisoft/esp_lcd_ili9488)
  * [GitHub](https://github.com/atanisoft/esp_lcd_ili9488)
    * [Initialization](https://github.com/atanisoft/esp_lcd_ili9488/blob/main/esp_lcd_ili9488.c#L114)
      `panel_ili9488_init`
* [TinyDRM ILI9488 driver on GitHub](https://github.com/birdtechstep/tinydrm/blob/master/ili9488.c)
* [TFT_eSPI on GitHub](https://github.com/Bodmer/TFT_eSPI)
  * [Initialization](https://github.com/Bodmer/TFT_eSPI/blob/master/TFT_Drivers/ILI9488_Init.h)

## Implemented

* Basic ILI9488 controller
  * Initializes the display for horizontal configuration with 1-bit color resolution
  * Sets the display to one color

* Function:
  * It takes a while at 12.5 MHz to refresh the screen, much longer than the ~75kbytes of
    data transfer seems to imply. 75 kbytes -> ~750kbits
  * It should be able to do ~16 refreshes a second but probably does less due to inefficiency
    in my implementation

## TODO

* Do a 40 MHz clock via PLL with a controller divider of 2 to use maximum speed 20MHz
* Implement zero-inter-byte delay properly in the underlying SPI controller
* Implement a character display similar to the VGA implementation I did earlier
  * Implement color foreground and background for each character (6 bits)
  * Font size 8w x 16h = 60x20 characters = 1,200 bytes of character ROM
  * Need to pipeline the reads
  * There are no porches to do things, and current implementation just streams the
    same byte N times for video memory, so we need to do figure it out fresh
    * Maybe have the RAM/ROM read in a different `always_ff` block
    * Have a "first byte" and "next byte" flag from the main state machine
      that inform the streaming reader via state changes to do something.


## Connections

* SPI signals
  * CS - `CSX` in the data sheet
  * SCK - `WRX/SCL` in the datasheet
  * SDO - note that this means data OUT from the ILI9488 in to the controller
    * This is not used
  * SDI - note that this means data out from the controller IN to the ILI9488
* DC/RS - `D/CX` in the datasheet
  * Must be low when sending a command (during bit 0, but I just do the whole byte)
  * Must be high when sending data or parameters for a command
  * This is part of the "4-line SPI" protocol
* RESET - `RESX` in the datasheet 
  * active low reset (can tie high if not used)
  * "Be sure to execute a power-on reset after supplying power." (page 23)
* LED - Turns on the backlight - provide 3.3V
* VCC/GND - 3.3V and Ground

The `SDI` pin can be used as bi-directional `SDA` pin if desired,
with the "Interface Mode Control" `B0h` command's `SDA_EN` bit.
However, if `SDO` is not used then it should be left floating (page 23).


## Unusual things noted

* Some read commands have a "dummy bit" before you can read a multi-byte response

* Data sheet says 5-6-5 data format is supported but I cannot see how to access it

## High level thoughts

* 480 x 320 = 153,600 pixels
  * times 3 channels = 460,800 bits of data minimum at 1 bit
  * or 460 KB of data at 1 byte per channel or 1,382,400 byte at 3 bytes per channel
    * (The display only does 6 bits per channel)
  * With overhead (1 byte per 6 bytes) = 1.6 MB transfer
    * At 12.5MHz that is about 1.5 MB/s
    * or about 1 Hz screen refresh rate (really slow)
  * at 2 pixels (1/1/1 bit depth) per byte = 
* Will need to put inter-byte delays to minimum/zero
  * Spec sheet does not seem to need any based on timing diagrams

It might be best to implement drawing directly to video memory of the SPI
device, rather than having a framebuffer in the FPGA and sending data there,
as it seems it will take a second to draw the screen.

If, instead, there is a screen of 8x16 characters that would hold
60x20 characters, maybe we could write each character to the SPI
memory as it was changed. However, there doesn't seem to be an easy
way to do this without using th


## Open Questions

* 5-6-5 bits per pixel seems to be supported but I cannot figure out how
  to use it.
  * This would reduce by a third the number of bits that need to be transferred
    per frame

* Is there a way to set the current column/page address (memory write pointer)?
  * I have not seen any in the data sheet.
  * Partial Area may be useful, but it is unclear how that works

## Misc Notes

* Converted `.mif` files to `.hex` format for Questa.
  * These `.hex` files are NOT human readable though, so I'm keeping both in source.
  * Use WSL2 Ubuntu 22 LTS for `srec_cat` command
  * `srec_cat isoFont.mif -Memory_Initialization_File -Output isoFont.hex -Intel`
  * `srec_cat starting_text.mif -Memory_Initialization_File -Output starting_text.hex -Intel`
  * After doing that, the files need to be converted to Windows line endings
  * Then, you need to symlink the `.hex` files into `simulation/modelsim` directory.
    (Yes, you can do symbolic links in Windows.)

## Reverse engineering

* Section 3.2.1: System Interface `MIPI-DBI Type C` operating mode presumably (page 20)
  * Not sure if Option1 or Option3, but presumably Option3 for 4-line since there is SDO and SDI
  * IM[0:2] == 111
* Section 4.2: `DBI Type C Serial Interface` 
  * D/CX
  * CSX L
  * SCL low to high
  * 3-line SPI:
    * CSX
    * SCL
    * SDA
  * 4-line SPI:
    * D/CX
    * CSX
    * SCL
    * SDA
  * SCL can be stopped when no communication is necessary
  * This seems to mean that it always is 3-wire SPI mode (i.e., SDI/SDO?)
  * MSB first
  * 4-line Serial Protocol has "dummy clock cycles" sometimes for reads (???)
    * See page 47
* Section 4.7: Display Data Format
  * 3 bits per pixel or 18 bits per pixel
  * See 4.7.2 (p121) for the 3 formats: 1/1/1, 5/6/5, 6/6/6
    * No example given for 5/6/5, which might be faster as it takes only two bytes per
      pixel (16 bits)
  * See 4.7.2.2 for 18-bit on 4-line SPI
  * See 4.7.2.1 for 1 bit per pixel
  * D/CX are always 1 (read at the LSB)
* Section 17.4.2-3 Timings for SPI (page 331-332)
  * Use 17.4.3 DBI Type C Option 3 (4-Line SPI System)
  * tCHW = 40ns - Chip Select high pulse width
  * tWC = Serial clock speed for writes = 50ns
    * [20 MHz](https://www.unitjuggler.com/convert-frequency-from-ns(p)-to-MHz.html?val=50)
    * 50MHz system clock -> CLK_DIV 2 would give us 25MHz of CLK_DIV 4 would give us 12.5MHz
    * Might need to use a PLL to get 80MHz and CLK_DIV of 4 to maximize throughput
  * tRC = Serial clock speed for reads = 150ns (!!! Different read/write max speeds !!!)
    * 6.67 MHz
  * D/CX setup & hold time = 10ns
  * SDA setup & hold time = 10ns
  * SDO access time from clock low = 10-50ns
  * SDO output disable time = 15-50ns (not shown on the timing diagram)
* Section 5 (page 140): Command list
* Section 13 (page 306): Reset & Registers
* Display memory writing
  * See flow-chart on p176
  * CASET (0x2A): SC, EC
  * PASET (0x2B): SP, EP
  * RAMWR (0x2C): Image data

Pins from Datasheet:
* `RESX` is low active reset - presumably this needs to be high
  * `RESET` on the back?
* `CSX` - Chip select (usual SPI thing) - low active - DBI Type B
* `D/CX` - For DBI Type B
* `WRX/SCL` - SCL for serial clock for DBI Type C
  * `SCK` on the back?
* `SDA`- SPI SDI for us, or DIO for 3-wire (which is not us)
* `SDO` - SPI SDO


## SPI Driver

* Reset - 3.3V (tie it high)
* A - `DC/RS` on board, seems to be `D/CX` in data sheet
* B - `LED` (seems to turn backlight on?)


`spicl` examples
* Note: The first byte has to have the `DC/RS` pin low, the rest have to have it high
  * This implies we are using the 4-pin SPI mode
  * This means we need a new SPI driver than the one we're currently using
  * I am using the `A` pin on SPI Driver for the `DC/RS` AKA `D/CX` pin
* .\spicl COM3 s a 0 w 0x04 a 1 r 4 u
  * 0x2a,0x40,0x33,0x00
  * Command: Read display identification information
  * This has a "dummy bit" that needs to be compensated for
* .\spicl COM3 s a 0 w 0x09 a 1 r 5 u
  * 0x00,0x30,0x80,0x00,0x00
  * Command: Read Display Status
* .\spicl COM3 s w 0x01 u
  * .\spicl COM3 s a 0 w 0x01 a 1 u
  * Soft reset



[Initialization from GitHub](https://github.com/Bodmer/TFT_eSPI/blob/master/TFT_Drivers/ILI9488_Init.h)

```
(did not set positive/negative gamma control)
PS:31 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xC0 a 1 w 0x17,0x15 u
  Power control 1
PS:32 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xC1 a 1 w 0x41 u
  Power control 2
PS:33 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xC5 a 1 w 0x00,0x12,0x80 u
  VCOM Control (takes 4 parameters, but only 3 provided?)
PS:34 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x36 a 1 w 0x48 u
  Memory Access control
  BGR panel (the 8)
  Write from the top right down to the bottom, then scan toward the left
  WE WANT THIS TO BE 0xE8 in the future
PS:35 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x3A a 1 w 0x66 u
  Interface pixel format (page 200)
  18 bits per pixel (twice)
PS:36 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xB0 a 1 w 0x00 u
  Interface Mode Control
  Use SDO (0x80 would use SDA for DIO and disable SDO)
PS:37 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xB1 a 1 w 0xA0 u
  Frame rate control  (takes two parameters, this ignored one)
PS:38 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xB4 a 1 w 0x02 u
  Display inversion control - two dot inversion
PS:39 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xB6 a 1 w 0x02,0x02,0x3B u
  Display function control (page 228)
PS:40 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xB7 a 1 w 0xC6 u
  Entry mode set (page 232)
PS:41 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xF7 a 1 w 0xA8,0x51,0x2c,0x82 u
  Adjust Control 3 (page 276) - "use loose packet RGB 666"
PS:42 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x11 u
  (exit sleep, 120 delay)
  Sleep OUT (page 166)
  Must wait 5ms before the next command
  Must wait 120ms after Sleep IN before you can issue Sleep OUT
PS:43 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x29 u
  (display on, 25 delay)
  Display ON (page 174)
```
... and the display turned on!

It seems the initial display memory was a uniform gray color.

What is the MADCTL D5 ? Column and page reversed?
* PS:57 C:\Program Files (x86)\Excamera Labs\SPIDriver> # Read MADCTL
* PS:58 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x0B a 1 r 2 u
* 0x48 (DUMMY),0x00
* Note: 00 is the default (page 158)
* So D5 = 0 by default and per this read


What is the display status? Command 0x09 section 5.2.5 page 153:
* .\spicl COM3 s a 0 w 0x09 a 1 r 5 u
* 0xd2,0x31,0x82,0x00,0x00
* There is a dummy bit at the front we need to ignore, so bit shift this one:
  * See page 47
  * Dummy 1st parameter doesn't seem to apply
* 110100100011000110000010000000000 -> 10100100011000110000010000000000
*  10100100011000110000010000000000 -> 
* 1010_0100__0110_0011__0000_0100__0000_0000: 31:0
* 31: Booster on
* Row address order Top to bottom
* Column address order right to left
* row/column exchange: normal
* _
* Vertical refresh
* BGR ???
* Horiz refresh
* (there is no D24)
* __
* (there is no D23)
* 22-20: 110: 18 bit/pix
* _
* idle off
* partial off
* sleep OUT
* Display normal mode
* __
* 15: Vertical scroll of
* (no 14)
* inversion off
* (no 12)
* _
* (no 11)
* 10: display on
* 9: Tear effect line off
* 8-6: Gamma curve selection
* __
* 5: Tearing effect line mode 1



Let's see if we can get something on the display:
* 480 = 1E0 (This is the page address, it seems)
* 320 = 140 (This is the column address, it seems)


```
PS:64 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x2A a 1 w 0x00,0x00,0x01,0x3F u
PS:65 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x2B a 1 w 0x00,0x00,0x01,0xDF u
PS:66 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x2C a 1 w 0xFF,0xFF,0xFF u
```

This draws the top right most pixel and then starts scanning down
* It always resets the drawing at the start coordinates provided (very inconvenient)
* Try the "Memory Write Continue" command 0x3C (5.2.35, page 201)
  * That worked

So, to write to memory, one time set the start column & start page
* Then start writing with the 0x2C command
* and continue writing with 0x3C command if you don't write everything all at once


Memory Access Control (0x36) Section 5.2.30 page 192
* If we write 0x20, it starts writing from the bottom right backwards
  to the left.
* If we write 0x60, it starts writing from the top right backwards to the left.
* 0x40 seems not to change anything
* 0xE0 seems to do what we want:
  * Write from top left corner toward the right, then the bottom
* So, write 0x36 0xE0 to scan properly
* Now need to set the column/page address information correctly
* Column: 0x2A 0 0 0x01 0xDF
* Page:   0x2B 0 0 0x01 0x3F
* BUT: 0xE0 gets the RGB/BGR wrong, so we need to really set 0xE8
  as the panel I have at least is BGR apparently

```
.\spicl COM3 s a 0 w 0x36 a 1 w 0xE8 u
PS:288 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x2A a 1 w 0,0,1,0xDF u
PS:289 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x2B a 1 w 0,0,1,0x3F u
```


Figure out how two write 1 bit per pixel mode
* --RG_BRGB - so two red pixels would be 0x24, two green would be 0x12
  * See 4.7.2.1 page 121
* This is actually simple, set 0x3A to 0x61 (see page 200)
  * `.\spicl COM3 s a 0 w 0x3A a 1 w 0x61 u`

Figure out how to write 5-6-5 pixel mode
* See page 121, which says set Command 3A (page 200) DBI to 101
* .\spicl COM3 s a 0 w 0x3A a 1 w 0x65 u
  * This does not work
* No combination I tried with 0x_5 seems to work


#### Minimal initialization

Defaults:
* Draws up from bottom right, moving toward the left
* Has wrong RGB setting (255,0,0 is blue not red)
* Does 6 bits per pixel

Initialization sequence:
* Memory Access Control 0x36 to 0xE8 (page 192)
  * scan top left to bottom right
  * BGR mode
* (Optional: Set 1 bit mode: set 0x3A to 0x61)
* Column Address Set: 0x2A 0 0 0x01 0xDF
* Page Address Set:   0x2B 0 0 0x01 0x3F
* Sleep OUT 0x11 (page 166)
  * Wait 5ms
* Display ON 0x29 (page 168)

Start writing memory
* 0x2C to begin a new frame
* 0x3C to continue a current frame
  * This is not strictly necessary, you can continue without the command
    if you just do not assert the `DC/RS` (on the board, `CSX` on the data sheet) pin

This seems to work fine:
```
.\spicl COM3 s a 0 w 0x36 a 1 w 0xE8 u
.\spicl COM3 s a 0 w 0x2A a 1 w 0,0,1,0xDF u
.\spicl COM3 s a 0 w 0x2B a 1 w 0,0,1,0x3F u
.\spicl COM3 s a 0 w 0x11 u
.\spicl COM3 s a 0 w 0x29 u

.\spicl COM3 s a 0 w 0x2C a 1 w 0,255,0... u
.\spicl COM3 s a 0 w 0x3C a 1 w 0,255,0... u
...
```


### SPI Driver Reading is Odd

```
PS:171 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0x04 a 1 r 4 u
0x2a,0x40,0x33,0x00
PS:172 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xda a 1 r 2 u
0x54,0x00
PS:173 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xdb a 1 r 2 u
0x80,0x00
PS:174 C:\Program Files (x86)\Excamera Labs\SPIDriver> .\spicl COM3 s a 0 w 0xdc a 1 r 2 u
0x66,0x00
```

The documentation shows that the 1st parameter is "dummy data" but shows the expected values
for the second parameter to be 54,80,66.

This is telling me that there is no "dummy read" going on in the SDI(MISO) pins for the 8-bit
reads.

Page 47 shows a dummy-bit for the 24/32-bit reads though

The first and the last 3 should show the same ID1-3

```
2a4033 0010_1010__0100_0000__0011_0011__00...
548066 0110_0100__1000_0000__0110_0110

       v--- Dummy bit
2a4033 001010100100000000110011
548066  010101001000000001100110
```

So it definitely is working with SPIDriver.

TODO: Add support for skipping a dummy bit in a read input (?!).

`RDDST` command 0x09 (page 153) also seems to get this dummy bit, but not
the "dummy parameter" that is shown.



