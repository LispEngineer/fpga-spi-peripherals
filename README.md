# Pimoroni Unicorn Hat Mini for FPGA

Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.

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
  should be avoided for 1ms following a power-on to
  allow the reset initialisation operation to complete
* Page 19-20: Command table
* Page 60 for Initialization
* Page 61 for Writing Display

# Implementation Notes

* I plan to try a two-cycle implementation where I output the clock in two parts
  as opposed to the four parts I used in my earlier I²C implementation.

# Open questions

* Are the two HT16D35A chips wired in sync mode? (page 3, SYNC pin)