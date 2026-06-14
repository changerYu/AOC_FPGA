# =============================================================================
# nexys_video.xdc  --  Milestone 1: switches -> LEDs
#
# Pins taken from Digilent's official Nexys Video master XDC (digilent-xdc),
# only the signals used by this design. Note the three different I/O voltages
# (a common Nexys Video gotcha):
#   - switches sw : LVCMOS12 (NOT 3.3V)
#   - LEDs    led : LVCMOS25
#   - clock   clk : LVCMOS33 (this milestone is pure combinational, no clock)
#
# Comments kept ASCII-only on purpose: tool-facing files decode reliably on a
# Big5/cp950 Windows console; UTF-8 Chinese here would render as garbage.
# =============================================================================

# ---- Bank 0 configuration voltage (clears DRC CFGBVS-1 warning) -------------
# Nexys Video config bank 0 is 3.3V.
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ---- Slide Switches (sw[0..7]) -- LVCMOS12 ----------------------------------
set_property -dict { PACKAGE_PIN E22  IOSTANDARD LVCMOS12 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN F21  IOSTANDARD LVCMOS12 } [get_ports { sw[1] }]
set_property -dict { PACKAGE_PIN G21  IOSTANDARD LVCMOS12 } [get_ports { sw[2] }]
set_property -dict { PACKAGE_PIN G22  IOSTANDARD LVCMOS12 } [get_ports { sw[3] }]
set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS12 } [get_ports { sw[4] }]
set_property -dict { PACKAGE_PIN J16  IOSTANDARD LVCMOS12 } [get_ports { sw[5] }]
set_property -dict { PACKAGE_PIN K13  IOSTANDARD LVCMOS12 } [get_ports { sw[6] }]
set_property -dict { PACKAGE_PIN M17  IOSTANDARD LVCMOS12 } [get_ports { sw[7] }]

# ---- LEDs (led[0..7]) -- LVCMOS25 -------------------------------------------
set_property -dict { PACKAGE_PIN T14  IOSTANDARD LVCMOS25 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN T15  IOSTANDARD LVCMOS25 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T16  IOSTANDARD LVCMOS25 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS25 } [get_ports { led[3] }]
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS25 } [get_ports { led[4] }]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS25 } [get_ports { led[5] }]
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS25 } [get_ports { led[6] }]
set_property -dict { PACKAGE_PIN Y13  IOSTANDARD LVCMOS25 } [get_ports { led[7] }]
