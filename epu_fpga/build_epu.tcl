# =============================================================================
# build_epu.tcl -- Phase A: standalone EPU-first FPGA build (Nexys Video)
#
# Usage (from D:\AOC-final\epu_fpga):
#     vivado -mode batch -source build_epu.tcl
#
# Flow: (re)create project -> add EPU RTL (minus EPU_Wrapper and the original
#       GLB) + FPGA overlay GLB (BRAM $readmemh init) + board top epu_top +
#       glb_init.hex + XDC -> synth -> impl -> write bitstream -> export reports
#       and epu_top.bit into build/.
#
# ASCII-only comments (Big5/cp950 Windows console safe).
# =============================================================================

# ---- Parameters -------------------------------------------------------------
set part      xc7a200tsbg484-1
set top       epu_top
set proj_name epu_fpga

set proj_dir  [file normalize [file dirname [info script]]]
set hw        [file normalize $proj_dir/../AOC-vcs-version/hardware]
set build_dir $proj_dir/build
set proj_path $build_dir/$proj_name

# ---- Clean rebuild ----------------------------------------------------------
file delete -force $proj_path
create_project $proj_name $proj_path -part $part -force

# ---- EPU RTL: all src/EPU/*.sv except EPU_Wrapper (AXI) and original GLB -----
set epu_files [glob $hw/src/EPU/*.sv]
set epu_files [lsearch -all -inline -not -glob $epu_files *EPU_Wrapper.sv]
set epu_files [lsearch -all -inline -not -glob $epu_files *GLB.sv]
add_files -fileset sources_1 $epu_files

# ---- FPGA overlay GLB (BRAM init) + board top -------------------------------
add_files -fileset sources_1 [list \
    $proj_dir/rtl/GLB.sv \
    $proj_dir/rtl/epu_top.sv ]

# ---- Memory init image (so $readmemh "glb_init.hex" resolves) ---------------
add_files -fileset sources_1 $proj_dir/glb_init.hex

# ---- Header as global include so all `define macros are visible everywhere ---
add_files -fileset sources_1 $hw/include/define.svh
set_property is_global_include true [get_files $hw/include/define.svh]

# Include dirs so relative `include "../../include/define.svh" also resolves.
set_property include_dirs [list $hw/include $hw/src/EPU] [get_filesets sources_1]

# ---- Constraints ------------------------------------------------------------
add_files -fileset constrs_1 $proj_dir/constraints/epu_nexys_video.xdc

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
