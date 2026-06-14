// ============================================================================
// chip_top.sv -- B0 board-level top for the FULL AOC SoC on Nexys Video
// Target: Digilent Nexys Video (Artix-7 XC7A200T-1).
//
// Wraps CHIP (the FPGA SoC top: RV32 CPU + AXI fabric + DMA + L1/L2 + WDT +
// ROM + FPGA buffer + EPU). After reset the firmware (rom0-3.hex, baked into
// ROM_wrapper BRAM) boots autonomously: boot.c DMAs ROM -> IMEM/DMEM/GLB
// (input@0x30000, weight@0x31000), main.c starts the EPU, EPU classifies, and
// CHIP drives result_valid/class/score. NO start button needed -- the CPU
// drives the whole flow. This top only provides clocks, reset, and an LED view.
//
// -------------------------------------------------------------------------
// Clocking (B0 v2): two clocks from one MMCME2_BASE (primitive, NOT the
// Clocking Wizard IP -- allowed by the project rules):
//   cpu_clk  = 100 MHz  -> CPU + EPU (EPU_Wrapper.ACLK = cpu_clk, proven at
//                          100 MHz standalone in V1) + IM1/DM1 SRAM + DMA
//   axi/rom/dram = 50 MHz -> AXI crossbar core + ROM + WDT + FPGA buffer
// Rationale: the single-100 MHz v1 build failed timing almost entirely inside
// AXI_fifo's async CDC FIFOs (worst paths -2.06 ns, all sys_clk->sys_clk in
// M2_DMA/M1 W_fifo pointers) because all four clocks shared one net, so the
// gray-code CDC crossings were timed as single-cycle same-clock paths. The SoC
// was designed for FOUR asynchronous clocks; the AXI fabric crosses every
// master/slave boundary through async FIFOs. Splitting cpu(100) from the rest
// (50) and declaring them asynchronous (set_clock_groups in the XDC) lets the
// synchronizers do their job and removes those false single-cycle paths. The
// user-approved budget is exactly this: CPU 100 MHz, AXI may drop to 50 MHz.
//
// Reset: all four CHIP resets are ACTIVE-HIGH. Async-assert / sync-deassert,
// gated by MMCM LOCKED. The 50 MHz-domain resets (dram->rom->axi) release
// first; cpu_rst releases last, so the CPU only starts fetching once ROM/
// fabric/buffer are ready (mirrors the SoC testbench release order).
//
// LED display multiplexed by sw[1:0]:
//   sw=00 : result_score  (golden sample expects 0110_0111 = 0x67 = 103)
//   sw=01 : {valid, 0000, class[2:0]}  (LED7=valid, LED2:0=class, expect 000=N)
//   sw=10 : {5'b0, locked, rst_done, result_valid}  bring-up status
//   sw=11 : heartbeat counter (proves clock + bitstream are alive)
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================

`timescale 1ns/1ps

module chip_top (
    input  wire        clk100,    // 100 MHz system clock (pin R4)
    input  wire        rst_btn,   // active-high reset button (BTNC) = trigger+reset
    input  wire [1:0]  sw,        // LED display select
    input  wire        uart_rxd,  // M1c: UART in (JA1/AB22) <- ESP32 GPIO17
    output wire [7:0]  led
);

    // ---------------------------------------------------------------------
    // Clock generation: MMCME2_BASE primitive. 100 MHz in -> 100 + 50 MHz out.
    // VCO = 100 * 10 / 1 = 1000 MHz (within the -1 part 600-1200 MHz range).
    // ---------------------------------------------------------------------
    wire clk_in_buf;
    wire clk100_unbuf, clk50_unbuf, clkfb, clkfb_buf;
    wire clk100_g, clk50_g;
    wire locked;

    IBUF u_clkin_ibuf (.I(clk100), .O(clk_in_buf));

    MMCME2_BASE #(
        .BANDWIDTH         ("OPTIMIZED"),
        .CLKIN1_PERIOD     (10.0),       // 100 MHz
        .DIVCLK_DIVIDE     (1),
        .CLKFBOUT_MULT_F   (10.0),       // VCO = 1000 MHz
        .CLKFBOUT_PHASE    (0.0),
        .CLKOUT0_DIVIDE_F  (10.0),       // 100 MHz (cpu)
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE     (0.0),
        .CLKOUT1_DIVIDE    (20),         // 50 MHz (axi/rom/dram)
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE     (0.0),
        .STARTUP_WAIT      ("FALSE")
    ) u_mmcm (
        .CLKOUT0  (clk100_unbuf),
        .CLKOUT0B (),
        .CLKOUT1  (clk50_unbuf),
        .CLKOUT1B (),
        .CLKOUT2  (), .CLKOUT2B (),
        .CLKOUT3  (), .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUT (clkfb),
        .CLKFBOUTB(),
        .CLKFBIN  (clkfb_buf),
        .CLKIN1   (clk_in_buf),
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG u_bufg_fb  (.I(clkfb),        .O(clkfb_buf));
    BUFG u_bufg_100 (.I(clk100_unbuf), .O(clk100_g));
    BUFG u_bufg_50  (.I(clk50_unbuf),  .O(clk50_g));

    // ---------------------------------------------------------------------
    // Reset button sync (into the 100 MHz domain) + async reset condition.
    // ---------------------------------------------------------------------
    reg  [1:0] btn_sync = 2'b11;
    always @(posedge clk100_g) btn_sync <= {btn_sync[0], rst_btn};
    wire rst_req = btn_sync[1];

    // Async reset assert when MMCM unlocked or button pressed.
    wire arst = ~locked | rst_req;

    // ---------------------------------------------------------------------
    // 50 MHz-domain reset sequencer (dram -> rom -> axi). Async assert,
    // synchronous (counter-gated) deassert.
    // ---------------------------------------------------------------------
    localparam [15:0] T_DRAM = 16'd256;
    localparam [15:0] T_ROM  = 16'd512;
    localparam [15:0] T_AXI  = 16'd768;

    reg [15:0] cnt50 = 16'd0;
    reg        dram_rst = 1'b1;
    reg        rom_rst  = 1'b1;
    reg        axi_rst  = 1'b1;
    always @(posedge clk50_g or posedge arst) begin
        if (arst) begin
            cnt50    <= 16'd0;
            dram_rst <= 1'b1;
            rom_rst  <= 1'b1;
            axi_rst  <= 1'b1;
        end
        else begin
            if (!(&cnt50)) cnt50 <= cnt50 + 16'd1;
            dram_rst <= (cnt50 < T_DRAM);
            rom_rst  <= (cnt50 < T_ROM);
            axi_rst  <= (cnt50 < T_AXI);
        end
    end

    // ---------------------------------------------------------------------
    // 100 MHz-domain reset (cpu) -- releases LAST, after the 50 MHz domain.
    // T_CPU*10ns must exceed T_AXI*20ns so cpu starts after the fabric/ROM.
    // 2048*10 = 20.48us > 768*20 = 15.36us.
    // ---------------------------------------------------------------------
    localparam [15:0] T_CPU = 16'd2048;

    reg [15:0] cnt100 = 16'd0;
    reg        cpu_rst = 1'b1;
    always @(posedge clk100_g or posedge arst) begin
        if (arst) begin
            cnt100  <= 16'd0;
            cpu_rst <= 1'b1;
        end
        else begin
            if (!(&cnt100)) cnt100 <= cnt100 + 16'd1;
            cpu_rst <= (cnt100 < T_CPU);
        end
    end

    wire rst_done = ~(dram_rst | rom_rst | axi_rst | cpu_rst);

    // ---------------------------------------------------------------------
    // SoC instance.
    // ---------------------------------------------------------------------
    wire        result_valid;
    wire [2:0]  result_class;
    wire [7:0]  result_score;
    wire        data_ready, uart_err, rx_seen;   // from UART loader (clk50 domain)

    CHIP u_chip (
        .cpu_clk      (clk100_g),
        .axi_clk      (clk50_g),
        .rom_clk      (clk50_g),
        .dram_clk     (clk50_g),
        .cpu_rst      (cpu_rst),
        .axi_rst      (axi_rst),
        .rom_rst      (rom_rst),
        .dram_rst     (dram_rst),
        .uart_rxd     (uart_rxd),
        .data_ready   (data_ready),
        .uart_err     (uart_err),
        .rx_seen      (rx_seen),
        .result_valid (result_valid),
        .result_class (result_class),
        .result_score (result_score)
    );

    // UART status lives in the clk50 buffer domain; double-flop into clk100 for
    // the LED view (slow/steady levels -> simple 2FF sync is sufficient).
    reg [1:0] dr_sync = 2'b00, ue_sync = 2'b00, rs_sync = 2'b00;
    always @(posedge clk100_g) begin
        dr_sync <= {dr_sync[0], data_ready};
        ue_sync <= {ue_sync[0], uart_err};
        rs_sync <= {rs_sync[0], rx_seen};
    end
    wire data_ready_s = dr_sync[1];
    wire uart_err_s   = ue_sync[1];
    wire rx_seen_s    = rs_sync[1];

    // ---------------------------------------------------------------------
    // Latch the result on the first rising edge of result_valid (cpu domain).
    // ---------------------------------------------------------------------
    reg        valid_lat = 1'b0;
    reg [2:0]  class_lat = 3'd0;
    reg [7:0]  score_lat = 8'd0;
    always @(posedge clk100_g) begin
        if (!rst_done) begin
            valid_lat <= 1'b0;
            class_lat <= 3'd0;
            score_lat <= 8'd0;
        end
        else if (result_valid && !valid_lat) begin
            valid_lat <= 1'b1;
            class_lat <= result_class;
            score_lat <= result_score;
        end
    end

    // ---------------------------------------------------------------------
    // Heartbeat (clock-alive sanity) and LED multiplexer.
    // ---------------------------------------------------------------------
    reg [25:0] hb = 26'd0;
    always @(posedge clk100_g) hb <= hb + 26'd1;

    reg [7:0] led_r;
    always @(*) begin
        case (sw)
            2'b00:   led_r = score_lat;
            2'b01:   led_r = {valid_lat, 4'b0000, class_lat};
            // M1c UART/status view:
            //   LED7=rx_seen LED6=uart_err LED5=data_ready
            //   LED2=locked  LED1=rst_done LED0=valid
            2'b10:   led_r = {rx_seen_s, uart_err_s, data_ready_s, 2'b00,
                              locked, rst_done, valid_lat};
            default: led_r = hb[25:18];
        endcase
    end
    assign led = led_r;

endmodule
