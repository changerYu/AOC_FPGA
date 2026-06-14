// ============================================================================
// CHIP.v -- M1c overlay of the FPGA SoC top. Identical to
// AOC-vcs-version/hardware/src/CHIP.v except it adds the UART input pin and the
// loader status outputs, plumbed straight through to the inner `top`. The UART
// loader itself lives in AXI_BRAM_Buffer_wrapper (next to the buffer BRAM).
// build_chip.tcl adds this overlay and excludes the original CHIP.v.
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================
module CHIP(
  input            cpu_clk,
  input            axi_clk,
  input            rom_clk,
  input            dram_clk,  // S5 FPGA buffer clock
  input            cpu_rst,
  input            axi_rst,
  input            rom_rst,
  input            dram_rst,

  // M1c: UART input -> FPGA buffer, plus loader status
  input            uart_rxd,
  output           data_ready,
  output           uart_err,
  output           rx_seen,

  output           result_valid,
  output [2:0]     result_class,
  output [7:0]     result_score
);

top u_TOP(
    .cpu_clk      (cpu_clk),
    .cpu_rst      (cpu_rst),
    .axi_clk      (axi_clk),
    .axi_rst      (axi_rst),
    .rom_clk      (rom_clk),
    .rom_rst      (rom_rst),
    .dram_clk     (dram_clk),
    .dram_rst     (dram_rst),
    .uart_rxd     (uart_rxd),
    .data_ready   (data_ready),
    .uart_err     (uart_err),
    .rx_seen      (rx_seen),
    .result_valid (result_valid),
    .result_class (result_class),
    .result_score (result_score)
);

endmodule
