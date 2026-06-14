# =============================================================================
# build.tcl  --  Nexys Video, Project Mode build script
#
# Usage (run from D:\AOC-final):
#     vivado -mode batch -source build.tcl
#
# Flow: (re)create project -> add HDL from src/ and XDC from constraints/ ->
#       set top -> synthesize -> implement -> write bitstream ->
#       export reports and top.bit into build/
#
# After it finishes you can open the GUI to inspect the result:
#     vivado build\aoc_final\aoc_final.xpr
# (Sources / Schematic / Implemented Design / reports)
#
# NOTE: comments kept ASCII-only so the Big5/cp950 Windows console does not
#       mangle them in the log.
# =============================================================================

# ---- Parameters -------------------------------------------------------------
set part      xc7a200tsbg484-1
set top       top
set proj_name aoc_final

# Script directory is the project root (independent of the caller's CWD)
set proj_dir  [file normalize [file dirname [info script]]]
set build_dir $proj_dir/build
set proj_path $build_dir/$proj_name

# ---- Clean rebuild (reproducible results every run) -------------------------
file delete -force $proj_path
create_project $proj_name $proj_path -part $part -force

# ---- Add sources ------------------------------------------------------------
add_files -fileset sources_1 [glob $proj_dir/src/*.v]
add_files -fileset constrs_1 [glob $proj_dir/constraints/*.xdc]
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# ---- Synthesis --------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed (synth_1). See build/$proj_name/$proj_name.runs/synth_1 log."
}

# ---- Implementation + bitstream ---------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed (impl_1). See build/$proj_name/$proj_name.runs/impl_1 log."
}

# ---- Export reports and bitstream into build/ for convenience ---------------
open_run impl_1
report_utilization     -file $build_dir/utilization.rpt
report_timing_summary  -file $build_dir/timing_summary.rpt

set bit [glob -nocomplain $proj_path/$proj_name.runs/impl_1/*.bit]
if {[llength $bit] == 1} {
    file copy -force [lindex $bit 0] $build_dir/$top.bit
    puts "==== BUILD OK, bitstream: build\\$top.bit ===="
} else {
    error "Bitstream not found. See impl_1 log."
}
