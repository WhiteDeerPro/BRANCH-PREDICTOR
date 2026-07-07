// ============================================================================
// TAGE Predictor Core Testbench
// 单周期测试：每个时钟周期处理一个分支
// ============================================================================

module tb_tage_predictor_core;

    import tage_pkg::*;
    
    localparam CLK_PERIOD = 10;
    localparam ADDR_MIN   = 0;
    localparam ADDR_MAX   = 16;          // 0~252, step 4, 共64个地址
    localparam ADDR_STEP  = 4;

    logic        clk, rst_n;
    logic [31:0] pc;

    logic        predict_vld;
    logic        update_vld;
    logic        is_taken_vld;
    logic        actual_taken_req;
    logic        actual_taken_update;


    // 使用 $bits 动态获取结构体的总位宽
    logic [$bits(tage_pkg::tage_snap_t)-1:0] input_snap_bus, output_snap_bus;
    logic        pred_taken;
    logic        pred_wrong;
    bit          verbose_trace;
    tage_snap_t  snap_reg;
    int          branch_cnt;
    int          correct_cnt;

    tage_snap_t snap_in, snap_out;
    assign snap_in = tage_snap_t'(input_snap_bus);
    
    // 将 DUT 输出的总线正确解包赋给 snap_out 结构体
    assign snap_out = tage_snap_t'(output_snap_bus);
    
    // DUT 实例化（端口名匹配修改后的 core）
    tage_predictor_core core (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_pc            (pc),

        .i_predict_vld   (predict_vld),

        .i_is_taken_vld     (is_taken_vld),
        .i_actual_taken  (actual_taken_update),
  		.i_is_snap_vld(update_vld),
        
        .i_input_snap_bus(input_snap_bus),
        .o_output_snap_bus(output_snap_bus),
        .o_pred_taken    (pred_taken),
        .o_pred_wrong    (pred_wrong)
    );

    // =========================================================================
    // 时钟生成
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // 地址生成 (PC)
    // =========================================================================
    int addr_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            addr_cnt <= ADDR_MIN;
        else if (addr_cnt >= ADDR_MAX)
            addr_cnt <= ADDR_MIN;
        else
            addr_cnt <= addr_cnt + ADDR_STEP;
    end
    assign pc = 32'(addr_cnt);

    // =========================================================================
    // 分支方向生成：确定性混合模式，避免依赖随机源。
    // =========================================================================
    function automatic logic actual_for_sample(input int addr, input int count);
        int pc_id;
        begin
            pc_id = addr >> 2;
            case (pc_id % 5)
                0:       actual_for_sample = ((count % 17) != 16);
                1:       actual_for_sample = ((count % 7) < 3);
                2:       actual_for_sample = count[0] ^ count[3];
                3:       actual_for_sample = ((count + pc_id) % 11) < 8;
                default: actual_for_sample = pc_id[0];
            endcase
        end
    endfunction

    assign actual_taken_req = actual_for_sample(addr_cnt, branch_cnt);

    // =========================================================================
    // 控制信号
    // =========================================================================
    
    assign predict_vld = 1'b1;                    // 每个周期都有一条新预测请求
    assign update_vld    = (branch_cnt != 0);      // 第一拍之后验证上一条预测
    assign is_taken_vld  = update_vld;


    assign actual_taken_update = snap_reg.actual_taken;
    assign input_snap_bus      = snap_reg;

    // =========================================================================
    // 统计准确率
    // =========================================================================
    logic last_pred_taken;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_cnt  <= 0;
            correct_cnt <= 0;
            last_pred_taken <= 0;
            snap_reg <= '0;
        end else begin
            last_pred_taken <= pred_taken;
            snap_reg <= snap_out;
            snap_reg.actual_taken <= actual_taken_req;
            // 采样当前预测
            branch_cnt <= branch_cnt + 1;
            if (pred_taken == actual_taken_req)     // 预测结果 vs 实际方向
                correct_cnt <= correct_cnt + 1;
        end
    end

    // =========================================================================
    // 默认关闭逐拍打印，仿真命令带 +verbose 时打开。
    // =========================================================================
    initial begin
        verbose_trace = $test$plusargs("verbose");
    end

    always_ff @(posedge clk) begin
        if (verbose_trace) begin
            $display("[%t] PC=0x%0h pred=%b actual=%b %s",
                     $time, pc, pred_taken, actual_taken_req,
                     (pred_taken == actual_taken_req) ? "CORRECT" : "WRONG");
        end
    end

    // =========================================================================
    // 仿真结束与三段式波形精简控制
    // =========================================================================
    int total_cycles = 50000;
    int window_len   = 200;
    int cycle_cnt;
    initial begin
        rst_n = 0;
        #20
        rst_n = 1;

        $fsdbDumpfile("tb_tage_predictor_core.fsdb");
        $fsdbDumpvars(0, tb_tage_predictor_core);

        // 记录开头窗口
        $fsdbDumpon;
        repeat(window_len) @(posedge clk);
        $fsdbDumpoff;

        // 跳过到 50% 窗口前
        cycle_cnt = window_len;
        while (cycle_cnt < total_cycles/2) begin
            @(posedge clk);
            cycle_cnt++;
        end

        // 记录 50% 窗口
        $fsdbDumpon;
        repeat(window_len) @(posedge clk);
        $fsdbDumpoff;
        cycle_cnt += window_len;

        // 跳过到 90% 窗口前
        while (cycle_cnt < total_cycles*9/10) begin
            @(posedge clk);
            cycle_cnt++;
        end

        // 记录 90% 窗口
        $fsdbDumpon;
        repeat(window_len) @(posedge clk);
        $fsdbDumpoff;

        // 跑完剩余周期
        while (cycle_cnt < total_cycles) begin
            @(posedge clk);
            cycle_cnt++;
        end

        $display("\n==================================================");
        $display("Total branches  : %0d", branch_cnt);
        $display("Correct predicts: %0d", correct_cnt);
        $display("Accuracy        : %.2f %%", (100.0 * correct_cnt / branch_cnt));
        $display("==================================================");

        $finish;
    end

endmodule
