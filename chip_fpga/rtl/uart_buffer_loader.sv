// ============================================================================
// uart_buffer_loader.sv -- M1c: receive a framed 544-word ECG input over UART
// and write it into the FPGA buffer BRAM via its port B.
//
// Adapted from the B1 frame parser (epu_fpga/rtl/epu_uart_top.sv): same UART
// (8N1) + frame format, but the loaded words go to a BRAM write port instead of
// the EPU System SRAM port, and there is NO start button -- classification is
// triggered separately by a CPU reset (the SoC then DMAs the buffer -> GLB).
//
// UART frame:  0xAA 0x55 | 2176 payload bytes (544 words, 4 bytes LE each)
//              | 1 XOR-checksum byte (over the 2176 payload bytes)
//
// Clock = the FPGA buffer domain (50 MHz in B0/M1 chip_top). uart_rxd is async
// and double-flopped inside uart_rx. After a full valid frame data_ready=1;
// a bad checksum sets uart_err. Data is written into BRAM as it arrives, so on
// data_ready the buffer already holds the new sample -> press CPU reset to run.
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================

`timescale 1ns/1ps

module uart_buffer_loader #(
    parameter int CLK_HZ = 50_000_000,
    parameter int BAUD   = 115_200
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        uart_rxd,

    // BRAM port-B write interface (to SRAM_wrapper_buf)
    output logic        pb_we,
    output logic [13:0] pb_addr,
    output logic [31:0] pb_wdata,

    // status (for LEDs / debug)
    output logic        data_ready,   // a full valid frame has been stored
    output logic        uart_err,     // checksum mismatch on last frame
    output logic        rx_seen       // at least one UART byte ever received
);
    localparam int NWORDS = 544;
    localparam int NBYTES = NWORDS * 4;        // 2176
    localparam logic [7:0] HDR0 = 8'hAA;
    localparam logic [7:0] HDR1 = 8'h55;

    // ---------------- UART receiver ----------------
    logic [7:0] rx_data;
    logic       rx_valid;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n), .rxd(uart_rxd),
        .data(rx_data), .valid(rx_valid)
    );

    // ---------------- frame / loader FSM ----------------
    typedef enum logic [2:0] {
        F_SYNC0, F_SYNC1, F_PAYLOAD, F_CKSUM, F_READY, F_ERR
    } fstate_e;
    fstate_e fst;

    logic [31:0] word_sr;
    logic [1:0]  bidx;         // byte index within word (0..3)
    logic [9:0]  word_cnt;     // 0..543
    logic [11:0] byte_cnt;     // 0..2175
    logic [7:0]  csum;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fst        <= F_SYNC0;
            word_sr    <= 32'd0;
            bidx       <= 2'd0;
            word_cnt   <= 10'd0;
            byte_cnt   <= 12'd0;
            csum       <= 8'd0;
            data_ready <= 1'b0;
            uart_err   <= 1'b0;
            rx_seen    <= 1'b0;
            pb_we      <= 1'b0;
            pb_addr    <= 14'd0;
            pb_wdata   <= 32'd0;
        end
        else begin
            pb_we <= 1'b0;                      // default: no BRAM write
            if (rx_valid) rx_seen <= 1'b1;

            case (fst)
                F_SYNC0: begin
                    if (rx_valid && rx_data == HDR0) fst <= F_SYNC1;
                end
                F_SYNC1: begin
                    if (rx_valid) begin
                        if      (rx_data == HDR1) begin
                            fst        <= F_PAYLOAD;
                            bidx       <= 2'd0;
                            word_cnt   <= 10'd0;
                            byte_cnt   <= 12'd0;
                            csum       <= 8'd0;
                            data_ready <= 1'b0;
                            uart_err   <= 1'b0;
                        end
                        else if (rx_data == HDR0) fst <= F_SYNC1; // re-sync
                        else                       fst <= F_SYNC0;
                    end
                end
                F_PAYLOAD: begin
                    if (rx_valid) begin
                        csum    <= csum ^ rx_data;
                        word_sr <= {rx_data, word_sr[31:8]};   // little-endian
                        if (bidx == 2'd3) begin
                            // 4th byte -> word complete; write it to BRAM port B.
                            pb_we    <= 1'b1;
                            pb_addr  <= {4'b0000, word_cnt};
                            pb_wdata <= {rx_data, word_sr[31:8]};
                            word_cnt <= word_cnt + 10'd1;
                            bidx     <= 2'd0;
                        end
                        else bidx <= bidx + 2'd1;

                        if (byte_cnt == NBYTES-1) fst <= F_CKSUM;
                        else                      byte_cnt <= byte_cnt + 12'd1;
                    end
                end
                F_CKSUM: begin
                    if (rx_valid) begin
                        if (rx_data == csum) begin
                            data_ready <= 1'b1;
                            fst        <= F_READY;
                        end
                        else begin
                            uart_err <= 1'b1;
                            fst      <= F_ERR;
                        end
                    end
                end
                F_READY: begin
                    // Buffer holds a valid sample. A new frame (re-header) can
                    // overwrite it; otherwise wait for the user to CPU-reset.
                    if (rx_valid && rx_data == HDR0) fst <= F_SYNC1;
                end
                F_ERR: begin
                    if (rx_valid && rx_data == HDR0) begin
                        uart_err <= 1'b0;
                        fst      <= F_SYNC1;
                    end
                end
                default: fst <= F_SYNC0;
            endcase
        end
    end
endmodule
