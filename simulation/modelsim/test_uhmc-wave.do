onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /test_uhmc/clk
add wave -noupdate /test_uhmc/reset
add wave -noupdate /test_uhmc/sck
add wave -noupdate /test_uhmc/sdo
add wave -noupdate {/test_uhmc/cs[0]}
add wave -noupdate -divider dut
add wave -noupdate /test_uhmc/dut/busy
add wave -noupdate /test_uhmc/dut/activate
add wave -noupdate /test_uhmc/dut/power_up_counter
add wave -noupdate /test_uhmc/dut/state
add wave -noupdate /test_uhmc/dut/return_after_command
add wave -noupdate /test_uhmc/dut/init_step
add wave -noupdate /test_uhmc/dut/out_data
add wave -noupdate /test_uhmc/dut/out_count
add wave -noupdate /test_uhmc/dut/next_out_data
add wave -noupdate /test_uhmc/dut/next_out_count
add wave -noupdate -divider init
add wave -noupdate /test_uhmc/dut/init
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {23135527 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 112
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
WaveRestoreZoom {13776805 ps} {165871035 ps}
