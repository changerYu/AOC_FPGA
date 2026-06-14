# =============================================================================
# epu_nexys_video.xdc -- Phase A EPU-first bring-up constraints
# Board: Digilent Nexys Video (Artix-7 XC7A200T)
# Pins taken from Digilent's official Nexys-Video-Master.xdc (only signals used).
# ASCII-only comments (Big5/cp950 Windows console safe).
# =============================================================================

# ---- Bank 0 configuration voltage (clears DRC CFGBVS-1) ---------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ---- 100 MHz system clock (pin R4) -----------------------------------------
set_property -dict { PACKAGE_PIN R4  IOSTANDARD LVCMOS33 } [get_ports { clk100 }]
create_clock -name sys_clk -period 10.000 [get_ports { clk100 }]

# ---- Reset: center pushbutton BTNC (active-high when pressed) ---------------
set_property -dict { PACKAGE_PIN B22 IOSTANDARD LVCMOS12 } [get_ports { rst_btn }]

# ---- Display-select slide switches sw[1:0] (LVCMOS12) -----------------------
set_property -dict { PACKAGE_PIN E22 IOSTANDARD LVCMOS12 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN F21 IOSTANDARD LVCMOS12 } [get_ports { sw[1] }]

# ---- LEDs led[7:0] (LVCMOS25) ----------------------------------------------
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS25 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS25 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS25 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS25 } [get_ports { led[3] }]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS25 } [get_ports { led[4] }]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS25 } [get_ports { led[5] }]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS25 } [get_ports { led[6] }]
set_property -dict { PACKAGE_PIN Y13 IOSTANDARD LVCMOS25 } [get_ports { led[7] }]
