// ============================================================================
// M2A overlay of EPU_Wrapper.sv (FPGA branch).
//
// Adds a second, CPU-clearable "frame ready" interrupt so the CPU can run a
// continuous classify loop without a button or reset. The UART buffer loader
// raises data_ready when a full 544-word frame has landed in the buffer BRAM;
// that crosses into this (cpu_clk) domain as data_ready_cpu (already 2FF-synced
// in top.sv). A rising edge latches frame_interrupt (mirrors the existing EPU
// interrupt FSM exactly), held until the CPU clears it by writing the EPU reg
// region sub-address 0x04 (0x0006_0004). frame_interrupt is OR'd into the CPU
// external interrupt line in top.sv. The EPU compute path itself is unchanged.
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================
module EPU_Wrapper(
    input  logic                      ACLK,
    input  logic                      ARESET, // Active High

    // WRITE ADDRESS
    input  logic [`AXI_IDS_BITS-1:0]  AWID,
    input  logic [`AXI_ADDR_BITS-1:0] AWADDR,
    input  logic [`AXI_LEN_BITS-1:0]  AWLEN,
    input  logic [`AXI_SIZE_BITS-1:0] AWSIZE,
    input  logic [1:0]                AWBURST,
    input  logic                      AWVALID,
    output logic                      AWREADY,
    // WRITE DATA
    input  logic [`AXI_DATA_BITS-1:0] WDATA,
    input  logic [`AXI_STRB_BITS-1:0] WSTRB,
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,
    // WRITE RESPONSE
    output logic [`AXI_IDS_BITS-1:0]  BID,
    output logic [1:0]                BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,
    // READ ADDRESS
    input  logic [`AXI_IDS_BITS-1:0]  ARID,
    input  logic [`AXI_ADDR_BITS-1:0] ARADDR,
    input  logic [`AXI_LEN_BITS-1:0]  ARLEN,
    input  logic [`AXI_SIZE_BITS-1:0] ARSIZE,
    input  logic [1:0]                ARBURST,
    input  logic                      ARVALID,
    output logic                      ARREADY,
    // READ DATA
    output logic [`AXI_IDS_BITS-1:0]  RID,
    output logic [`AXI_DATA_BITS-1:0] RDATA,
    output logic [1:0]                RRESP,
    output logic                      RLAST,
    output logic                      RVALID,
    input  logic                      RREADY,
    
    // EPU specific
    output logic                      layer_done,
    output logic                      epu_interrupt,

    // M2A: continuous-loop "frame ready" interrupt (UART frame in buffer BRAM).
    input  logic                      data_ready_cpu,  // 2FF-synced data_ready
    output logic                      frame_interrupt, // level, CPU-clearable

    // FPGA result output. Latched by EPU when final logits are written.
    output logic                      result_valid,
    output logic [2:0]                result_class,
    output logic [7:0]                result_score
);

    // ---------------- Types ----------------
    typedef enum logic { R_IDLE, R_ACTIVE } r_state_e;
    typedef enum logic [1:0] { W_IDLE, W_AW, W_W, W_B } w_state_e;
    // Interrupt FSM Types
    typedef enum logic [1:0] { intrIDLE, intrDO, intrINTERRUPT } intr_state_t;

    // ---------------- Read regs ----------------
    r_state_e                   r_state, r_next_state;
    logic [`AXI_IDS_BITS-1:0]   r_id_q;
    logic [31:0]                r_addr_q; // Full address
    logic [3:0]                 r_len_q, r_beat_cnt_q;
    logic                       rvalid_q;
    logic [`AXI_DATA_BITS-1:0]  rdata_q;

    // ---------------- Write regs ----------------
    w_state_e                   w_state, w_next_state;
    logic [`AXI_IDS_BITS-1:0]   w_id_q;
    logic [31:0]                w_addr_q; // Full address

    // ---------------- Handshake / flags ----------------
    logic r_busy, w_busy, r_last_beat;
    logic r_hold, rvalid_out;

    logic                       read_this_cycle, DO_is_valid;
    logic                       AR_handshake_first, still_need_to_read;
    logic [31:0]                read_address_full;
    logic                       bypass;

    // ---------------- SRAM & EPU Interconnect ----------------
    logic [31:0] DO_0;
    logic [31:0] DI;
    logic [13:0] A;
    
    // Chip Enables
    logic Image0_CEB;
    logic WEB;

    // Register Write Logic
    logic is_reg_write;
    
    // Interrupt Logic
    intr_state_t intrstate, next_intrstate;
    logic EPU_start, EPU_done, cpu_response;



    always_comb begin
        r_busy      = (r_state != R_IDLE);
        w_busy      = (w_state != W_IDLE);
        r_last_beat = (r_beat_cnt_q == r_len_q);


        rvalid_out = rvalid_q | DO_is_valid;
        r_hold     = rvalid_out && !RREADY;
    end

    assign bypass = DO_is_valid & ~rvalid_q;

    // ---------------- Early-issue for Read ----------------
    always_comb begin
        AR_handshake_first  = (r_state == R_IDLE)   && (ARVALID && ARREADY);
        still_need_to_read  = (r_state == R_ACTIVE) && (rvalid_out & RREADY) && !r_last_beat;
        read_this_cycle     = AR_handshake_first || still_need_to_read;
        
        if(AR_handshake_first)
            read_address_full = ARADDR;
        else if(still_need_to_read)
            read_address_full = r_addr_q + 32'd4; // Burst Increment
        else
            read_address_full = 32'd0;
    end

    // ---------------- Address Decoding ----------------
    logic [31:0] sram_access_addr;
    logic        sram_write_en;
    logic        sram_read_en;

    always_comb begin
        // Default
        Image0_CEB = 1'b1;
        WEB        = 1'b1; // Read mode by default
        DI         = 32'd0;
        A          = 14'd0;
        sram_access_addr = 32'd0;
        sram_write_en = 1'b0;
        sram_read_en  = 1'b0;

        // --- Write Access ---
        if (WVALID && WREADY) begin
            sram_access_addr = w_addr_q;
            DI = WDATA;
            // 判斷是否為暫存器地址 (0x60000)
            if (w_addr_q[18:16] == 3'b110) begin 
                sram_write_en = 1'b0;
            end else begin
                sram_write_en = 1'b1;
                WEB = 1'b0; // Active Low Write
                Image0_CEB = 1'b0;
            end
        end
        // --- Read Access ---
        else if (read_this_cycle) begin
            sram_access_addr = read_address_full;
            sram_read_en = 1'b1;
            WEB = 1'b1; // Read
            Image0_CEB = 1'b0;
        end


        if (sram_write_en || sram_read_en) begin
            A = sram_access_addr[15:2];
            Image0_CEB = 1'b0;
        end
    end


    assign is_reg_write = (WVALID && WREADY) && (w_addr_q[18:16] == 3'b110);

    // ---------------- Read FSM ----------------
    always_comb begin
        r_next_state = r_state;
        ARREADY      = 1'b0;

        unique case (r_state)
            R_IDLE: begin
                if (ARVALID && !w_busy) begin
                    ARREADY      = 1'b1;
                    r_next_state = R_ACTIVE;
                end
            end
            R_ACTIVE: begin
                if ((rvalid_out & RREADY) && r_last_beat) 
                    r_next_state = R_IDLE;
                else 
                    r_next_state = R_ACTIVE;
            end
            default: r_next_state = R_IDLE;
        endcase
    end

    // ---------------- Write FSM ----------------
    always_comb begin
        w_next_state = w_state;

        AWREADY = 1'b0;
        WREADY  = 1'b0;
        BVALID  = 1'b0;
        BID     = w_id_q;
        BRESP   = 2'b00; // OKAY

        unique case (w_state)
            W_IDLE: begin
                if (AWVALID && !r_busy && !ARVALID) begin
                    AWREADY      = 1'b1;
                    w_next_state = W_W;
                end
            end
            W_W: begin
                if (!r_hold && !AR_handshake_first) begin
                    WREADY = 1'b1;
                    if (WVALID) begin
                        w_next_state = WLAST ? W_B : W_W;
                    end
                end
            end
            W_B: begin
                BVALID = 1'b1;
                if (BREADY) w_next_state = W_IDLE;
            end
            default: w_next_state = W_IDLE;
        endcase
    end

    // ---------------- Sequential Logic ----------------
    always_ff @(posedge ACLK or posedge ARESET) begin
        if (ARESET) begin
            // Read
            r_state      <= R_IDLE;
            r_id_q       <= 8'd0;
            r_addr_q     <= 32'd0;
            r_len_q      <= 4'd0;
            r_beat_cnt_q <= 4'd0;
            rvalid_q     <= 1'b0;
            rdata_q      <= 32'd0;
            DO_is_valid  <= 1'b0;
            // Write
            w_state      <= W_IDLE;
            w_id_q       <= 8'd0;
            w_addr_q     <= 32'd0;
        end else begin
            // --- Read Channel Updates ---
            r_state <= r_next_state;
            DO_is_valid <= read_this_cycle;

            if (ARVALID && ARREADY) begin
                r_id_q       <= ARID;
                r_addr_q     <= ARADDR;
                r_len_q      <= ARLEN;
                r_beat_cnt_q <= 4'd0;
            end

            if (DO_is_valid) begin
                rdata_q <= DO_0;
            end

            rvalid_q <= (rvalid_q & ~(rvalid_out & RREADY)) | (DO_is_valid & ~RREADY);

            if (rvalid_out & RREADY) begin
                r_beat_cnt_q <= r_beat_cnt_q + 4'd1;
                if (!r_last_beat) begin
                    r_addr_q <= r_addr_q + 32'd4;
                end
            end

            // --- Write Channel Updates ---
            w_state <= w_next_state;

            if (AWVALID && AWREADY) begin
                w_id_q   <= AWID;
                w_addr_q <= AWADDR;
            end
            
            if (WVALID && WREADY && !WLAST) begin
                w_addr_q <= w_addr_q + 32'd4;
            end
        end
    end

    // ---------------- Outputs ----------------
    always_comb begin
        if(bypass && r_addr_q[18:16] == 3'b011)begin
            RDATA  = DO_0;
        end
        else begin
            RDATA = rdata_q;
        end
    end
    assign RVALID = rvalid_out;
    assign RLAST  = (bypass ? (r_beat_cnt_q == r_len_q) : (rvalid_q && r_last_beat));
    assign RID    = r_id_q;
    assign RRESP  = 2'b00; // OKAY


    always_ff @(posedge ACLK or posedge ARESET)begin
        if (ARESET) begin
            intrstate <= intrIDLE;
        end
        else begin
            intrstate <= next_intrstate;
        end
    end

    always_comb begin
        // Default
        next_intrstate = intrstate; 
        
        case(intrstate)
            intrIDLE:begin
                if(EPU_start)
                    next_intrstate = intrDO;
                else
                    next_intrstate = intrIDLE;
            end
            intrDO:begin
                if(EPU_done)
                    next_intrstate = intrINTERRUPT;
                else
                    next_intrstate = intrDO;
            end
            intrINTERRUPT:begin
                if(cpu_response)
                    next_intrstate = intrIDLE;
                else
                    next_intrstate = intrINTERRUPT;
            end
        endcase
    end


    assign epu_interrupt = (intrstate == intrINTERRUPT);
    assign cpu_response  = (intrstate == intrINTERRUPT) && !EPU_start;


    // M2A: per-run EPU soft reset. The EPU was verified for a single run; its
    // internal sub-FSMs/counters are not all re-armed when the top controller
    // returns to NONE, so a second run stalls. The CPU pulses this (write reg
    // sub-address 0x08 with bit0=1 then 0) before each EPU_start to fully re-init
    // the EPU. The GLB is BRAM -- its weights/input survive the reset, only the
    // control logic is cleared.
    logic epu_soft_reset;

    always_ff @(posedge ACLK or posedge ARESET) begin
        if(ARESET)begin
            EPU_start            <= 1'b0;
            epu_soft_reset       <= 1'b0;
        end
        else if(is_reg_write) begin
            case(w_addr_q[7:0])
                8'h00: EPU_start            <= WDATA[0];
                8'h08: epu_soft_reset       <= WDATA[0];
                default: ;
            endcase
        end
    end

    // ---------------- M2A: frame-ready interrupt FSM ----------------
    // Mirrors the EPU interrupt FSM: a rising edge of the (already synced)
    // data_ready latches a level interrupt, held until the CPU clears it by
    // writing reg sub-address 0x04 (any data). Clearing inside the trap handler
    // avoids the persistent-level re-trap that a raw data_ready OR would cause.
    logic data_ready_q;
    logic frame_set;        // 1-cycle: a new full frame just arrived
    logic frame_clear;      // 1-cycle: CPU acknowledged / consumed the frame
    logic frame_pending;    // level interrupt latch

    assign frame_set   = data_ready_cpu & ~data_ready_q;
    assign frame_clear = is_reg_write && (w_addr_q[7:0] == 8'h04);

    always_ff @(posedge ACLK or posedge ARESET) begin
        if (ARESET) begin
            data_ready_q  <= 1'b0;
            frame_pending <= 1'b0;
        end
        else begin
            data_ready_q <= data_ready_cpu;
            if (frame_set)        frame_pending <= 1'b1;  // set wins on a tie
            else if (frame_clear) frame_pending <= 1'b0;
        end
    end

    assign frame_interrupt = frame_pending;

    // ---------------- EPU Instantiation ----------------
    EPU epu(
        .clk                    (ACLK                ),
        .rst_n                  (!ARESET & !epu_soft_reset ),  // M2A per-run soft reset
        .system_start_i         (EPU_start           ),
        .System_SRAM_CEB        (Image0_CEB          ),
        .System_WEB             (WEB                 ),
        .System_DI              (DI                  ),
        .System_A               (A                   ),
        .System_DO              (DO_0                ),
        .busy_o                 (                    ),
        .done_o                 (EPU_done            ),
        .layer_done_o           (layer_done          ),
        .result_valid_o         (result_valid        ),
        .result_class_o         (result_class        ),
        .result_score_o         (result_score        )
    );










endmodule