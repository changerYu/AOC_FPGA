// epu_top.sv  --  Phase A board-level top for standalone EPU-first FPGA bring-up
// Target: Digilent Nexys Video (Artix-7 XC7A200T), single 100 MHz clock.
//
// Flow: power-on reset -> (GLB BRAM already $readmemh-initialized with input@0,
// weight@1024) -> after reset, pulse system_start_i (held high) -> EPU runs the
// whole TinyArrhythmiaTransformer internally -> result_valid_o latches the class
// and score. No CPU / ROM / AXI / firmware involved.
//
// Expected golden for the bundled sample (sim/fpga/golden.hex = 25113D67):
//   logits LE = [0x67,0x3D,0x11,0x25,0x00] -> argmax class 0 (N), score 0x67=103.
//
// LED display is multiplexed by sw[1:0] so the single-sample result is fully
// observable with only board LEDs/switches:
//   sw=00 : result_score   (expect 0110_0111 = 0x67 = 103)
//   sw=01 : {valid, 0000, class[2:0]}  (LED7=valid, LED2:0=class, expect class=000)
//   sw=10 : {0000, layer_done, done, busy, valid}  status flags
//   sw=11 : heartbeat counter  (proves clock + bitstream are alive)

`timescale 1ns/1ps

module epu_top (
    input  wire        clk100,    // 100 MHz system clock (pin R4)
    input  wire        rst_btn,   // active-high reset button
    input  wire [1:0]  sw,        // LED display select
    output wire [7:0]  led
);

    // ---------------------------------------------------------------------
    // Reset: 2-FF synchronize the button, plus a power-on hold counter.
    // Produces active-low rst_n, deasserted synchronously after the design
    // has had time to settle post-configuration.
    // ---------------------------------------------------------------------
    reg  [1:0] btn_sync = 2'b00;
    always @(posedge clk100) btn_sync <= {btn_sync[0], rst_btn};
    wire rst_req = btn_sync[1];

    reg  [7:0] por_cnt = 8'd0;
    reg        rst_n   = 1'b0;
    always @(posedge clk100) begin
        if (rst_req) begin
            por_cnt <= 8'd0;
            rst_n   <= 1'b0;
        end
        else if (!(&por_cnt)) begin
            por_cnt <= por_cnt + 8'd1;
            rst_n   <= 1'b0;
        end
        else begin
            rst_n   <= 1'b1;
        end
    end

    // ---------------------------------------------------------------------
    // Start sequence: after reset releases, wait a bit then assert start and
    // hold it. EPU starts compute on the rising edge of system_start_i.
    // ---------------------------------------------------------------------
    reg [7:0] start_dly = 8'd0;
    reg       start_r   = 1'b0;
    always @(posedge clk100) begin
        if (!rst_n) begin
            start_dly <= 8'd0;
            start_r   <= 1'b0;
        end
        else if (!(&start_dly)) begin
            start_dly <= start_dly + 8'd1;
        end
        else begin
            start_r   <= 1'b1;     // single rising edge, then held high
        end
    end

    // ---------------------------------------------------------------------
    // EPU instance. System SRAM port idle (CEB/WEB=1) so the BRAM-initialized
    // GLB contents stay intact; internal controller reads them once started.
    // ---------------------------------------------------------------------
    wire        busy, done, layer_done, result_valid;
    wire [2:0]  result_class;
    wire [7:0]  result_score;

    EPU u_epu (
        .clk             (clk100),
        .rst_n           (rst_n),
        .system_start_i  (start_r),
        .System_SRAM_CEB (1'b1),
        .System_WEB      (1'b1),
        .System_DI       (32'd0),
        .System_A        (14'd0),
        .System_DO       (),
        .busy_o          (busy),
        .done_o          (done),
        .layer_done_o    (layer_done),
        .result_valid_o  (result_valid),
        .result_class_o  (result_class),
        .result_score_o  (result_score)
    );

    // ---------------------------------------------------------------------
    // Heartbeat (clock-alive sanity) and LED multiplexer.
    // ---------------------------------------------------------------------
    reg [25:0] hb = 26'd0;
    always @(posedge clk100) hb <= hb + 26'd1;

    reg [7:0] led_r;
    always @(*) begin
        case (sw)
            2'b00:   led_r = result_score;
            2'b01:   led_r = {result_valid, 4'b0000, result_class};
            2'b10:   led_r = {4'b0000, layer_done, done, busy, result_valid};
            default: led_r = hb[25:18];
        endcase
    end
    assign led = led_r;

endmodule
