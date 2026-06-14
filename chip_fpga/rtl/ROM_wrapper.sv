`include "../include/AXI_define.svh"

// ============================================================================
// ROM_wrapper.sv -- B0 FPGA overlay (full-CHIP bring-up on Nexys Video)
//
// Identical to AOC-vcs-version/hardware/src/ROM_wrapper.sv EXCEPT the four
// ROM*_HEX parameter defaults are ABSOLUTE paths. Vivado synthesis silently
// ignores $readmemh with a bare filename (it cannot find the file -> the BRAM
// initializes to all-zero -> CPU executes zeros -> nothing happens). This was
// already hit once in V1 with glb_init.hex; absolute paths are the fix.
//
// top.sv instantiates ROM_wrapper WITHOUT a parameter override, so the only
// place to inject the path is the default value here. build_chip.tcl adds this
// overlay and EXCLUDES the original src/ROM_wrapper.sv.
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================
module ROM_wrapper #(
  parameter int ROM_ADDR_WORD_BITS = 13,   // 8K words = 32 KiB
  parameter string ROM0_HEX = "D:/AOC-final/chip_fpga/rom0.hex",
  parameter string ROM1_HEX = "D:/AOC-final/chip_fpga/rom1.hex",
  parameter string ROM2_HEX = "D:/AOC-final/chip_fpga/rom2.hex",
  parameter string ROM3_HEX = "D:/AOC-final/chip_fpga/rom3.hex"
)(
  input  logic                      clk,
  input  logic                      rst,

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

  localparam int ROM_DEPTH = (1 << ROM_ADDR_WORD_BITS);

  typedef enum logic { R_IDLE, R_ACTIVE } r_state_e;

  (* rom_style = "block" *) logic [7:0] rom0 [0:ROM_DEPTH-1];
  (* rom_style = "block" *) logic [7:0] rom1 [0:ROM_DEPTH-1];
  (* rom_style = "block" *) logic [7:0] rom2 [0:ROM_DEPTH-1];
  (* rom_style = "block" *) logic [7:0] rom3 [0:ROM_DEPTH-1];

  r_state_e                  r_state, r_next_state;
  logic [`AXI_IDS_BITS-1:0]  r_id_q;
  logic [ROM_ADDR_WORD_BITS-1:0] r_word_q;
  logic [3:0]                r_len_q, r_beat_cnt_q;
  logic                      rvalid_q;
  logic [`AXI_DATA_BITS-1:0] rdata_q;

  logic r_last_beat;
  logic r_hold, rvalid_out;
  logic read_this_cycle, DO_is_valid;
  logic AR_handshake_first, still_need_to_read;
  logic [ROM_ADDR_WORD_BITS-1:0] read_address;
  logic bypass;
  logic [31:0] rom_do;

  initial begin
    $readmemh(ROM0_HEX, rom0);
    $readmemh(ROM1_HEX, rom1);
    $readmemh(ROM2_HEX, rom2);
    $readmemh(ROM3_HEX, rom3);
  end

  always_comb begin
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
      read_address = ARADDR_S[ROM_ADDR_WORD_BITS+1:2];
    else if (still_need_to_read)
      read_address = r_word_q + {{(ROM_ADDR_WORD_BITS-1){1'b0}}, 1'b1};
    else
      read_address = '0;
  end

  always_ff @(posedge clk) begin
    if (read_this_cycle) begin
      rom_do <= {rom3[read_address], rom2[read_address], rom1[read_address], rom0[read_address]};
    end
  end

  always_comb begin
    r_next_state = r_state;
    ARREADY_S    = 1'b0;

    unique case (r_state)
      R_IDLE: begin
        if (ARVALID_S) begin
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

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      r_state       <= R_IDLE;
      r_id_q        <= '0;
      r_word_q      <= '0;
      r_len_q       <= '0;
      r_beat_cnt_q  <= '0;
      rvalid_q      <= 1'b0;
      rdata_q       <= '0;
      DO_is_valid   <= 1'b0;
    end else begin
      r_state      <= r_next_state;
      DO_is_valid <= read_this_cycle;

      if (ARVALID_S && ARREADY_S) begin
        r_id_q        <= ARID_S;
        r_word_q      <= ARADDR_S[ROM_ADDR_WORD_BITS+1:2];
        r_len_q       <= ARLEN_S;
        r_beat_cnt_q  <= '0;
      end

      if (DO_is_valid) begin
        rdata_q <= rom_do;
      end

      rvalid_q <= (rvalid_q & ~(rvalid_out & RREADY_S)) | (DO_is_valid & ~RREADY_S);

      if (rvalid_out & RREADY_S) begin
        r_beat_cnt_q <= r_beat_cnt_q + 4'd1;
        if (!r_last_beat) r_word_q <= r_word_q + {{(ROM_ADDR_WORD_BITS-1){1'b0}}, 1'b1};
      end
    end
  end

  assign RDATA_S  = bypass ? rom_do : rdata_q;
  assign RVALID_S = rvalid_out;
  assign RLAST_S  = bypass ? (r_beat_cnt_q == r_len_q) : (rvalid_q && r_last_beat);
  assign RID_S    = r_id_q;
  assign RRESP_S  = 2'b00;

endmodule
