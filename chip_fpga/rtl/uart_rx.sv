// uart_rx.sv  --  simple 8N1 UART receiver (no parity, 1 stop bit)
//
// Oversampled by the system clock. Emits a 1-cycle `valid` pulse with `data`
// when a byte has been received (LSB first, UART standard). The async `rxd`
// input is double-flopped before use.
//
// Default 115200 baud @ 100 MHz (DIV = 868).

`timescale 1ns/1ps

module uart_rx #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rxd,        // asynchronous serial input
    output logic [7:0] data,       // received byte (valid when `valid` is high)
    output logic       valid       // 1-cycle strobe
);
    localparam int DIV  = CLK_HZ / BAUD;   // clocks per bit
    localparam int HALF = DIV / 2;
    localparam int CW   = $clog2(DIV);

    // Synchronize the async input.
    logic [2:0] rxd_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rxd_q <= 3'b111;
        else        rxd_q <= {rxd_q[1:0], rxd};
    end
    wire rx = rxd_q[2];

    typedef enum logic [1:0] { S_IDLE, S_START, S_DATA, S_STOP } state_e;
    state_e        st;
    logic [CW-1:0] cnt;
    logic [2:0]    bit_idx;
    logic [7:0]    sh;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_IDLE;
            cnt     <= '0;
            bit_idx <= 3'd0;
            sh      <= 8'd0;
            data    <= 8'd0;
            valid   <= 1'b0;
        end
        else begin
            valid <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (!rx) begin           // start bit (line goes low)
                        st  <= S_START;
                        cnt <= '0;
                    end
                end
                S_START: begin
                    if (cnt == HALF-1) begin // sample middle of start bit
                        if (!rx) begin       // still low => real start
                            st      <= S_DATA;
                            cnt     <= '0;
                            bit_idx <= 3'd0;
                        end
                        else st <= S_IDLE;   // glitch
                    end
                    else cnt <= cnt + 1'b1;
                end
                S_DATA: begin
                    if (cnt == DIV-1) begin
                        cnt <= '0;
                        sh  <= {rx, sh[7:1]};   // LSB first
                        if (bit_idx == 3'd7) st <= S_STOP;
                        else                 bit_idx <= bit_idx + 3'd1;
                    end
                    else cnt <= cnt + 1'b1;
                end
                S_STOP: begin
                    if (cnt == DIV-1) begin
                        st    <= S_IDLE;
                        cnt   <= '0;
                        data  <= sh;            // stop bit not strictly checked
                        valid <= 1'b1;
                    end
                    else cnt <= cnt + 1'b1;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
