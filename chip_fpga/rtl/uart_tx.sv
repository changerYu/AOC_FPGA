// ============================================================================
// uart_tx.sv -- M2A: minimal 8N1 UART transmitter for the FPGA->ESP32 ACK.
//
// One byte per `send` pulse. When the EPU finishes a classification the SoC
// pulses `send` (rising edge of the EPU done interrupt) and this module shifts
// out a single ACK byte (start + 8 data LSB-first + stop) at BAUD. While busy
// the module ignores further `send` pulses (txd held idle high between bytes).
//
// Runs in the cpu_clk (100 MHz) domain, same as the EPU done interrupt, so no
// CDC is needed on the trigger; txd is asynchronous to the ESP32 by nature of
// UART. Default 115200 baud @ 100 MHz (DIV = 868).
//
// ASCII-only comments (Big5/cp950 Windows console safe).
// ============================================================================

`timescale 1ns/1ps

module uart_tx #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       send,        // 1-cycle request to transmit `data`
    input  logic [7:0] data,        // byte to send (latched when accepted)
    output logic       txd,         // serial out (idle high)
    output logic       busy         // high while a byte is in flight
);
    localparam int DIV = CLK_HZ / BAUD;          // clocks per bit
    localparam int CW  = $clog2(DIV);

    typedef enum logic [1:0] { T_IDLE, T_START, T_DATA, T_STOP } state_e;
    state_e        st;
    logic [CW-1:0] cnt;
    logic [2:0]    bit_idx;
    logic [7:0]    sh;

    assign busy = (st != T_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= T_IDLE;
            cnt     <= '0;
            bit_idx <= 3'd0;
            sh      <= 8'd0;
            txd     <= 1'b1;          // line idle high
        end
        else begin
            case (st)
                T_IDLE: begin
                    txd <= 1'b1;
                    if (send) begin
                        sh  <= data;
                        cnt <= '0;
                        st  <= T_START;
                    end
                end
                T_START: begin
                    txd <= 1'b0;                 // start bit
                    if (cnt == DIV-1) begin
                        cnt     <= '0;
                        bit_idx <= 3'd0;
                        st      <= T_DATA;
                    end
                    else cnt <= cnt + 1'b1;
                end
                T_DATA: begin
                    txd <= sh[0];                // LSB first
                    if (cnt == DIV-1) begin
                        cnt <= '0;
                        sh  <= {1'b0, sh[7:1]};
                        if (bit_idx == 3'd7) st <= T_STOP;
                        else                 bit_idx <= bit_idx + 3'd1;
                    end
                    else cnt <= cnt + 1'b1;
                end
                T_STOP: begin
                    txd <= 1'b1;                 // stop bit
                    if (cnt == DIV-1) begin
                        cnt <= '0;
                        st  <= T_IDLE;
                    end
                    else cnt <= cnt + 1'b1;
                end
                default: st <= T_IDLE;
            endcase
        end
    end
endmodule
