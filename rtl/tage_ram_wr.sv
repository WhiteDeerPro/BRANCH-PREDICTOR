// ============================================================
// 1W1R RAM
// ============================================================
module tage_ram_wr #(
    parameter DEPTH = 1024,
    parameter WIDTH = 32
) (
    input  logic               i_clk,
    // 写端口
    input  logic               i_wr_en,
    input  logic [$clog2(DEPTH)-1:0] i_wr_addr,
    input  logic [WIDTH-1:0]   i_wr_data,
    // 读端口 (组合输出)
    input  logic [$clog2(DEPTH)-1:0] i_rd_addr,
    output logic [WIDTH-1:0]   o_rd_data
);

    logic [WIDTH-1:0] mem [DEPTH] = '{default: '0};

    // 组合读
    assign o_rd_data = mem[i_rd_addr];

    // 时序写
    always_ff @(posedge i_clk) begin
        if (i_wr_en)
            mem[i_wr_addr] <= i_wr_data;
    end

endmodule