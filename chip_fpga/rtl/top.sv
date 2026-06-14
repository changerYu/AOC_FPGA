

module top (
//* system
input cpu_clk, 
input axi_clk,
input rom_clk,
// S5 buffer clock domain. This keeps the original AXI_fifo DRAM-domain CDC
// ports but the external DRAM interface is replaced by FPGA BRAM.
input dram_clk,
input cpu_rst,
input axi_rst,
input rom_rst,
input dram_rst,

//* M1c: UART input -> FPGA buffer (S5) port B, plus loader status
input        uart_rxd,
output logic data_ready,
output logic uart_err,
output logic rx_seen,

//* FPGA classification output
// result_class encoding: 0=N, 1=S, 2=V, 3=F, 4=Q
output logic       result_valid,
output logic [2:0] result_class,
output logic [7:0] result_score
);

	// user defined AXI parameters
    localparam DATA_WIDTH              = 32;
    localparam ADDR_WIDTH              = 32;
    localparam ID_WIDTH                = 4;
    localparam IDS_WIDTH               = 8;
    localparam LEN_WIDTH               = 4;
    localparam MAXLEN                  = 4;
    // fixed AXI parameters
    localparam STRB_WIDTH              = DATA_WIDTH/8;
    localparam SIZE_WIDTH              = 3;
    localparam BURST_WIDTH             = 2;  
    localparam CACHE_WIDTH             = 4;  
    localparam PROT_WIDTH              = 3;  
    localparam BRESP_WIDTH             = 2; 
    localparam RRESP_WIDTH             = 2;      
    localparam AWUSER_WIDTH            = 32; // Size of AWUser field
    localparam WUSER_WIDTH             = 32; // Size of WUser field
    localparam BUSER_WIDTH             = 32; // Size of BUser field
    localparam ARUSER_WIDTH            = 32; // Size of ARUser field
    localparam RUSER_WIDTH             = 32; // Size of RUser field
    localparam QOS_WIDTH               = 4;  // Size of QOS field
    localparam REGION_WIDTH            = 4;  // Size of Region field


    // Slave Interface for Masters
    
    // Write Address
    logic [`AXI_ID_BITS-1:0] awid_m1;
    logic [`AXI_ADDR_BITS-1:0] awaddr_m1;
    logic [`AXI_LEN_BITS-1:0] awlen_m1;
    logic [`AXI_SIZE_BITS-1:0] awsize_m1;
    logic [1:0] awburst_m1;
    logic awvalid_m1;
    logic awready_m1;
    
    // Write Data
    logic [`AXI_DATA_BITS-1:0] wdata_m1;
    logic [`AXI_STRB_BITS-1:0] wstrb_m1;
    logic wlast_m1;
    logic wvalid_m1;
    logic wready_m1;
    
    // Write Response
    logic [`AXI_ID_BITS-1:0] bid_m1;
    logic [1:0] bresp_m1;
    logic bvalid_m1;
    logic bready_m1;
	
	// Write Address
    logic [`AXI_ID_BITS-1:0] awid_m2;
    logic [`AXI_ADDR_BITS-1:0] awaddr_m2;
    logic [`AXI_LEN_BITS-1:0] awlen_m2;
    logic [`AXI_SIZE_BITS-1:0] awsize_m2;
    logic [1:0] awburst_m2;
    logic awvalid_m2;
    logic awready_m2;
    
    // Write Data
    logic [`AXI_DATA_BITS-1:0] wdata_m2;
    logic [`AXI_STRB_BITS-1:0] wstrb_m2;
    logic wlast_m2;
    logic wvalid_m2;
    logic wready_m2;
    
    // Write Response
    logic [`AXI_ID_BITS-1:0] bid_m2;
    logic [1:0] bresp_m2;
    logic bvalid_m2;
    logic bready_m2;

    // Read Address0
    logic [`AXI_ID_BITS-1:0] arid_m0;
    logic [`AXI_ADDR_BITS-1:0] araddr_m0;
    logic [`AXI_LEN_BITS-1:0] arlen_m0;
    logic [`AXI_SIZE_BITS-1:0] arsize_m0;
    logic [1:0] arburst_m0;
    logic arvalid_m0;
    logic arready_m0;
    
    // Read Data0
    logic [`AXI_ID_BITS-1:0] rid_m0;
    logic [`AXI_DATA_BITS-1:0] rdata_m0;
    logic [1:0] rresp_m0;
    logic rlast_m0;
    logic rvalid_m0;
    logic rready_m0;
    
    // Read Address1
    logic [`AXI_ID_BITS-1:0] arid_m1;
    logic [`AXI_ADDR_BITS-1:0] araddr_m1;
    logic [`AXI_LEN_BITS-1:0] arlen_m1;
    logic [`AXI_SIZE_BITS-1:0] arsize_m1;
    logic [1:0] arburst_m1;
    logic arvalid_m1;
    logic arready_m1;
    
    // Read Data1
    logic [`AXI_ID_BITS-1:0] rid_m1;
    logic [`AXI_DATA_BITS-1:0] rdata_m1;
    logic [1:0] rresp_m1;
    logic rlast_m1;
    logic rvalid_m1;
    logic rready_m1;
	
	// Read Address1
    logic [`AXI_ID_BITS-1:0] arid_m2;
    logic [`AXI_ADDR_BITS-1:0] araddr_m2;
    logic [`AXI_LEN_BITS-1:0] arlen_m2;
    logic [`AXI_SIZE_BITS-1:0] arsize_m2;
    logic [1:0] arburst_m2;
    logic arvalid_m2;
    logic arready_m2;
    
    // Read Data1
    logic [`AXI_ID_BITS-1:0] rid_m2;
    logic [`AXI_DATA_BITS-1:0] rdata_m2;
    logic [1:0] rresp_m2;
    logic rlast_m2;
    logic rvalid_m2;
    logic rready_m2;

    // Master Interface for Slaves
	// Read Address0
    logic [`AXI_IDS_BITS-1:0] arid_s0;
    logic [`AXI_ADDR_BITS-1:0] araddr_s0;
    logic [`AXI_LEN_BITS-1:0] arlen_s0;
    logic [`AXI_SIZE_BITS-1:0] arsize_s0;
    logic [1:0] arburst_s0;
    logic arvalid_s0;
    logic arready_s0;
    
    // Read Data0
    logic [`AXI_IDS_BITS-1:0] rid_s0;
    logic [`AXI_DATA_BITS-1:0] rdata_s0;
    logic [1:0] rresp_s0;
    logic rlast_s0;
    logic rvalid_s0;
    logic rready_s0;
	
	
    // Read Address1
    logic [`AXI_IDS_BITS-1:0] arid_s1;
    logic [`AXI_ADDR_BITS-1:0] araddr_s1;
    logic [`AXI_LEN_BITS-1:0] arlen_s1;
    logic [`AXI_SIZE_BITS-1:0] arsize_s1;
    logic [1:0] arburst_s1;
    logic arvalid_s1;
    logic arready_s1;
    
    // Read Data1
    logic [`AXI_IDS_BITS-1:0] rid_s1;
    logic [`AXI_DATA_BITS-1:0] rdata_s1;
    logic [1:0] rresp_s1;
    logic rlast_s1;
    logic rvalid_s1;
    logic rready_s1;
    // Write Address1
    logic [`AXI_IDS_BITS-1:0] awid_s1;
    logic [`AXI_ADDR_BITS-1:0] awaddr_s1;
    logic [`AXI_LEN_BITS-1:0] awlen_s1;
    logic [`AXI_SIZE_BITS-1:0] awsize_s1;
    logic [1:0] awburst_s1;
    logic awvalid_s1;
    logic awready_s1;
    
    // Write Data1
    logic [`AXI_DATA_BITS-1:0] wdata_s1;
    logic [`AXI_STRB_BITS-1:0] wstrb_s1;
    logic wlast_s1;
    logic wvalid_s1;
    logic wready_s1;
    // Write Response1
    logic [`AXI_IDS_BITS-1:0] bid_s1;
    logic [1:0] bresp_s1;
    logic bvalid_s1;
    logic bready_s1;
	
	// New ports in lowercase
    // Read Address Channel from S2 to S7
    logic arready_s2;
    // logic arready_s3;
    // logic arready_s4;
    logic arready_s5;
    logic arready_s6;
    
    logic [`AXI_ADDR_BITS-1:0] araddr_s2;
    logic [`AXI_IDS_BITS-1:0] arid_s2;
    logic [`AXI_LEN_BITS-1:0] arlen_s2;
    logic [`AXI_SIZE_BITS-1:0] arsize_s2;
    logic [1:0] arburst_s2;
    logic arvalid_s2;
    
    // logic [`AXI_ADDR_BITS-1:0] araddr_s3;
    // logic [`AXI_IDS_BITS-1:0] arid_s3;
    // logic [`AXI_LEN_BITS-1:0] arlen_s3;
    // logic [`AXI_SIZE_BITS-1:0] arsize_s3;
    // logic [1:0] arburst_s3;
    // logic arvalid_s3;
    
    // logic [`AXI_ADDR_BITS-1:0] araddr_s4;
    // logic [`AXI_IDS_BITS-1:0] arid_s4;
    // logic [`AXI_LEN_BITS-1:0] arlen_s4;
    // logic [`AXI_SIZE_BITS-1:0] arsize_s4;
    // logic [1:0] arburst_s4;
    // logic arvalid_s4;
    
    logic [`AXI_ADDR_BITS-1:0] araddr_s5;
    logic [`AXI_IDS_BITS-1:0] arid_s5;
    logic [`AXI_LEN_BITS-1:0] arlen_s5;
    logic [`AXI_SIZE_BITS-1:0] arsize_s5;
    logic [1:0] arburst_s5;
    logic arvalid_s5;
	
	logic [`AXI_ADDR_BITS-1:0] araddr_s6;
    logic [`AXI_IDS_BITS-1:0] arid_s6;
    logic [`AXI_LEN_BITS-1:0] arlen_s6;
    logic [`AXI_SIZE_BITS-1:0] arsize_s6;
    logic [1:0] arburst_s6;
    logic arvalid_s6;


    // Write Address Channel S2 to S6
    logic awready_s2;
    logic awready_s3;
    logic awready_s4;
    logic awready_s5;
	logic awready_s6;

    
    logic [`AXI_ADDR_BITS-1:0] awaddr_s2;
    logic [`AXI_IDS_BITS-1:0] awid_s2;
    logic [`AXI_LEN_BITS-1:0] awlen_s2;
    logic [`AXI_SIZE_BITS-1:0] awsize_s2;
    logic [1:0] awburst_s2;
    logic awvalid_s2;
    
    logic [`AXI_ADDR_BITS-1:0] awaddr_s3;
    logic [`AXI_IDS_BITS-1:0] awid_s3;
    logic [`AXI_LEN_BITS-1:0] awlen_s3;
    logic [`AXI_SIZE_BITS-1:0] awsize_s3;
    logic [1:0] awburst_s3;
    logic awvalid_s3;
    
    logic [`AXI_ADDR_BITS-1:0] awaddr_s4;
    logic [`AXI_IDS_BITS-1:0] awid_s4;
    logic [`AXI_LEN_BITS-1:0] awlen_s4;
    logic [`AXI_SIZE_BITS-1:0] awsize_s4;
    logic [1:0] awburst_s4;
    logic awvalid_s4;
    
    logic [`AXI_ADDR_BITS-1:0] awaddr_s5;
    logic [`AXI_IDS_BITS-1:0] awid_s5;
    logic [`AXI_LEN_BITS-1:0] awlen_s5;
    logic [`AXI_SIZE_BITS-1:0] awsize_s5;
    logic [1:0] awburst_s5;
    logic awvalid_s5;

	logic [`AXI_ADDR_BITS-1:0] awaddr_s6;
    logic [`AXI_IDS_BITS-1:0] awid_s6;
    logic [`AXI_LEN_BITS-1:0] awlen_s6;
    logic [`AXI_SIZE_BITS-1:0] awsize_s6;
    logic [1:0] awburst_s6;
    logic awvalid_s6;



    // Read Data Channel S2 to S5
    logic [`AXI_IDS_BITS-1:0] rid_s2;
    logic [`AXI_DATA_BITS-1:0] rdata_s2;
    logic rvalid_s2;
    logic [1:0] rresp_s2;
    logic rlast_s2;

    // logic [`AXI_IDS_BITS-1:0] rid_s3;
    // logic [`AXI_DATA_BITS-1:0] rdata_s3;
    // logic rvalid_s3;
    // logic [1:0] rresp_s3;
    // logic rlast_s3;

    // logic [`AXI_IDS_BITS-1:0] rid_s4;
    // logic [`AXI_DATA_BITS-1:0] rdata_s4;
    // logic rvalid_s4;
    // logic [1:0] rresp_s4;
    // logic rlast_s4;

    logic [`AXI_IDS_BITS-1:0] rid_s5;
    logic [`AXI_DATA_BITS-1:0] rdata_s5;
    logic rvalid_s5;
    logic [1:0] rresp_s5;
    logic rlast_s5;

	logic [`AXI_IDS_BITS-1:0] rid_s6;
    logic [`AXI_DATA_BITS-1:0] rdata_s6;
    logic rvalid_s6;
    logic [1:0] rresp_s6;
    logic rlast_s6;

    logic rready_s2;
    // logic rready_s3;
    // logic rready_s4;
    logic rready_s5;
	logic rready_s6;

    logic wready_s2;
    logic wready_s3;
    logic wready_s4;
    logic wready_s5;
	logic wready_s6;
    
    logic [`AXI_DATA_BITS-1:0] wdata_s2;
    logic [`AXI_STRB_BITS-1:0] wstrb_s2;
    logic wlast_s2;
    logic wvalid_s2;
    
    logic [`AXI_DATA_BITS-1:0] wdata_s3;
    logic [`AXI_STRB_BITS-1:0] wstrb_s3;
    logic wlast_s3;
    logic wvalid_s3;
    
    logic [`AXI_DATA_BITS-1:0] wdata_s4;
    logic [`AXI_STRB_BITS-1:0] wstrb_s4;
    logic wlast_s4;
    logic wvalid_s4;
    
    logic [`AXI_DATA_BITS-1:0] wdata_s5;
    logic [`AXI_STRB_BITS-1:0] wstrb_s5;
    logic wlast_s5;
    logic wvalid_s5;
    
	logic [`AXI_DATA_BITS-1:0] wdata_s6;
    logic [`AXI_STRB_BITS-1:0] wstrb_s6;
    logic wlast_s6;
    logic wvalid_s6;
    // Write Response Channel S2 to S5
    logic [`AXI_IDS_BITS-1:0] bid_s2;
    logic [1:0] bresp_s2;
    logic bvalid_s2;
    
    logic [`AXI_IDS_BITS-1:0] bid_s3;
    logic [1:0] bresp_s3;
    logic bvalid_s3;
    
    logic [`AXI_IDS_BITS-1:0] bid_s4;
    logic [1:0] bresp_s4;
    logic bvalid_s4;
    
    logic [`AXI_IDS_BITS-1:0] bid_s5;
    logic [1:0] bresp_s5;
    logic bvalid_s5;

	logic [`AXI_IDS_BITS-1:0] bid_s6;
    logic [1:0] bresp_s6;
    logic bvalid_s6;
    
    
    logic bready_s2;
    logic bready_s3;
    logic bready_s4;
    logic bready_s5;
	logic bready_s6;
	
	
	/////WDT
	logic [`AXI_DATA_BITS-1:0] WTOCNT;
	logic WDEN, WDLIVE;
	logic WTO;

	logic layer_done, intr_epu;
	
	/////DMA
	logic DMA_interrupt;

/*===========================AXI===========================*/	
AXI_fifo AXI_fifo(
	.CPU_CLK_i(cpu_clk),    
    .CPU_RST_i(cpu_rst),
	.AXI_CLK_i(axi_clk),        
    .AXI_RST_i(axi_rst),  
	.ROM_CLK_i(rom_clk), 
    .ROM_RST_i(rom_rst), 
    .SRAM_CLK_i(cpu_clk),
    .SRAM_RST_i(cpu_rst), 
    .WDT_CLK_i(rom_clk),
    .WDT_RST_i(rom_rst),
	.DMA_CLK_i(cpu_clk),        
	.DMA_RST_i(cpu_rst),
    .DRAM_CLK_i(dram_clk),
	.DRAM_RST_i(dram_rst),

	//MASTER INTERFACE

	.ARID_M0_i(arid_m0),
	.ARADDR_M0_i(araddr_m0),
	.ARLEN_M0_i(arlen_m0),
	.ARSIZE_M0_i(arsize_m0),
	.ARBURST_M0_i(arburst_m0),
	.ARVALID_M0_i(arvalid_m0),
	.ARREADY_M0_o(arready_m0),
	.RID_M0_o(rid_m0),
	.RDATA_M0_o(rdata_m0),
	.RRESP_M0_o(rresp_m0),
	.RLAST_M0_o(rlast_m0),
	.RVALID_M0_o(rvalid_m0),
	.RREADY_M0_i(rready_m0),
	// axi_m1_cdc
	// WRITE
	.AWID_M1_i(awid_m1),
	.AWADDR_M1_i(awaddr_m1),
	.AWLEN_M1_i(awlen_m1),
	.AWSIZE_M1_i(awsize_m1),
	.AWBURST_M1_i(awburst_m1),
	.AWVALID_M1_i(awvalid_m1),
	.AWREADY_M1_o(awready_m1),

	.WDATA_M1_i(wdata_m1),
	.WSTRB_M1_i(wstrb_m1),
	.WLAST_M1_i(wlast_m1),
	.WVALID_M1_i(wvalid_m1),
	.WREADY_M1_o(wready_m1),
	.BID_M1_o(bid_m1),
	.BRESP_M1_o(bresp_m1),
	.BVALID_M1_o(bvalid_m1),
	.BREADY_M1_i(bready_m1),
	// READ
	.ARID_M1_i(arid_m1),
	.ARADDR_M1_i(araddr_m1),
	.ARLEN_M1_i(arlen_m1),
	.ARSIZE_M1_i(arsize_m1),
	.ARBURST_M1_i(arburst_m1),
	.ARVALID_M1_i(arvalid_m1),
	.ARREADY_M1_o(arready_m1),
	.RID_M1_o(rid_m1),
	.RDATA_M1_o(rdata_m1),
	.RRESP_M1_o(rresp_m1),
	.RLAST_M1_o(rlast_m1),
	.RVALID_M1_o(rvalid_m1),
	.RREADY_M1_i(rready_m1),
	// axi_m2_cdc(DMA)
	// WRITE
	.AWID_M2_i(awid_m2),
	.AWADDR_M2_i(awaddr_m2),
	.AWLEN_M2_i(awlen_m2),
	.AWSIZE_M2_i(awsize_m2),
	.AWBURST_M2_i(awburst_m2),
	.AWVALID_M2_i(awvalid_m2),
	.AWREADY_M2_o(awready_m2),
	.WDATA_M2_i(wdata_m2),
	.WSTRB_M2_i(wstrb_m2),
	.WLAST_M2_i(wlast_m2),
	.WVALID_M2_i(wvalid_m2),
	.WREADY_M2_o(wready_m2),
	.BID_M2_o(bid_m2),
	.BRESP_M2_o(bresp_m2),
	.BVALID_M2_o(bvalid_m2),
	.BREADY_M2_i(bready_m2),
	// READ
	.ARID_M2_i(arid_m2),
	.ARADDR_M2_i(araddr_m2),
	.ARLEN_M2_i(arlen_m2),
	.ARSIZE_M2_i(arsize_m2),
	.ARBURST_M2_i(arburst_m2),
	.ARVALID_M2_i(arvalid_m2),
	.ARREADY_M2_o(arready_m2),
	.RID_M2_o(rid_m2),
	.RDATA_M2_o(rdata_m2),
	.RRESP_M2_o(rresp_m2),
	.RLAST_M2_o(rlast_m2),
	.RVALID_M2_o(rvalid_m2),
	.RREADY_M2_i(rready_m2),
	//SLAVE INTERFACE
	// axi_s0_cdc
	// READ
	.ARID_S0_o(arid_s0),
	.ARADDR_S0_o(araddr_s0),
	.ARLEN_S0_o(arlen_s0),
	.ARSIZE_S0_o(arsize_s0),
	.ARBURST_S0_o(arburst_s0),
	.ARVALID_S0_o(arvalid_s0),
	.ARREADY_S0_i(arready_s0),
	.RID_S0_i(rid_s0),
	.RDATA_S0_i(rdata_s0),
	.RRESP_S0_i(rresp_s0),
	.RLAST_S0_i(rlast_s0),
	.RVALID_S0_i(rvalid_s0),
	.RREADY_S0_o(rready_s0),
	// axi_s1_cdc
	// WRITE

	.AWID_S1_o(awid_s1),
	.AWADDR_S1_o(awaddr_s1),
	.AWLEN_S1_o(awlen_s1),
	.AWSIZE_S1_o(awsize_s1),
	.AWBURST_S1_o(awburst_s1),
	.AWVALID_S1_o(awvalid_s1),
	.AWREADY_S1_i(awready_s1),
	.WDATA_S1_o(wdata_s1),
	.WSTRB_S1_o(wstrb_s1),
	.WLAST_S1_o(wlast_s1),
	.WVALID_S1_o(wvalid_s1),
	.WREADY_S1_i(wready_s1),
	.BID_S1_i(bid_s1),
	.BRESP_S1_i(bresp_s1),
	.BVALID_S1_i(bvalid_s1),
	.BREADY_S1_o(bready_s1),
	// READ
	.ARID_S1_o(arid_s1),
	.ARADDR_S1_o(araddr_s1),
	.ARLEN_S1_o(arlen_s1),
	.ARSIZE_S1_o(arsize_s1),
	.ARBURST_S1_o(arburst_s1),
	.ARVALID_S1_o(arvalid_s1),
	.ARREADY_S1_i(arready_s1),
	.RID_S1_i(rid_s1),
	.RDATA_S1_i(rdata_s1),
	.RRESP_S1_i(rresp_s1),
	.RLAST_S1_i(rlast_s1),
	.RVALID_S1_i(rvalid_s1),
	.RREADY_S1_o(rready_s1),
	// axi_s2_cdc
	// WRITE
	.AWID_S2_o(awid_s2),
	.AWADDR_S2_o(awaddr_s2),
	.AWLEN_S2_o(awlen_s2),
	.AWSIZE_S2_o(awsize_s2),
	.AWBURST_S2_o(awburst_s2),
	.AWVALID_S2_o(awvalid_s2),
	.AWREADY_S2_i(awready_s2),
	.WDATA_S2_o(wdata_s2),
	.WSTRB_S2_o(wstrb_s2),
	.WLAST_S2_o(wlast_s2),
	.WVALID_S2_o(wvalid_s2),
	.WREADY_S2_i(wready_s2),
	.BID_S2_i(bid_s2),
	.BRESP_S2_i(bresp_s2),
	.BVALID_S2_i(bvalid_s2),
	.BREADY_S2_o(bready_s2),
	// READ
	.ARID_S2_o(arid_s2),
	.ARADDR_S2_o(araddr_s2),
	.ARLEN_S2_o(arlen_s2),
	.ARSIZE_S2_o(arsize_s2),
	.ARBURST_S2_o(arburst_s2),
	.ARVALID_S2_o(arvalid_s2),
	.ARREADY_S2_i(arready_s2),
	.RID_S2_i(rid_s2),
	.RDATA_S2_i(rdata_s2),
	.RRESP_S2_i(rresp_s2),
	.RLAST_S2_i(rlast_s2),
	.RVALID_S2_i(rvalid_s2),
	.RREADY_S2_o(rready_s2),
	// axi_s3_cdc
	// WRITE

	.AWID_S3_o(awid_s3),
	.AWADDR_S3_o(awaddr_s3),
	.AWLEN_S3_o(awlen_s3),
	.AWSIZE_S3_o(awsize_s3),
	.AWBURST_S3_o(awburst_s3),
	.AWVALID_S3_o(awvalid_s3),
	.AWREADY_S3_i(awready_s3),
	.WDATA_S3_o(wdata_s3),
	.WSTRB_S3_o(wstrb_s3),
	.WLAST_S3_o(wlast_s3),
	.WVALID_S3_o(wvalid_s3),
	.WREADY_S3_i(wready_s3),
	.BID_S3_i(bid_s3),
	.BRESP_S3_i(bresp_s3),
	.BVALID_S3_i(bvalid_s3),
	.BREADY_S3_o(bready_s3),
	// // READ
	// .ARID_S3_o(),
	// .ARADDR_S3_o(),
	// .ARLEN_S3_o(),
	// .ARSIZE_S3_o(),
	// .ARBURST_S3_o(),
	// .ARVALID_S3_o(),
	// .ARREADY_S3_i(),
	// .RID_S3_i(),
	// .RDATA_S3_i(),
	// .RRESP_S3_i(),
	// .RLAST_S3_i(),
	// .RVALID_S3_i(),
	// .RREADY_S3_o(),
	// axi_s4_cdc
	// WRITE

	.AWID_S4_o(awid_s4),
	.AWADDR_S4_o(awaddr_s4),
	.AWLEN_S4_o(awlen_s4),
	.AWSIZE_S4_o(awsize_s4),
	.AWBURST_S4_o(awburst_s4),
	.AWVALID_S4_o(awvalid_s4),
	.AWREADY_S4_i(awready_s4),
	.WDATA_S4_o(wdata_s4),
	.WSTRB_S4_o(wstrb_s4),
	.WLAST_S4_o(wlast_s4),
	.WVALID_S4_o(wvalid_s4),
	.WREADY_S4_i(wready_s4),
	.BID_S4_i(bid_s4),
	.BRESP_S4_i(bresp_s4),
	.BVALID_S4_i(bvalid_s4),
	.BREADY_S4_o(bready_s4),
	// // READ
	// .ARID_S4_o(),
	// .ARADDR_S4_o(),
	// .ARLEN_S4_o(),
	// .ARSIZE_S4_o(),
	// .ARBURST_S4_o(),
	// .ARVALID_S4_o(),
	// .ARREADY_S4_i(),
	// .RID_S4_i(),
	// .RDATA_S4_i(),
	// .RRESP_S4_i(),
	// .RLAST_S4_i(),
	// .RVALID_S4_i(),
	// .RREADY_S4_o(),
	// axi_s5_cdc
	// WRITE
	.AWID_S5_o(awid_s5),
	.AWADDR_S5_o(awaddr_s5),
	.AWLEN_S5_o(awlen_s5),
	.AWSIZE_S5_o(awsize_s5),
	.AWBURST_S5_o(awburst_s5),
	.AWVALID_S5_o(awvalid_s5),
	.AWREADY_S5_i(awready_s5),
	.WDATA_S5_o(wdata_s5),
	.WSTRB_S5_o(wstrb_s5),
	.WLAST_S5_o(wlast_s5),
	.WVALID_S5_o(wvalid_s5),
	.WREADY_S5_i(wready_s5),
	.BID_S5_i(bid_s5),
	.BRESP_S5_i(bresp_s5),
	.BVALID_S5_i(bvalid_s5),
	.BREADY_S5_o(bready_s5),
	// READ
	.ARID_S5_o(arid_s5),
	.ARADDR_S5_o(araddr_s5),
	.ARLEN_S5_o(arlen_s5),
	.ARSIZE_S5_o(arsize_s5),
	.ARBURST_S5_o(arburst_s5),
	.ARVALID_S5_o(arvalid_s5),
	.ARREADY_S5_i(arready_s5),
	.RID_S5_i(rid_s5),
	.RDATA_S5_i(rdata_s5),
	.RRESP_S5_i(rresp_s5),
	.RLAST_S5_i(rlast_s5),
	.RVALID_S5_i(rvalid_s5),
	.RREADY_S5_o(rready_s5),

	// WRITE
	   .AWID_S6_o(   awid_s6),
	 .AWADDR_S6_o( awaddr_s6),
	  .AWLEN_S6_o(  awlen_s6),
	 .AWSIZE_S6_o( awsize_s6),
	.AWBURST_S6_o(awburst_s6),
	.AWVALID_S6_o(awvalid_s6),
	.AWREADY_S6_i(awready_s6),
	  .WDATA_S6_o(  wdata_s6),
	  .WSTRB_S6_o(  wstrb_s6),
	  .WLAST_S6_o(  wlast_s6),
	 .WVALID_S6_o( wvalid_s6),
	 .WREADY_S6_i( wready_s6),
	    .BID_S6_i(    bid_s6),
	  .BRESP_S6_i(  bresp_s6),
	 .BVALID_S6_i( bvalid_s6),
	 .BREADY_S6_o( bready_s6),
	// READ
	   .ARID_S6_o(   arid_s6),
	 .ARADDR_S6_o( araddr_s6),
	  .ARLEN_S6_o(  arlen_s6),
	 .ARSIZE_S6_o( arsize_s6),
	.ARBURST_S6_o(arburst_s6),
	.ARVALID_S6_o(arvalid_s6),
	.ARREADY_S6_i(arready_s6),
	    .RID_S6_i(rid_s6),
	.RDATA_S6_i(rdata_s6),
	.RRESP_S6_i(rresp_s6),
	.RLAST_S6_i(rlast_s6),
	.RVALID_S6_i(rvalid_s6),
	.RREADY_S6_o(rready_s6)
);


/*===========================CPU(Master0, Master1)=================*/
CPU_wrapper cpu_instance (
    .clk(cpu_clk),
    .rst(cpu_rst),

    .ARID_M0(arid_m0),
    .ARADDR_M0(araddr_m0),
    .ARLEN_M0(arlen_m0),
    .ARSIZE_M0(arsize_m0),
    .ARBURST_M0(arburst_m0),
    .ARVALID_M0(arvalid_m0),
    .ARREADY_M0(arready_m0),
    
    .RID_M0(rid_m0),
    .RDATA_M0(rdata_m0),
    .RLAST_M0(rlast_m0),
    .RVALID_M0(rvalid_m0),
    .RRESP_M0(rresp_m0),
    .RREADY_M0(rready_m0),

    .AWID_M1(awid_m1),
    .AWADDR_M1(awaddr_m1),
    .AWLEN_M1(awlen_m1),
    .AWSIZE_M1(awsize_m1),
    .AWBURST_M1(awburst_m1),
    .AWVALID_M1(awvalid_m1),
    .AWREADY_M1(awready_m1),

    .WDATA_M1(wdata_m1),
    .WSTRB_M1(wstrb_m1),
    .WLAST_M1(wlast_m1),
    .WVALID_M1(wvalid_m1),
    .WREADY_M1(wready_m1),

    .BID_M1(bid_m1),
    .BRESP_M1(bresp_m1),
    .BVALID_M1(bvalid_m1),
    .BREADY_M1(bready_m1),

    .ARID_M1(arid_m1),
    .ARADDR_M1(araddr_m1),
    .ARLEN_M1(arlen_m1),
    .ARSIZE_M1(arsize_m1),
    .ARBURST_M1(arburst_m1),
    .ARVALID_M1(arvalid_m1),
    .ARREADY_M1(arready_m1),

    .RID_M1(rid_m1),
    .RDATA_M1(rdata_m1),
    .RLAST_M1(rlast_m1),
    .RVALID_M1(rvalid_m1),
    .RRESP_M1(rresp_m1),
    .RREADY_M1(rready_m1),
	
	.interrupt(DMA_interrupt || intr_epu),
	.timer_interrupt(WTO)
	);

/*===========================ROM(Slave0)===========================*/
ROM_wrapper ROM_wrapper(
	.clk(rom_clk),
	.rst(rom_rst),
	
	.ARID_S(arid_s0),
	.ARADDR_S(araddr_s0),
	.ARLEN_S(arlen_s0),
	.ARSIZE_S(arsize_s0),
	.ARBURST_S(arburst_s0),
	.ARVALID_S(arvalid_s0),
	.ARREADY_S(arready_s0),
	
	.RID_S(rid_s0),
	.RDATA_S(rdata_s0),
	.RLAST_S(rlast_s0),
	.RRESP_S(rresp_s0),
	.RVALID_S(rvalid_s0),
	.RREADY_S(rready_s0)
	// ROM contents are loaded from rom0.hex~rom3.hex inside ROM_wrapper.
);

/*===========================IM1(Slave1)===========================*/
SRAM_wrapper IM1(
	.clk(cpu_clk),
	.rst(cpu_rst),
		
	.AWID_S(awid_s1),
	.AWADDR_S(awaddr_s1),
	.AWLEN_S(awlen_s1),
	.AWSIZE_S(awsize_s1),
	.AWBURST_S(awburst_s1),
	.AWVALID_S(awvalid_s1),
	.AWREADY_S(awready_s1),
		
	.WDATA_S(wdata_s1),
	.WSTRB_S(wstrb_s1),
	.WLAST_S(wlast_s1),
	.WVALID_S(wvalid_s1),
	.WREADY_S(wready_s1),
		
	.BID_S(bid_s1),
	.BRESP_S(bresp_s1),
	.BVALID_S(bvalid_s1),
	.BREADY_S(bready_s1),
		
	.ARID_S(arid_s1),
	.ARADDR_S(araddr_s1),
	.ARLEN_S(arlen_s1),
	.ARSIZE_S(arsize_s1),
	.ARBURST_S(arburst_s1),
	.ARVALID_S(arvalid_s1),
	.ARREADY_S(arready_s1),
		
	.RID_S(rid_s1),
	.RDATA_S(rdata_s1),
	.RLAST_S(rlast_s1),
	.RRESP_S(rresp_s1),
	.RVALID_S(rvalid_s1),
	.RREADY_S(rready_s1)
);

/*===========================DM1(Slave2)===========================*/
SRAM_wrapper DM1(
	.clk(cpu_clk),
	.rst(cpu_rst),
		
	.AWID_S(awid_s2),
	.AWADDR_S(awaddr_s2),
	.AWLEN_S(awlen_s2),
	.AWSIZE_S(awsize_s2),
	.AWBURST_S(awburst_s2),
	.AWVALID_S(awvalid_s2),
	.AWREADY_S(awready_s2),
		
	.WDATA_S(wdata_s2),
	.WSTRB_S(wstrb_s2),
	.WLAST_S(wlast_s2),
	.WVALID_S(wvalid_s2),
	.WREADY_S(wready_s2),
		
	.BID_S(bid_s2),
	.BRESP_S(bresp_s2),
	.BVALID_S(bvalid_s2),
	.BREADY_S(bready_s2),
		
	.ARID_S(arid_s2),
	.ARADDR_S(araddr_s2),
	.ARLEN_S(arlen_s2),
	.ARSIZE_S(arsize_s2),
	.ARBURST_S(arburst_s2),
	.ARVALID_S(arvalid_s2),
	.ARREADY_S(arready_s2),
		
	.RID_S(rid_s2),
	.RDATA_S(rdata_s2),
	.RLAST_S(rlast_s2),
	.RRESP_S(rresp_s2),
	.RVALID_S(rvalid_s2),
	.RREADY_S(rready_s2)
);

/*===========================DMA(Master2, Slave3)==================*/

DMA_wrapper DMA_wrapper_inst ( // 建議在模組名稱後加上 "inst" 或 "i"
    .ACLK(cpu_clk),        // <-- 名稱變更
    .ARESETn(cpu_rst),   // 

    // ================= AXI Master (to fabric/memory) =================
    // --- AW ---
    .M_AWID(awid_m2),
    .M_AWADDR(awaddr_m2),
    .M_AWLEN(awlen_m2),
    .M_AWSIZE(awsize_m2),
    .M_AWBURST(awburst_m2),
    .M_AWVALID(awvalid_m2),
    .M_AWREADY(awready_m2),
    // --- W ---
    .M_WDATA(wdata_m2),
    .M_WSTRB(wstrb_m2),
    .M_WLAST(wlast_m2),
    .M_WVALID(wvalid_m2),
    .M_WREADY(wready_m2),
    // --- B ---
    .M_BID(bid_m2),
    .M_BRESP(bresp_m2),
    .M_BVALID(bvalid_m2),
    .M_BREADY(bready_m2),
    // --- AR ---
    .M_ARID(arid_m2),
    .M_ARADDR(araddr_m2),
    .M_ARLEN(arlen_m2),
    .M_ARSIZE(arsize_m2),
    .M_ARBURST(arburst_m2),
    .M_ARVALID(arvalid_m2),
    .M_ARREADY(arready_m2),
    // --- R ---
    .M_RID(rid_m2),
    .M_RDATA(rdata_m2),
    .M_RRESP(rresp_m2),
    .M_RLAST(rlast_m2),
    .M_RVALID(rvalid_m2),
    .M_RREADY(rready_m2),

    // ================= AXI Slave (from CPU) =================
    // --- AW ---
    .S_AWID(awid_s3),
    .S_AWADDR(awaddr_s3),
    .S_AWLEN(awlen_s3),
    .S_AWSIZE(awsize_s3),
    .S_AWBURST(awburst_s3),
    .S_AWVALID(awvalid_s3),
    .S_AWREADY(awready_s3),
    // --- W ---
    .S_WDATA(wdata_s3),
    .S_WSTRB(wstrb_s3),
    .S_WLAST(wlast_s3),
    .S_WVALID(wvalid_s3),
    .S_WREADY(wready_s3),
    // --- B ---
    .S_BID(bid_s3),
    .S_BRESP(bresp_s3),
    .S_BVALID(bvalid_s3),
    .S_BREADY(bready_s3),


    // ================= Interrupt =================
    .DMA_IRQ(DMA_interrupt) // <-- 名稱變更
);

/*
DMA_wrapper DMA_wrapper(
		.clk(clk),
		.rst(rst),

		.awid_m(awid_m2),
		.awaddr_m(awaddr_m2),
		.awlen_m(awlen_m2),
		.awsize_m(awsize_m2),
		.awburst_m(awburst_m2),
		.awvalid_m(awvalid_m2),
		.awready_m(awready_m2),
		
		.wdata_m(wdata_m2),
		.wstrb_m(wstrb_m2),
		.wlast_m(wlast_m2),
		.wvalid_m(wvalid_m2),
		.wready_m(wready_m2),
		
		.bid_m(bid_m2),
		.bresp_m(bresp_m2),
		.bvalid_m(bvalid_m2),
		.bready_m(bready_m2),
		
		.arid_m(arid_m2),
		.araddr_m(araddr_m2),
		.arlen_m(arlen_m2),
		.arsize_m(arsize_m2),
		.arburst_m(arburst_m2),
		.arvalid_m(arvalid_m2),
		.arready_m(arready_m2),
		
		.rid_m(rid_m2),
		.rdata_m(rdata_m2),
		.rlast_m(rlast_m2),
		.rresp_m(rresp_m2),
		.rvalid_m(rvalid_m2),
		.rready_m(rready_m2),
		
		.awid_s(awid_s3),
		.awaddr_s(awaddr_s3),
		.awlen_s(awlen_s3),
		.awsize_s(awsize_s3),
		.awburst_s(awburst_s3),
		.awvalid_s(awvalid_s3),
		.awready_s(awready_s3),
		
		.wdata_s(wdata_s3),
		.wstrb_s(wstrb_s3),
		.wlast_s(wlast_s3),
		.wvalid_s(wvalid_s3),
		.wready_s(wready_s3),
		
		.bid_s(bid_s3),
		.bresp_s(bresp_s3),
		.bvalid_s(bvalid_s3),
		.bready_s(bready_s3),
		
		.DMA_interrupt(DMA_interrupt)
);
*/

/*===========================WDT(Slave4)===========================*/
WDT_wrapper WDT_wrapper(
	.clk(cpu_clk),
	.rst(cpu_rst),
	.clk2(rom_clk),
	.rst2(rom_rst),
		
	.AWID(awid_s4),
	.AWADDR(awaddr_s4),
	.AWLEN(awlen_s4),
	.AWSIZE(awsize_s4),
	.AWBURST(awburst_s4),
	.AWVALID(awvalid_s4),
	.AWREADY(awready_s4),
	
	.WDATA(wdata_s4),
	.WSTRB(wstrb_s4),
	.WLAST(wlast_s4),
	.WVALID(wvalid_s4),
	.WREADY(wready_s4),
		
	.BID(bid_s4),
	.BRESP(bresp_s4),
	.BVALID(bvalid_s4),
	.BREADY(bready_s4),
	
	// .arid(arid_s4),
	// .araddr(araddr_s4),
	// .arlen(arlen_s4),
	// .arsize(arsize_s4),
	// .arburst(arburst_s4),
	// .arvalid(arvalid_s4),
	// .arready(arready_s4),
		
	// .rid(rid_s4),
	// .rdata(rdata_s4),
	// .rlast(rlast_s4),
	// .rresp(rresp_s4),
	// .rvalid(rvalid_s4),
	// .rready(rready_s4),

	//* WDT control signal
	//.WTOCNT(WTOCNT),
	//.WDEN(WDEN),
	//.WDLIVE(WDLIVE),
	.WTO(WTO)
);

/*======================FPGA BUFFER(Slave5)========================*/
AXI_BRAM_Buffer_wrapper FPGA_BUFFER_wrapper(

		.clk(dram_clk),
		.rst(dram_rst),

		.AWID(      awid_s5),
		.AWADDR(  awaddr_s5),
		.AWLEN(    awlen_s5),
		.AWSIZE(  awsize_s5),
		.AWBURST(awburst_s5),
		.AWVALID(awvalid_s5),
		.AWREADY(awready_s5),
		.WDATA ( wdata_s5),
		.WSTRB ( wstrb_s5),
		.WLAST ( wlast_s5),
		.WVALID(wvalid_s5),
		.WREADY(wready_s5),
		.BID   (   bid_s5),
		.BRESP ( bresp_s5),
		.BVALID(bvalid_s5),
		.BREADY(bready_s5),
		.ARID   (   arid_s5),
		.ARADDR ( araddr_s5),
		.ARLEN  (  arlen_s5),
		.ARSIZE ( arsize_s5),
		.ARBURST(arburst_s5),
		.ARVALID(arvalid_s5),
		.ARREADY(arready_s5),
		.RID   (   rid_s5),
		.RDATA ( rdata_s5),
		.RLAST ( rlast_s5),
		.RRESP ( rresp_s5),
		.RVALID(rvalid_s5),
		.RREADY(rready_s5),
		// M1c: UART loader writes BRAM port B; status out to chip_top LEDs.
		.uart_rxd  (uart_rxd),
		.data_ready(data_ready),
		.uart_err  (uart_err),
		.rx_seen   (rx_seen)
);

EPU_Wrapper EPU_Wrapper(
	.ACLK           (cpu_clk),
    .ARESET        (cpu_rst),
    // write address signals
    .AWID           (   awid_s6),
    .AWADDR         ( awaddr_s6),
    .AWLEN          (  awlen_s6),
    .AWSIZE         ( awsize_s6),
    .AWBURST        (awburst_s6),
    .AWVALID        (awvalid_s6),
    .AWREADY        (awready_s6),
    // write data signals
    .WDATA          ( wdata_s6),
    .WSTRB          ( wstrb_s6),
    .WLAST          ( wlast_s6),
    .WVALID         (wvalid_s6),
    .WREADY         (wready_s6),
    // write respond signals
    .BID            (   bid_s6),
    .BRESP          ( bresp_s6),
    .BVALID         (bvalid_s6),
    .BREADY         (bready_s6),
    // read address signals
    .ARID           (   arid_s6),
    .ARADDR         ( araddr_s6),
    .ARLEN          (  arlen_s6),
    .ARSIZE         ( arsize_s6),
    .ARBURST        (arburst_s6),
    .ARVALID        (arvalid_s6),
    .ARREADY        (arready_s6),
    // read data signals
    .RID            (   rid_s6),
    .RDATA          ( rdata_s6),
    .RRESP          ( rresp_s6),
    .RLAST          ( rlast_s6),
    .RVALID         (rvalid_s6),
    .RREADY         (rready_s6),
	///layer done
    .layer_done     (layer_done),
	.epu_interrupt	(intr_epu),
	.result_valid   (result_valid),
	.result_class   (result_class),
	.result_score   (result_score)
);

endmodule