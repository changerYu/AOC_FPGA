`include "../include/AXI_define.svh"

// ============================================================================
// SRAM_wrapper_buf.sv -- B0/M1b FPGA buffer SRAM (AXI slave S5 data store)
//
// Copy of src/CPU/SRAM_wrapper.sv (the shared inferred-BRAM AXI SRAM) with ONE
// addition: the BRAM is pre-initialized from buf_init.hex via $readmemh so the
// FPGA buffer powers up holding the ECG input sample. This decouples the buffer
// contents from the CPU boot path: boot.c no longer DMAs the input into the
// buffer; main.c just DMAs whatever is in the buffer -> GLB -> EPU.
//
// IMPORTANT (design constraint): the buffer data MUST live in BRAM, never in
// registers. BRAM array contents survive a reset (reset clears only the control
// FSM/regs, not mem[]), which is exactly what makes "CPU reset = re-classify the
// current buffer" work, and what will let UART-written data survive a reset in
// M1c. M1c adds a SECOND write port (true dual-port BRAM) for the UART loader,
// writing into this same mem[] array -- the data stays in BRAM.
//
// Only the S5 buffer instance uses this variant; IM1/DM1 keep the original
// uninitialized SRAM_wrapper untouched.
//
// $readmemh uses an ABSOLUTE path (Vivado silently ignores a bare filename in
// synthesis -> BRAM all-zero; hit before in V1/B0 with rom/glb hex).
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================
module SRAM_wrapper_buf #(
  parameter string INIT_HEX = "D:/AOC-final/chip_fpga/buf_init.hex"
)(
  input  logic                      clk,
  input  logic                      rst,

  // WRITE ADDRESS
  input  logic [`AXI_IDS_BITS-1:0]  AWID_S,
  input  logic [`AXI_ADDR_BITS-1:0] AWADDR_S,
  input  logic [`AXI_LEN_BITS-1:0]  AWLEN_S,
  input  logic [`AXI_SIZE_BITS-1:0] AWSIZE_S,
  input  logic [1:0]                AWBURST_S,
  input  logic                      AWVALID_S,
  output logic                      AWREADY_S,

  // WRITE DATA
  input  logic [`AXI_DATA_BITS-1:0] WDATA_S,
  input  logic [`AXI_STRB_BITS-1:0] WSTRB_S,
  input  logic                      WLAST_S,
  input  logic                      WVALID_S,
  output logic                      WREADY_S,

  // WRITE RESP
  output logic [`AXI_IDS_BITS-1:0]  BID_S,
  output logic [1:0]                BRESP_S,
  output logic                      BVALID_S,
  input  logic                      BREADY_S,

  // READ ADDRESS
  input  logic [`AXI_IDS_BITS-1:0]  ARID_S,
  input  logic [`AXI_ADDR_BITS-1:0] ARADDR_S,
  input  logic [`AXI_LEN_BITS-1:0]  ARLEN_S,
  input  logic [`AXI_SIZE_BITS-1:0] ARSIZE_S,
  input  logic [1:0]                ARBURST_S,
  input  logic                      ARVALID_S,
  output logic                      ARREADY_S,

  // READ DATA
  output logic [`AXI_IDS_BITS-1:0]  RID_S,
  output logic [`AXI_DATA_BITS-1:0] RDATA_S,
  output logic [1:0]                RRESP_S,
  output logic                      RLAST_S,
  output logic                      RVALID_S,
  input  logic                      RREADY_S
);

  localparam int ADDR_WORD_BITS = 14;
  localparam int DEPTH          = (1 << ADDR_WORD_BITS);

  typedef enum logic       { R_IDLE, R_ACTIVE } r_state_e;
  typedef enum logic [1:0] { W_IDLE, W_W, W_B } w_state_e;

  (* ram_style = "block" *) logic [31:0] mem [0:DEPTH-1];

  r_state_e                  r_state, r_next_state;
  logic [`AXI_IDS_BITS-1:0]  r_id_q;
  logic [ADDR_WORD_BITS-1:0] r_word_q;
  logic [3:0]                r_len_q, r_beat_cnt_q;
  logic                      rvalid_q;
  logic [`AXI_DATA_BITS-1:0] rdata_q;

  w_state_e                  w_state, w_next_state;
  logic [`AXI_IDS_BITS-1:0]  w_id_q;
  logic [ADDR_WORD_BITS-1:0] w_word_q;

  logic r_busy, w_busy, r_last_beat;
  logic r_hold, rvalid_out;
  logic read_this_cycle, DO_is_valid;
  logic AR_handshake_first, still_need_to_read;
  logic [ADDR_WORD_BITS-1:0] read_address;
  logic bypass;
  logic [31:0] DO;

  // Pre-load the buffer BRAM with the input sample. Absolute path required.
  initial begin
    $readmemh(INIT_HEX, mem);
  end

  always_comb begin
    r_busy      = (r_state != R_IDLE);
    w_busy      = (w_state != W_IDLE);
    r_last_beat = (r_beat_cnt_q == r_len_q);
    rvalid_out  = rvalid_q | DO_is_valid;
    r_hold      = rvalid_out && !RREADY_S;
  end

  assign bypass = DO_is_valid & ~rvalid_q;

  always_comb begin
    AR_handshake_first  = (r_state == R_IDLE)   && (ARVALID_S && ARREADY_S);
    still_need_to_read  = (r_state == R_ACTIVE) && (rvalid_out & RREADY_S) && !r_last_beat;
    read_this_cycle     = AR_handshake_first || still_need_to_read;

    if (AR_handshake_first)
      read_address = ARADDR_S[ADDR_WORD_BITS+1:2];
    else if (still_need_to_read)
      read_address = r_word_q + {{(ADDR_WORD_BITS-1){1'b0}}, 1'b1};
    else
      read_address = '0;
  end

  // Single-port synchronous BRAM: write has priority over read. Active-low byte
  // strobes (ASIC BWEB convention): WSTRB bit 0 writes that byte.
  always @(posedge clk) begin
    if (WVALID_S && WREADY_S) begin
      for (int b = 0; b < 4; b++) begin
        if (!WSTRB_S[b]) begin
          mem[w_word_q][8*b +: 8] <= WDATA_S[8*b +: 8];
        end
      end
    end
    else if (read_this_cycle) begin
      DO <= mem[read_address];
    end
  end

  always_comb begin
    r_next_state = r_state;
    ARREADY_S    = 1'b0;

    unique case (r_state)
      R_IDLE: begin
        if (ARVALID_S && !w_busy) begin
          ARREADY_S    = 1'b1;
          r_next_state = R_ACTIVE;
        end
      end
      R_ACTIVE: begin
        r_next_state = ((rvalid_out & RREADY_S) && r_last_beat) ? R_IDLE : R_ACTIVE;
      end
      default: r_next_state = R_IDLE;
    endcase
  end

  always_comb begin
    w_next_state = w_state;
    AWREADY_S = 1'b0;
    WREADY_S  = 1'b0;
    BVALID_S  = 1'b0;
    BID_S     = w_id_q;
    BRESP_S   = 2'b00;

    unique case (w_state)
      W_IDLE: begin
        if (AWVALID_S && !r_busy && !ARVALID_S) begin
          AWREADY_S    = 1'b1;
          w_next_state = W_W;
        end
      end
      W_W: begin
        if (!r_hold && !AR_handshake_first) begin
          WREADY_S = 1'b1;
          if (WVALID_S) w_next_state = WLAST_S ? W_B : W_W;
        end
      end
      W_B: begin
        BVALID_S = 1'b1;
        if (BREADY_S) w_next_state = W_IDLE;
      end
      default: w_next_state = W_IDLE;
    endcase
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      r_state       <= R_IDLE;
      r_id_q        <= '0;
      r_word_q      <= '0;
      r_len_q       <= '0;
      r_beat_cnt_q  <= '0;
      rvalid_q      <= 1'b0;
      rdata_q       <= '0;
      DO_is_valid   <= 1'b0;
      w_state       <= W_IDLE;
      w_id_q        <= '0;
      w_word_q      <= '0;
    end else begin
      r_state      <= r_next_state;
      DO_is_valid <= read_this_cycle;

      if (ARVALID_S && ARREADY_S) begin
        r_id_q        <= ARID_S;
        r_word_q      <= ARADDR_S[ADDR_WORD_BITS+1:2];
        r_len_q       <= ARLEN_S;
        r_beat_cnt_q  <= '0;
      end

      if (DO_is_valid) begin
        rdata_q <= DO;
      end

      rvalid_q <= (rvalid_q & ~(rvalid_out & RREADY_S)) | (DO_is_valid & ~RREADY_S);

      if (rvalid_out & RREADY_S) begin
        r_beat_cnt_q <= r_beat_cnt_q + 4'd1;
        if (!r_last_beat) r_word_q <= r_word_q + {{(ADDR_WORD_BITS-1){1'b0}}, 1'b1};
      end

      w_state <= w_next_state;

      if (AWVALID_S && AWREADY_S) begin
        w_id_q   <= AWID_S;
        w_word_q <= AWADDR_S[ADDR_WORD_BITS+1:2];
      end
      if ((WVALID_S && WREADY_S) && !WLAST_S) begin
        w_word_q <= w_word_q + {{(ADDR_WORD_BITS-1){1'b0}}, 1'b1};
      end
    end
  end

  assign RDATA_S  = bypass ? DO : rdata_q;
  assign RVALID_S = rvalid_out;
  assign RLAST_S  = bypass ? (r_beat_cnt_q == r_len_q) : (rvalid_q && r_last_beat);
  assign RID_S    = r_id_q;
  assign RRESP_S  = 2'b00;

endmodule
