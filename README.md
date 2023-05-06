# FPGA SPI & Peripheral Implementations

Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.

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

# Reverse engineering UHM

Used a [SPIDriver](https://spidriver.com/)
to test much of this out. Note that the SPIDriver
Windows application seems to need to run as Administrator
to get access to the "COM" port.

* CS0 = left half
* CS1 = right half

## Binary mode

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
 * 10-12 - nothing (!!)
 * 13-15 - column 11, blue, green, red (!!)
 * 16-18 - column 10, blue, green, red
 * 19 - column 12, blue
 * 1a - column 12, green
 * 1b - column 12, red

 # Gray mode

 See page 41: it goes from 0 to 63

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







# Implementation Notes

* It is a two-cycle implementation where I output the clock in two parts
  as opposed to the four parts I used in my earlier I²C implementation.

* The 3-wire SPI implementation is done and supports:
  * MSB and LSB-first data transmission.
  * Optional delay after releasing chip select.
  * WRITE ONLY (for now)
  * Parameter configured maximum write burst size.

# Open questions

* Are the two HT16D35A chips wired in sync mode? (page 3, SYNC pin)

--------------------------------------------------------------------------------------------------------

