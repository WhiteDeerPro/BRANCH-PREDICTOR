// ============================================================================
// TAGE Predictor Trace Testbench
//   - Reads dynamic execution vectors: PC ISBR BRRES BRPC1 BRPC2.
//   - ISBR rows drive wrapper predictions.
//   - BRRES is returned after PIPELINE_DEPTH cycles.
//   - A reference core is driven with the same prediction/update timing and
//     must match the wrapper on every branch prediction.
// ============================================================================

module tb_tage_predictor_trace;

    import tage_pkg::*;

    localparam int PIPELINE_DEPTH = 11;
    localparam int CLK_PERIOD     = 10;

`ifdef TAGE_CFG_TINY
    localparam int CFG_BIMODAL_SIZE = 256;
    localparam bit [tage_pkg::NUM_TABLES*32-1:0] CFG_HIST_LENS_LUT     = {32'd4, 32'd8, 32'd16, 32'd32, 32'd64};
    localparam bit [tage_pkg::NUM_TABLES*32-1:0] CFG_TABLE_ENTRIES_LUT = {32'd256, 32'd256, 32'd256, 32'd256, 32'd256};
    localparam bit [tage_pkg::NUM_TABLES*8-1:0]  CFG_TAG_WIDTH_LUT     = {8'd8, 8'd8, 8'd8, 8'd8, 8'd8};
`elsif TAGE_CFG_WIDE
    localparam int CFG_BIMODAL_SIZE = 1024;
    localparam bit [tage_pkg::NUM_TABLES*32-1:0] CFG_HIST_LENS_LUT     = {32'd16, 32'd32, 32'd64, 32'd96, 32'd120};
    localparam bit [tage_pkg::NUM_TABLES*32-1:0] CFG_TABLE_ENTRIES_LUT = {32'd1024, 32'd1024, 32'd1024, 32'd1024, 32'd1024};
    localparam bit [tage_pkg::NUM_TABLES*8-1:0]  CFG_TAG_WIDTH_LUT     = {8'd12, 8'd12, 8'd12, 8'd12, 8'd12};
`else
    localparam int CFG_BIMODAL_SIZE = tage_pkg::BIMODAL_SIZE;
    localparam bit [tage_pkg::NUM_TABLES*32-1:0] CFG_HIST_LENS_LUT     = tage_pkg::HIST_LENS_LUT;
    localparam bit [tage_pkg::NUM_TABLES*32-1:0] CFG_TABLE_ENTRIES_LUT = tage_pkg::TABLE_ENTRIES_LUT;
    localparam bit [tage_pkg::NUM_TABLES*8-1:0]  CFG_TAG_WIDTH_LUT     = tage_pkg::TAG_WIDTH_LUT;
`endif

    logic clk;
    logic rst_n;

    logic [31:0] pc;
    logic        predict_req_vld;
    logic        trace_actual_taken;
    logic [31:0] brpc1;
    logic [31:0] brpc2;

    logic        resolve_actual_taken;
    logic        wrap_pred;

    logic [PIPELINE_DEPTH-1:0] resolve_actual_pipe;
    logic [PIPELINE_DEPTH-1:0] ref_resolve_vld_pipe;
    logic [PIPELINE_DEPTH-1:0] ref_resolve_snap_vld_pipe;
    tage_snap_t                ref_snap_pipe [0:PIPELINE_DEPTH-1];

    logic [$bits(tage_pkg::tage_snap_t)-1:0] ref_snap_in_bus;
    logic [$bits(tage_pkg::tage_snap_t)-1:0] ref_snap_out_bus;
    logic ref_resolve_vld;
    logic ref_resolve_snap_vld;
    logic ref_pred;
    logic ref_resolve_wrong;
    logic ref_flush_younger;

    int fd;
    int max_cycles;
    int warmup_branches;
    int cycle_cnt;
    int vector_cnt;
    int branch_cnt;
    int measured_cnt;
    int match_cnt;
    int mismatch_cnt;
    int wrap_correct_cnt;
    int ref_correct_cnt;
    int pc_flow_errors;
    int drain_cnt;
    int dbg_cycles;
    bit eof_seen;
    bit verbose_trace;
    bit expected_pc_vld;
    logic [31:0] expected_pc;
    string trace_file;
    bit load_eof;
    logic [31:0] load_pc;
    logic [31:0] load_brpc1;
    logic [31:0] load_brpc2;
    logic load_predict_req_vld;
    logic load_actual;

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    task automatic load_next_vector(
        output logic [31:0] next_pc,
        output logic        next_predict_req_vld,
        output logic        next_actual,
        output logic [31:0] next_brpc1,
        output logic [31:0] next_brpc2,
        output bit          next_eof
    );
        string line;
        int parsed;
        int isbr_i;
        int brres_i;
        begin
            next_pc         = '0;
            next_predict_req_vld = 1'b0;
            next_actual     = 1'b0;
            next_brpc1      = '0;
            next_brpc2      = '0;
            next_eof        = 1'b0;
            parsed          = 0;

            while (parsed != 5 && !$feof(fd)) begin
                void'($fgets(line, fd));
                parsed = $sscanf(line, "%h %d %d %h %h",
                                 next_pc, isbr_i, brres_i, next_brpc1, next_brpc2);
            end

            if (parsed == 5) begin
                next_predict_req_vld = (isbr_i != 0);
                next_actual     = (brres_i != 0);
            end else begin
                next_eof = 1'b1;
            end
        end
    endtask

    initial begin
        trace_file      = "../../sim/tb/traces/ws128_mixed.trace";
        max_cycles      = 300000;
        warmup_branches = 10000;
        dbg_cycles      = 40;
        verbose_trace   = $test$plusargs("verbose");

        void'($value$plusargs("trace=%s", trace_file));
        void'($value$plusargs("max_cycles=%d", max_cycles));
        void'($value$plusargs("warmup=%d", warmup_branches));
        void'($value$plusargs("dbg_cycles=%d", dbg_cycles));

        fd = $fopen(trace_file, "r");
        if (fd == 0)
            $fatal(1, "Failed to open trace file: %s", trace_file);

        $fsdbDumpfile("tb_tage_predictor_trace.fsdb");
        $fsdbDumpvars(0, tb_tage_predictor_trace);
    end

    assign resolve_actual_taken    = resolve_actual_pipe[PIPELINE_DEPTH-1];
    assign ref_resolve_vld = ref_resolve_vld_pipe[PIPELINE_DEPTH-1];
    assign ref_resolve_snap_vld  = ref_resolve_snap_vld_pipe[PIPELINE_DEPTH-1];
    assign ref_snap_in_bus      = ref_snap_pipe[PIPELINE_DEPTH-1];
    assign ref_flush_younger = ref_resolve_wrong && ref_resolve_snap_vld;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc                 <= '0;
            predict_req_vld         <= 1'b0;
            trace_actual_taken         <= 1'b0;
            brpc1              <= '0;
            brpc2              <= '0;
            resolve_actual_pipe        <= '0;
            ref_resolve_vld_pipe <= '0;
            ref_resolve_snap_vld_pipe  <= '0;
            for (int i = 0; i < PIPELINE_DEPTH; i++)
                ref_snap_pipe[i] <= '0;
            cycle_cnt       <= 0;
            vector_cnt      <= 0;
            branch_cnt      <= 0;
            measured_cnt    <= 0;
            match_cnt       <= 0;
            mismatch_cnt    <= 0;
            wrap_correct_cnt <= 0;
            ref_correct_cnt <= 0;
            pc_flow_errors  <= 0;
            drain_cnt       <= 0;
            eof_seen        <= 1'b0;
            expected_pc_vld <= 1'b0;
            expected_pc     <= '0;
            load_eof        <= 1'b0;
            load_pc         <= '0;
            load_brpc1      <= '0;
            load_brpc2      <= '0;
            load_predict_req_vld <= 1'b0;
            load_actual     <= 1'b0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;

            if (predict_req_vld || (!eof_seen && vector_cnt != 0)) begin
                if (expected_pc_vld && pc != expected_pc) begin
                    pc_flow_errors <= pc_flow_errors + 1;
                    $fatal(1, "Trace PC flow error at vector %0d: pc=0x%0h expected=0x%0h",
                           vector_cnt, pc, expected_pc);
                end
                expected_pc_vld <= 1'b1;
                expected_pc     <= predict_req_vld ? (trace_actual_taken ? brpc2 : brpc1) : (pc + 32'd4);
            end

            if (predict_req_vld) begin
                branch_cnt <= branch_cnt + 1;

                if (wrap_pred == ref_pred)
                    match_cnt <= match_cnt + 1;
                else
                    mismatch_cnt <= mismatch_cnt + 1;

                if (branch_cnt >= warmup_branches) begin
                    measured_cnt <= measured_cnt + 1;
                    if (wrap_pred == trace_actual_taken)
                        wrap_correct_cnt <= wrap_correct_cnt + 1;
                    if (ref_pred == trace_actual_taken)
                        ref_correct_cnt <= ref_correct_cnt + 1;
                end

                if (verbose_trace || branch_cnt < 8) begin
                    $display("[%t] branch=%0d PC=0x%0h actual=%b wrap=%b ref=%b target=0x%0h %s",
                             $time, branch_cnt + 1, pc, trace_actual_taken, wrap_pred, ref_pred,
                             trace_actual_taken ? brpc2 : brpc1,
                             (wrap_pred == ref_pred) ? "MATCH" : "MISMATCH");
                end
            end

            if (cycle_cnt < dbg_cycles) begin
                $display("[DBG %0t] cyc=%0d pc=0x%0h predict_req=%b resolve_vld=%b resolve_snap=%b resolve_actual=%b wrap_pred=%b ref_pred=%b resolve_wrong=%b flush_younger=%b snap_pipe=%b",
                         $time, cycle_cnt, pc, predict_req_vld, ref_resolve_vld,
                         ref_resolve_snap_vld, resolve_actual_taken, wrap_pred, ref_pred,
                         ref_resolve_wrong, ref_flush_younger, ref_resolve_snap_vld_pipe);
            end

            if (ref_flush_younger)
                ref_resolve_snap_vld_pipe <= {{(PIPELINE_DEPTH-1){1'b0}}, predict_req_vld};
            else
                ref_resolve_snap_vld_pipe <= {ref_resolve_snap_vld_pipe[PIPELINE_DEPTH-2:0], predict_req_vld};
            ref_resolve_vld_pipe <= {ref_resolve_vld_pipe[PIPELINE_DEPTH-2:0], predict_req_vld};

            ref_snap_pipe[0] <= tage_snap_t'(ref_snap_out_bus);
            for (int i = 1; i < PIPELINE_DEPTH; i++)
                ref_snap_pipe[i] <= ref_snap_pipe[i-1];

            resolve_actual_pipe <= {resolve_actual_pipe[PIPELINE_DEPTH-2:0], predict_req_vld ? trace_actual_taken : 1'b0};

            if (!eof_seen) begin
                load_next_vector(load_pc, load_predict_req_vld, load_actual,
                                 load_brpc1, load_brpc2, load_eof);
                eof_seen <= load_eof;
                if (load_eof) begin
                    pc         <= '0;
                    predict_req_vld <= 1'b0;
                    trace_actual_taken <= 1'b0;
                    brpc1      <= '0;
                    brpc2      <= '0;
                end else begin
                    pc         <= load_pc;
                    predict_req_vld <= load_predict_req_vld;
                    trace_actual_taken <= load_actual;
                    brpc1      <= load_brpc1;
                    brpc2      <= load_brpc2;
                    vector_cnt <= vector_cnt + 1;
                end
            end else begin
                pc         <= '0;
                predict_req_vld <= 1'b0;
                trace_actual_taken <= 1'b0;
                brpc1      <= '0;
                brpc2      <= '0;
                drain_cnt  <= drain_cnt + 1;
            end

            if (cycle_cnt > max_cycles)
                $fatal(1, "Trace test timeout after %0d cycles", max_cycles);

            if (eof_seen && drain_cnt >= PIPELINE_DEPTH + 2) begin
                $display("\n==================================================");
                $display("Wrapper/Core trace compare test");
                $display("Trace file       : %s", trace_file);
                $display("Pipeline depth   : %0d", PIPELINE_DEPTH);
                $display("Vectors          : %0d", vector_cnt);
                $display("Total branches   : %0d", branch_cnt);
                $display("Warmup branches  : %0d", warmup_branches);
                $display("Measured branches: %0d", measured_cnt);
                $display("Prediction match : %0d", match_cnt);
                $display("Mismatches       : %0d", mismatch_cnt);
                $display("PC flow errors   : %0d", pc_flow_errors);
                $display("Wrapper correct  : %0d", wrap_correct_cnt);
                $display("Reference correct: %0d", ref_correct_cnt);
                if (measured_cnt != 0) begin
                    $display("Wrapper accuracy : %.2f %%", (100.0 * wrap_correct_cnt / measured_cnt));
                    $display("Reference accuracy: %.2f %%", (100.0 * ref_correct_cnt / measured_cnt));
                end
                $display("==================================================");

                if (mismatch_cnt != 0)
                    $fatal(1, "Wrapper prediction mismatched reference core.");
                if (pc_flow_errors != 0)
                    $fatal(1, "Trace PC flow check failed.");
                if (measured_cnt == 0)
                    $fatal(1, "No measured branches. Reduce warmup or increase trace length.");

                $finish;
            end
        end
    end

    tage_predictor #(
        .PIPELINE_DEPTH    (PIPELINE_DEPTH),
        .BIMODAL_SIZE      (CFG_BIMODAL_SIZE),
        .HIST_LENS_LUT     (CFG_HIST_LENS_LUT),
        .TABLE_ENTRIES_LUT (CFG_TABLE_ENTRIES_LUT),
        .TAG_WIDTH_LUT     (CFG_TAG_WIDTH_LUT)
    ) dut_wrapper (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .i_pc           (pc),
        .i_is_taken_vld (predict_req_vld),
        .i_actual_taken (resolve_actual_taken),
        .o_pred_taken   (wrap_pred)
    );

    tage_predictor_core #(
        .BIMODAL_SIZE      (CFG_BIMODAL_SIZE),
        .HIST_LENS_LUT     (CFG_HIST_LENS_LUT),
        .TABLE_ENTRIES_LUT (CFG_TABLE_ENTRIES_LUT),
        .TAG_WIDTH_LUT     (CFG_TAG_WIDTH_LUT)
    ) ref_core (
        .i_clk             (clk),
        .i_rst_n           (rst_n),
        .i_pc              (pc),
        .i_predict_vld     (predict_req_vld),
        .i_actual_taken    (resolve_actual_taken),
        .i_is_snap_vld     (ref_resolve_snap_vld),
        .i_is_taken_vld    (ref_resolve_vld),
        .i_input_snap_bus  (ref_snap_in_bus),
        .o_output_snap_bus (ref_snap_out_bus),
        .o_pred_taken      (ref_pred),
        .o_pred_wrong      (ref_resolve_wrong)
    );

endmodule
