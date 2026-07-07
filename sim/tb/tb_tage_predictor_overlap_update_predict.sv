// ============================================================================
// TAGE Predictor Wrapper Overlap Testbench
//   - A new branch is predicted in the same cycle that the previous branch
//     returns its actual direction.
//   - This stresses snapshot consistency when update_vld and a fresh lookup
//     happen together.
// ============================================================================

module tb_tage_predictor_overlap_update_predict;

    localparam int PIPELINE_DEPTH       = 11;
    localparam int CLK_PERIOD           = 10;
    localparam int BRANCH_GAP_CYCLES    = PIPELINE_DEPTH;
    localparam int TOTAL_CYCLES_DEFAULT = 50000;

    localparam int ADDR_MIN  = 0;
    localparam int ADDR_MAX  = 16;
    localparam int ADDR_STEP = 4;

    logic clk;
    logic rst_n;

    logic [31:0] pc;
    logic        is_taken_vld;
    logic        actual_taken;
    logic        actual_taken_req;
    logic        pred_taken;

    int total_cycles;
    int gap_cnt;
    int addr_cnt;
    int branch_cnt;
    int correct_cnt;
    bit verbose_trace;

    logic [PIPELINE_DEPTH-1:0] outstanding_pipe;
    logic [PIPELINE_DEPTH-1:0] actual_pipe;

    function automatic logic actual_for_addr(input int addr);
        case (addr)
            0:        actual_for_addr = 1'b1;
            4:        actual_for_addr = 1'b0;
            8:        actual_for_addr = 1'b1;
            12:       actual_for_addr = 1'b0;
            16:       actual_for_addr = 1'b1;
            default:  actual_for_addr = addr[3];
        endcase
    endfunction

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        total_cycles = TOTAL_CYCLES_DEFAULT;
        void'($value$plusargs("max_cycles=%d", total_cycles));
        verbose_trace = $test$plusargs("verbose");

        $fsdbDumpfile("tb_tage_predictor_overlap_update_predict.fsdb");
        $fsdbDumpvars(0, tb_tage_predictor_overlap_update_predict);

        repeat (total_cycles) @(posedge clk);

        $display("\n==================================================");
        $display("Wrapper overlap update/predict smoke test");
        $display("Pipeline depth   : %0d", PIPELINE_DEPTH);
        $display("Branch gap cycles: %0d", BRANCH_GAP_CYCLES);
        $display("Total branches   : %0d", branch_cnt);
        $display("Correct predicts : %0d", correct_cnt);
        if (branch_cnt != 0)
            $display("Accuracy         : %.2f %%", (100.0 * correct_cnt / branch_cnt));
        $display("==================================================");

        if (branch_cnt == 0)
            $fatal(1, "No branches were generated.");
        if ((correct_cnt * 100) < (branch_cnt * 90))
            $fatal(1, "Accuracy is below 90%%.");

        $finish;
    end

    assign is_taken_vld     = (rst_n && gap_cnt == 0);
    assign actual_taken_req = actual_for_addr(addr_cnt);
    assign actual_taken     = actual_pipe[PIPELINE_DEPTH-1];
    assign pc               = 32'(addr_cnt);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gap_cnt          <= 0;
            addr_cnt         <= ADDR_MIN;
            branch_cnt       <= 0;
            correct_cnt      <= 0;
            outstanding_pipe <= '0;
            actual_pipe      <= '0;
        end else begin
            gap_cnt <= (gap_cnt == BRANCH_GAP_CYCLES-1) ? 0 : gap_cnt + 1;

            if (is_taken_vld) begin
                if (|outstanding_pipe[PIPELINE_DEPTH-2:0])
                    $fatal(1, "More than one unresolved branch before same-cycle resolve at time %0t", $time);

                branch_cnt <= branch_cnt + 1;
                if (pred_taken == actual_taken_req)
                    correct_cnt <= correct_cnt + 1;

                if (verbose_trace || branch_cnt < 8) begin
                    $display("[%t] branch=%0d PC=0x%0h pred=%b actual=%b resolving=%b %s",
                             $time, branch_cnt + 1, pc, pred_taken, actual_taken_req,
                             outstanding_pipe[PIPELINE_DEPTH-1],
                             (pred_taken == actual_taken_req) ? "CORRECT" : "WRONG");
                end

                if (addr_cnt >= ADDR_MAX)
                    addr_cnt <= ADDR_MIN;
                else
                    addr_cnt <= addr_cnt + ADDR_STEP;
            end

            outstanding_pipe <= {outstanding_pipe[PIPELINE_DEPTH-2:0], is_taken_vld};
            actual_pipe      <= {actual_pipe[PIPELINE_DEPTH-2:0], is_taken_vld ? actual_taken_req : 1'b0};
        end
    end

    tage_predictor #(
        .PIPELINE_DEPTH (PIPELINE_DEPTH)
    ) dut (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .i_pc           (pc),
        .i_is_taken_vld (is_taken_vld),
        .i_actual_taken (actual_taken),
        .o_pred_taken   (pred_taken)
    );

endmodule
