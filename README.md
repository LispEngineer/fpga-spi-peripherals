# Pimoroni Unicorn Hat Mini for FPGA

Copyright ⓒ 2023 Douglas P. Fields, Jr. All Rights Reserved.

Unicorn Hat Mini References:
* [Pimoroni product page](https://shop.pimoroni.com/en-us/products/unicorn-hat-mini)
* [Chipset](https://www.holtek.com/productdetail/-/vg/ht16d35a_b) - Holtek HT16D35A x2
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