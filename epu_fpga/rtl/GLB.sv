// GLB.sv  --  FPGA overlay for standalone EPU-first bring-up.
//
// Same module name / ports as AOC-vcs-version/hardware/src/EPU/GLB.sv, but the
// power-up contents are initialized from glb_init.hex (input @word0, weights
// @word1024) so the EPU sees the same state the firmware DMA would have left.
// Vivado honors `initial $readmemh` as BRAM initialization during synthesis.
//
// The original GLB.sv is left untouched for the VCS/Verilator flow; the Phase-A
// build.tcl includes THIS file instead.
module GLB (
    input  logic        clk,
    input  logic        en,
    input  logic        we,
    input  logic [14:0] addr,   // addr[14] selects bank; total depth = 32K words
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,  // byte write enable, 1 = write this byte
    output logic [31:0] rdata
);

    localparam int DEPTH = 1 << 15;

    // Init image path. Vivado synthesis resolves $readmemh unreliably by bare
    // basename (it silently ignores a not-found file), so use an absolute path.
    // This overlay is a machine-specific FPGA build helper; the path is fixed.
    parameter string INIT_HEX = "D:/AOC-final/epu_fpga/glb_init.hex";

    (* ram_style = "block" *) logic [31:0] mem [0:DEPTH-1];

    // BRAM initialization (synthesis + simulation). All 32768 words are present
    // in glb_init.hex, so this fully defines power-up contents.
    initial begin
        $readmemh(INIT_HEX, mem);
    end

    always @(posedge clk) begin
        if (en) begin
            if (we) begin
                for (int b = 0; b < 4; b++) begin
                    if (wstrb[b]) begin
                        mem[addr][8*b +: 8] <= wdata[8*b +: 8];
                    end
                end
            end
            else begin
                rdata <= mem[addr];
            end
        end
    end

endmodule
