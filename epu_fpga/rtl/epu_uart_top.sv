// epu_uart_top.sv  --  B1 board top: UART -> standalone EPU, button-triggered.
//
// Flow:
//   ESP32/PC --UART(115200 8N1)--> uart_rx --> frame FSM --> writes 544-word
//   input image into the EPU's GLB via the System SRAM port (preload path,
//   active while system_start=0) --> START button pulses system_start_i -->
//   EPU classifies --> result_class/score latched onto LEDs.
//
// Weights stay baked into the GLB via $readmemh (glb_init.hex, words 1024+).
// The GLB's input region (words 0..543) is also baked (the golden sample) as a
// fallback, and is OVERWRITTEN by whatever arrives over UART.
//
// UART frame:  0xAA 0x55 | 2176 payload bytes (544 words, 4 bytes LE each)
//              | 1 XOR-checksum byte (over the 2176 payload bytes)
//
// Buttons (active-high): rst_btn = BTND, start_btn = BTNC.
// LED display select sw[1:0]:
//   00: result_score                      (golden sample -> 0x67 = 103)
//   01: {valid, 0000, class[2:0]}         (golden -> valid + class 000 = N)
//   10: status {rx_seen,run,err,ready,layer_done,done,busy,valid}
//   11: heartbeat

`timescale 1ns/1ps

module epu_uart_top (
    input  wire        clk100,    // 100 MHz (pin R4)
    input  wire        rst_btn,   // BTND, active-high
    input  wire        start_btn, // BTNC, active-high
    input  wire [1:0]  sw,
    input  wire        uart_rxd,  // JA1 (AB22) <- ESP32 GPIO17 (TX)
    output wire        uart_txd,  // JA7 (Y21)  -> ESP32 GPIO16 (RX), idle for now
    output wire [7:0]  led
);
    // ---------------- payload geometry ----------------
    localparam int NWORDS = 544;
    localparam int NBYTES = NWORDS * 4;     // 2176
    localparam logic [7:0] HDR0 = 8'hAA;
    localparam logic [7:0] HDR1 = 8'h55;

    // ---------------- reset (sync + power-on hold) ----------------
    logic [1:0] rstb_q = 2'b00;
    always @(posedge clk100) rstb_q <= {rstb_q[0], rst_btn};
    wire rst_req = rstb_q[1];

    logic [7:0] por = 8'd0;
    logic       rst_n = 1'b0;
    always @(posedge clk100) begin
        if (rst_req)        begin por <= 8'd0;        rst_n <= 1'b0; end
        else if (!(&por))   begin por <= por + 8'd1;  rst_n <= 1'b0; end
        else                       rst_n <= 1'b1;
    end

    // ---------------- start button: sync + simple debounce ----------------
    logic [1:0] sb_q = 2'b00;
    always @(posedge clk100) sb_q <= {sb_q[0], start_btn};
    logic [15:0] sb_cnt = 16'd0;
    logic        start_level = 1'b0;        // debounced level
    always @(posedge clk100) begin
        if (!rst_n) begin sb_cnt <= 16'd0; start_level <= 1'b0; end
        else if (sb_q[1] != start_level) begin
            if (&sb_cnt) begin start_level <= sb_q[1]; sb_cnt <= 16'd0; end
            else sb_cnt <= sb_cnt + 16'd1;
        end
        else sb_cnt <= 16'd0;
    end

    // ---------------- UART receiver ----------------
    logic [7:0] rx_data;
    logic       rx_valid;
    uart_rx #(.CLK_HZ(100_000_000), .BAUD(115_200)) u_rx (
        .clk(clk100), .rst_n(rst_n), .rxd(uart_rxd),
        .data(rx_data), .valid(rx_valid)
    );

    // ---------------- frame / loader FSM ----------------
    typedef enum logic [2:0] {
        F_SYNC0, F_SYNC1, F_PAYLOAD, F_CKSUM, F_READY, F_RUN, F_ERR
    } fstate_e;
    fstate_e fst;

    logic [31:0] word_sr;
    logic [1:0]  bidx;                  // byte index within word (0..3)
    logic [9:0]  word_cnt;              // 0..543
    logic [11:0] byte_cnt;              // 0..2175
    logic [7:0]  csum;
    logic        data_ready, uart_err, rx_seen;

    // EPU System-port drive (GLB preload while system_start=0)
    logic        sys_wr;                // 1-cycle write strobe
    logic [13:0] sys_a;
    logic [31:0] sys_di;
    logic        system_start;

    wire can_start = (fst == F_SYNC0) || (fst == F_READY);

    always_ff @(posedge clk100 or negedge rst_n) begin
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
            sys_wr     <= 1'b0;
            sys_a      <= 14'd0;
            sys_di     <= 32'd0;
            system_start <= 1'b0;
        end
        else begin
            sys_wr <= 1'b0;                     // default: no GLB write
            if (rx_valid) rx_seen <= 1'b1;

            // START button takes priority from a startable state.
            if (can_start && start_level) begin
                fst          <= F_RUN;
                system_start <= 1'b1;
            end

            case (fst)
                F_SYNC0: begin
                    if (rx_valid && rx_data == HDR0) fst <= F_SYNC1;
                end
                F_SYNC1: begin
                    if (rx_valid) begin
                        if      (rx_data == HDR1) begin
                            fst      <= F_PAYLOAD;
                            bidx     <= 2'd0;
                            word_cnt <= 10'd0;
                            byte_cnt <= 12'd0;
                            csum     <= 8'd0;
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
                            // 4th byte -> word complete; write it to GLB.
                            sys_wr   <= 1'b1;
                            sys_a    <= {4'b0000, word_cnt};
                            sys_di   <= {rx_data, word_sr[31:8]};
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
                    // wait for start button (handled by can_start block above)
                end
                F_RUN: begin
                    // system_start held high; EPU runs and latches result.
                end
                F_ERR: begin
                    // stay until reset or a fresh header
                    if (rx_valid && rx_data == HDR0) begin
                        uart_err <= 1'b0;
                        fst      <= F_SYNC1;
                    end
                end
                default: fst <= F_SYNC0;
            endcase
        end
    end

    // ---------------- EPU ----------------
    wire        busy, done, layer_done, result_valid;
    wire [2:0]  result_class;
    wire [7:0]  result_score;

    EPU u_epu (
        .clk             (clk100),
        .rst_n           (rst_n),
        .system_start_i  (system_start),
        .System_SRAM_CEB (sys_wr ? 1'b0 : 1'b1),   // active-low enable
        .System_WEB      (sys_wr ? 1'b0 : 1'b1),   // active-low write
        .System_DI       (sys_di),
        .System_A        (sys_a),
        .System_DO       (),
        .busy_o          (busy),
        .done_o          (done),
        .layer_done_o    (layer_done),
        .result_valid_o  (result_valid),
        .result_class_o  (result_class),
        .result_score_o  (result_score)
    );

    // ---------------- LEDs ----------------
    reg [25:0] hb = 26'd0;
    always @(posedge clk100) hb <= hb + 26'd1;

    reg [7:0] led_r;
    always @(*) begin
        case (sw)
            2'b00:   led_r = result_score;
            2'b01:   led_r = {result_valid, 4'b0000, result_class};
            2'b10:   led_r = {rx_seen, (fst==F_RUN), uart_err, data_ready,
                              layer_done, done, busy, result_valid};
            default: led_r = hb[25:18];
        endcase
    end
    assign led = led_r;

    assign uart_txd = 1'b1;   // UART idle (TX not used yet)

endmodule
