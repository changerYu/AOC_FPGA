// GLB.sv  --  DIAGNOSTIC overlay: weights baked, input region (words 0..543)
// left ZERO. Identical to rtl/GLB.sv except INIT_HEX points to the zeroed-input
// image. Used only by build_epu_uart_zeroinput.tcl to prove the on-board result
// comes from UART-streamed input (no UART -> non-golden result; with UART -> 0x67).
module GLB (
    input  logic        clk,
    input  logic        en,
    input  logic        we,
    input  logic [14:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    output logic [31:0] rdata
);
    localparam int DEPTH = 1 << 15;
    parameter string INIT_HEX = "D:/AOC-final/epu_fpga/glb_init_zeroinput.hex";

    (* ram_style = "block" *) logic [31:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(INIT_HEX, mem);
    end

    always @(posedge clk) begin
        if (en) begin
            if (we) begin
                for (int b = 0; b < 4; b++) begin
                    if (wstrb[b]) mem[addr][8*b +: 8] <= wdata[8*b +: 8];
                end
            end
            else rdata <= mem[addr];
        end
    end
endmodule
