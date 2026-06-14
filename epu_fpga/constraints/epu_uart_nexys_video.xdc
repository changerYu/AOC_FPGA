# =============================================================================
# epu_uart_nexys_video.xdc -- B1: UART -> standalone EPU (Nexys Video, XC7A200T)
# Pins from Digilent Nexys-Video-Master.xdc. ASCII-only comments.
# =============================================================================

set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ---- 100 MHz system clock (R4) ---------------------------------------------
set_property -dict { PACKAGE_PIN R4  IOSTANDARD LVCMOS33 } [get_ports { clk100 }]
create_clock -name sys_clk -period 10.000 [get_ports { clk100 }]

# ---- Buttons (active-high) -------------------------------------------------
set_property -dict { PACKAGE_PIN D22 IOSTANDARD LVCMOS12 } [get_ports { rst_btn }]   ;# BTND
set_property -dict { PACKAGE_PIN B22 IOSTANDARD LVCMOS12 } [get_ports { start_btn }] ;# BTNC

# ---- Display-select switches sw[1:0] ---------------------------------------
set_property -dict { PACKAGE_PIN E22 IOSTANDARD LVCMOS12 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN F21 IOSTANDARD LVCMOS12 } [get_ports { sw[1] }]

# ---- UART over Pmod JA (3.3 V) ---------------------------------------------
# JA1 = AB22 : FPGA RX  <- ESP32 GPIO17 (TX)
# JA7 = Y21  : FPGA TX  -> ESP32 GPIO16 (RX)
# GND: Pmod JA pin 5 or 11 <-> ESP32 GND
set_property -dict { PACKAGE_PIN AB22 IOSTANDARD LVCMOS33 } [get_ports { uart_rxd }]
set_property -dict { PACKAGE_PIN Y21  IOSTANDARD LVCMOS33 } [get_ports { uart_txd }]

# Async UART input: relax timing (double-flop synchronized inside uart_rx).
set_false_path -to [get_pins -hier -filter {NAME =~ *u_rx/rxd_q_reg[0]*/D}]

# ---- LEDs led[7:0] ---------------------------------------------------------
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS25 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS25 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS25 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS25 } [get_ports { led[3] }]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS25 } [get_ports { led[4] }]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS25 } [get_ports { led[5] }]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS25 } [get_ports { led[6] }]
set_property -dict { PACKAGE_PIN Y13 IOSTANDARD LVCMOS25 } [get_ports { led[7] }]
