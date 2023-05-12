onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /test_spi/dut/sck
add wave -noupdate /test_spi/clk
add wave -noupdate /test_spi/reset
add wave -noupdate /test_spi/in_cs
add wave -noupdate /test_spi/out_count
add wave -noupdate /test_spi/in_count
add wave -noupdate /test_spi/dcx_start
add wave -noupdate /test_spi/dcx_flip
add wave -noupdate /test_spi/activate
add wave -noupdate /test_spi/busy
add wave -noupdate /test_spi/cs
add wave -noupdate /test_spi/sck
add wave -noupdate /test_spi/dio_o
add wave -noupdate /test_spi/dio_e
add wave -noupdate /test_spi/dio_i
add wave -noupdate /test_spi/dcx
add wave -noupdate -divider dut
add wave -noupdate /test_spi/dut/half_bit_counter
add wave -noupdate /test_spi/dut/state
add wave -noupdate /test_spi/dut/sck
add wave -noupdate /test_spi/dut/r_out_data
add wave -noupdate /test_spi/dut/current_bit
add wave -noupdate /test_spi/dut/current_byte
add wave -noupdate /test_spi/dut/current_last_byte
add wave -noupdate /test_spi/dut/r_dcx_flip
add wave -noupdate /test_spi/dut/r_dcx_start
add wave -noupdate /test_spi/dut/dcx_flipped
add wave -noupdate /test_spi/dut/dcx_flip_counter
add wave -noupdate /test_spi/dut/inter_byte_delay
add wave -noupdate -divider {Received Data}
add wave -noupdate /test_spi/in_data
add wave -noupdate -divider parameters
add wave -noupdate /test_spi/dut/DCX_FLIP_MAX
add wave -noupdate /test_spi/dut/DCX_FLIP_SZ
add wave -noupdate -radix unsigned /test_spi/dut/ALL_DONE_DELAY
add wave -noupdate -radix unsigned /test_spi/dut/NUM_SELECTS
add wave -noupdate -radix unsigned /test_spi/dut/SELECT_SZ
add wave -noupdate -radix unsigned /test_spi/dut/CLK_DIV
add wave -noupdate -radix unsigned /test_spi/dut/DIV_SZ
add wave -noupdate -radix unsigned /test_spi/dut/CLK_2us
add wave -noupdate -radix unsigned /test_spi/dut/us2_SZ
add wave -noupdate -radix unsigned /test_spi/dut/OUT_BYTES
add wave -noupdate -radix unsigned /test_spi/dut/OUT_BYTES_SZ
add wave -noupdate -radix unsigned /test_spi/dut/CLK_HALF_BIT
add wave -noupdate -radix unsigned /test_spi/dut/HALF_BIT_SZ
add wave -noupdate -radix unsigned /test_spi/dut/INTER_BYTE_DELAY
add wave -noupdate -radix unsigned /test_spi/dut/IB_DELAY_SZ
add wave -noupdate -radix unsigned /test_spi/dut/IB_DELAY_START
add wave -noupdate -radix unsigned /test_spi/dut/HALF_BIT_START
add wave -noupdate -radix unsigned /test_spi/dut/IN_BYTES
add wave -noupdate -radix unsigned /test_spi/dut/IN_BYTES_SZ
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1970000 ps} 0} {{Cursor 2} {2210000 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {6374487 ps}
