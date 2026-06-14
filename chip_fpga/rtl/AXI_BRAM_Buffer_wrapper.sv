`include "../include/AXI_define.svh"

// ============================================================================
// AXI_BRAM_Buffer_wrapper.sv -- M1b overlay for the FPGA buffer slave (S5).
//
// Identical to AOC-vcs-version/.../src/AXI_BRAM_Buffer_wrapper.sv EXCEPT it
// instantiates SRAM_wrapper_buf (BRAM pre-initialized from buf_init.hex) instead
// of the plain SRAM_wrapper. This makes the buffer power up holding the ECG
// input, decoupling it from the CPU boot path (boot.c no longer loads it).
// build_chip.tcl adds this overlay and excludes the original.
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================
module AXI_BRAM_Buffer_wrapper(
    input  logic                      clk,
    input  logic                      rst,

    input  logic [`AXI_IDS_BITS-1:0]  AWID,
    input  logic [`AXI_ADDR_BITS-1:0] AWADDR,
    input  logic [`AXI_LEN_BITS-1:0]  AWLEN,
    input  logic [`AXI_SIZE_BITS-1:0] AWSIZE,
    input  logic [1:0]                AWBURST,
    input  logic                      AWVALID,
    output logic                      AWREADY,

    input  logic [`AXI_DATA_BITS-1:0] WDATA,
    input  logic [`AXI_STRB_BITS-1:0] WSTRB,
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,

    output logic [`AXI_IDS_BITS-1:0]  BID,
    output logic [1:0]                BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,

    input  logic [`AXI_IDS_BITS-1:0]  ARID,
    input  logic [`AXI_ADDR_BITS-1:0] ARADDR,
    input  logic [`AXI_LEN_BITS-1:0]  ARLEN,
    input  logic [`AXI_SIZE_BITS-1:0] ARSIZE,
    input  logic [1:0]                ARBURST,
    input  logic                      ARVALID,
    output logic                      ARREADY,

    output logic [`AXI_IDS_BITS-1:0]  RID,
    output logic [`AXI_DATA_BITS-1:0] RDATA,
    output logic                      RLAST,
    output logic [1:0]                RRESP,
    output logic                      RVALID,
    input  logic                      RREADY,

    // ---- M1c: UART input loader (writes BRAM port B) -----------------------
    input  logic                      uart_rxd,    // async serial in
    output logic                      data_ready,  // full valid frame stored
    output logic                      uart_err,    // checksum mismatch
    output logic                      rx_seen      // any UART byte seen
);

    // UART loader -> BRAM port B write bus
    logic        pb_we;
    logic [13:0] pb_addr;
    logic [31:0] pb_wdata;

    uart_buffer_loader #(.CLK_HZ(50_000_000), .BAUD(115_200)) u_loader (
        .clk        (clk),
        .rst_n      (~rst),          // wrapper reset is active-high
        .uart_rxd   (uart_rxd),
        .pb_we      (pb_we),
        .pb_addr    (pb_addr),
        .pb_wdata   (pb_wdata),
        .data_ready (data_ready),
        .uart_err   (uart_err),
        .rx_seen    (rx_seen)
    );

    SRAM_wrapper_buf u_buffer_bram (
        .clk       (clk),
        .rst       (rst),
        .AWID_S    (AWID),
        .AWADDR_S  (AWADDR),
        .AWLEN_S   (AWLEN),
        .AWSIZE_S  (AWSIZE),
        .AWBURST_S (AWBURST),
        .AWVALID_S (AWVALID),
        .AWREADY_S (AWREADY),
        .WDATA_S   (WDATA),
        .WSTRB_S   (WSTRB),
        .WLAST_S   (WLAST),
        .WVALID_S  (WVALID),
        .WREADY_S  (WREADY),
        .BID_S     (BID),
        .BRESP_S   (BRESP),
        .BVALID_S  (BVALID),
        .BREADY_S  (BREADY),
        .ARID_S    (ARID),
        .ARADDR_S  (ARADDR),
        .ARLEN_S   (ARLEN),
        .ARSIZE_S  (ARSIZE),
        .ARBURST_S (ARBURST),
        .ARVALID_S (ARVALID),
        .ARREADY_S (ARREADY),
        .RID_S     (RID),
        .RDATA_S   (RDATA),
        .RLAST_S   (RLAST),
        .RRESP_S   (RRESP),
        .RVALID_S  (RVALID),
        .RREADY_S  (RREADY),
        .pb_we     (pb_we),
        .pb_addr   (pb_addr),
        .pb_wdata  (pb_wdata)
    );

endmodule
