onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /test_tpg/clk
add wave -noupdate /test_tpg/reset
add wave -noupdate /test_tpg/toggle_restart
add wave -noupdate /test_tpg/toggle_next
add wave -noupdate -divider DUT
add wave -noupdate /test_tpg/dut/last_restart
add wave -noupdate /test_tpg/dut/last_next
add wave -noupdate /test_tpg/dut/cur_char
add wave -noupdate /test_tpg/dut/cur_pixels
add wave -noupdate /test_tpg/dut/text_rd_address
add wave -noupdate /test_tpg/dut/rom_rd_addr
add wave -noupdate /test_tpg/dut/text_col
add wave -noupdate /test_tpg/dut/text_row
add wave -noupdate /test_tpg/dut/pixel_row
add wave -noupdate /test_tpg/dut/text_rd_row_start
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
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
WaveRestoreZoom {0 ps} {2572288 ps}
