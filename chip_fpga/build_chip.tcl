# =============================================================================
# build_chip.tcl -- B0: full AOC SoC (CHIP) FPGA build for Nexys Video
#
# Usage (from D:\AOC-final\chip_fpga):
#     vivado -mode batch -source build_chip.tcl
#
# Flow: (re)create project -> add the curated FPGA RTL set from
#       AOC-vcs-version/hardware/src/rtl_fpga_auto.f (minus the original
#       ROM_wrapper, replaced by the absolute-path overlay; minus the stray
#       src/AXI_define.svh header) -> add chip_top board wrapper + rom*.hex +
#       XDC -> mark headers global include + set include dirs -> synth -> impl
#       -> write bitstream -> export reports and chip_top.bit into build/.
#
# Clocking: single 100 MHz to all four CHIP domains (see chip_top.sv header).
# If timing fails, switch AXI/rom/dram to a 50 MHz MMCME2_BASE clock.
#
# ASCII-only comments (Big5/cp950 Windows console safe).
# =============================================================================

# ---- Parameters -------------------------------------------------------------
set part      xc7a200tsbg484-1
set top       chip_top
set proj_name chip_fpga

set proj_dir  [file normalize [file dirname [info script]]]
set hw        [file normalize $proj_dir/../AOC-vcs-version/hardware]
set build_dir $proj_dir/build
set proj_path $build_dir/$proj_name

# ---- Clean rebuild ----------------------------------------------------------
file delete -force $proj_path
create_project $proj_name $proj_path -part $part -force

# ---- Parse the curated FPGA filelist ----------------------------------------
# rtl_fpga_auto.f lives in hardware/src and uses paths relative to that dir.
set flist [file normalize $hw/src/rtl_fpga_auto.f]
set fdir  [file dirname $flist]
set rtl   {}
set fh    [open $flist r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "//*" $line]} { continue }
    set abs [file normalize [file join $fdir $line]]
    # Skip headers (.svh) -- handled separately as global includes.
    if {[string match "*.svh" $abs]} { continue }
    # Skip the original ROM_wrapper -- replaced by the absolute-path overlay.
    if {[string match "*/ROM_wrapper.sv" $abs]} { continue }
    lappend rtl $abs
}
close $fh

puts "==== build_chip: adding [llength $rtl] RTL files from filelist ===="
add_files -fileset sources_1 $rtl

# ---- Board wrapper + ROM overlay (absolute-path $readmemh) -------------------
add_files -fileset sources_1 [list \
    $proj_dir/rtl/ROM_wrapper.sv \
    $proj_dir/rtl/chip_top.sv ]

# ---- ROM init images (so $readmemh absolute paths have the files present) ----
add_files -fileset sources_1 [list \
    $proj_dir/rom0.hex \
    $proj_dir/rom1.hex \
    $proj_dir/rom2.hex \
    $proj_dir/rom3.hex ]

# ---- Headers as global includes so `define macros are visible everywhere -----
# define.svh is `ifndef-guarded; AXI_define.svh is not (benign "redefined"
# warnings may appear from files that also explicitly `include it).
add_files -fileset sources_1 [list \
    $hw/include/define.svh \
    $hw/include/AXI_define.svh ]
set_property is_global_include true [get_files $hw/include/define.svh]
set_property is_global_include true [get_files $hw/include/AXI_define.svh]

# Include dirs so relative `include "../include/..." / "../../include/..." and
# intra-tree headers all resolve.
set_property include_dirs [list \
    $hw/include \
    $hw/src \
    $hw/src/EPU \
    $hw/src/AXI \
    $hw/src/CPU ] [get_filesets sources_1]

# ---- Constraints ------------------------------------------------------------
add_files -fileset constrs_1 $proj_dir/constraints/chip_nexys_video.xdc

# ---- Top --------------------------------------------------------------------
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# ---- Synthesis --------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed (synth_1). See $proj_path/$proj_name.runs/synth_1."
}

# ---- Implementation + bitstream ---------------------------------------------
# Timing-focused strategy with post-route phys_opt. The default strategy left
# cpu_clk@100 MHz at WNS -0.100 ns on 3 route-dominated endpoints (CPU pipeline
# mem_wb->if_id and an EPU reducer adder). This strategy's aggressive placement
# + post-route physical optimization is expected to recover that ~0.1 ns.
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed (impl_1). See $proj_path/$proj_name.runs/impl_1."
}

# ---- Export reports + bitstream ---------------------------------------------
open_run impl_1
report_utilization    -file $build_dir/utilization.rpt
report_timing_summary -file $build_dir/timing_summary.rpt

set bit [glob -nocomplain $proj_path/$proj_name.runs/impl_1/*.bit]
if {[llength $bit] == 1} {
    file copy -force [lindex $bit 0] $build_dir/$top.bit
    puts "==== BUILD OK, bitstream: build\\$top.bit ===="
} else {
    error "Bitstream not found. See impl_1 log."
}
