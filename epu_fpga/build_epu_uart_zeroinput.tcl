# =============================================================================
# build_epu_uart_zeroinput.tcl -- A: airtight-proof diagnostic build.
#   vivado -mode batch -source build_epu_uart_zeroinput.tcl
# Same as build_epu_uart.tcl but the GLB input region is baked ZERO
# (rtl_zeroinput/GLB.sv + glb_init_zeroinput.hex). Result with no UART should be
# NON-golden; only a real UART-streamed input yields class N / score 0x67.
# Output: build/epu_uart_top_zeroinput.bit
# =============================================================================

set part      xc7a200tsbg484-1
set top       epu_uart_top
set proj_name epu_uart_zi

set proj_dir  [file normalize [file dirname [info script]]]
set hw        [file normalize $proj_dir/../AOC-vcs-version/hardware]
set build_dir $proj_dir/build
set proj_path $build_dir/$proj_name

file delete -force $proj_path
create_project $proj_name $proj_path -part $part -force

# EPU core minus EPU_Wrapper and original GLB
set epu_files [glob $hw/src/EPU/*.sv]
set epu_files [lsearch -all -inline -not -glob $epu_files *EPU_Wrapper.sv]
set epu_files [lsearch -all -inline -not -glob $epu_files *GLB.sv]
add_files -fileset sources_1 $epu_files

# DIAGNOSTIC GLB (zeroed input) + UART RX + board top
add_files -fileset sources_1 [list \
    $proj_dir/rtl_zeroinput/GLB.sv \
    $proj_dir/rtl/uart_rx.sv \
    $proj_dir/rtl/epu_uart_top.sv ]

add_files -fileset sources_1 $proj_dir/glb_init_zeroinput.hex

add_files -fileset sources_1 $hw/include/define.svh
set_property is_global_include true [get_files $hw/include/define.svh]
set_property include_dirs [list $hw/include $hw/src/EPU] [get_filesets sources_1]

add_files -fileset constrs_1 $proj_dir/constraints/epu_uart_nexys_video.xdc

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed (synth_1)."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed (impl_1)."
}

open_run impl_1
set bit [glob -nocomplain $proj_path/$proj_name.runs/impl_1/*.bit]
if {[llength $bit] == 1} {
    file copy -force [lindex $bit 0] $build_dir/${top}_zeroinput.bit
    puts "==== BUILD OK, bitstream: build\\${top}_zeroinput.bit ===="
} else {
    error "Bitstream not found."
}
