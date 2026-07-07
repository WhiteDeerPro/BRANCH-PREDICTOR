// ============================================================================
// TAGE Predictor Wrapper (参数化 N 级流水线支持)
// 对外提供简洁接口，内部实例化 tage_predictor_core
// 支持 PIPELINE_DEPTH = 0, 1, 2 ... N 级打拍
// ============================================================================

module tage_predictor #(
    parameter int PIPELINE_DEPTH   = 11,
    parameter int CORE_LATENCY     = 1,
    parameter int GHR_LEN          = tage_pkg::GHR_LEN,
    parameter int BIMODAL_SIZE     = tage_pkg::BIMODAL_SIZE,
    parameter int BIMODAL_CTR_W    = tage_pkg::BIMODAL_CTR_W,
    parameter int NUM_TABLES       = tage_pkg::NUM_TABLES,
    parameter int TAG_CTR_W        = tage_pkg::TAG_CTR_W,
    parameter int TAG_USE_W        = tage_pkg::TAG_USE_W,
    parameter int AGE_INTERVAL     = 4096,
    parameter bit [NUM_TABLES*32-1:0] HIST_LENS_LUT     = tage_pkg::HIST_LENS_LUT,
    parameter bit [NUM_TABLES*32-1:0] TABLE_ENTRIES_LUT = tage_pkg::TABLE_ENTRIES_LUT,
    parameter bit [NUM_TABLES*8-1:0]  TAG_WIDTH_LUT     = tage_pkg::TAG_WIDTH_LUT
) (
    input  logic        i_clk,
    input  logic        i_rst_n,
    input  logic [31:0] i_pc,

    // Current PC is a branch and requests a prediction.
    input  logic        i_is_taken_vld,
    // Resolved outcome aligned with the wrapper delay pipe.
    input  logic        i_actual_taken,

    output logic        o_pred_vld,
    output logic        o_pred_taken
);
    import tage_pkg::*;

    localparam int FEEDBACK_DEPTH = PIPELINE_DEPTH - CORE_LATENCY;

    logic                      is_taken_vld;
    logic                      resolve_wrong;
    logic                      flush_younger;
    logic                      core_pred_vld;

    tage_snap_t snap_to_core, snap_from_core;
    logic is_snap_vld;

    // A wrong resolved branch invalidates younger delayed snapshots.
    assign flush_younger = resolve_wrong && is_snap_vld;

    generate
        if (PIPELINE_DEPTH == 0) begin : GEN_UPDATE_DIRECT
            assign is_taken_vld   = i_is_taken_vld;
        end else begin : GEN_PIPELINE_REGISTERS
            logic [PIPELINE_DEPTH-1:0] taken_vld_pipe;

            if (PIPELINE_DEPTH == 1) begin : GEN_ONE_STAGE
                always_ff @(posedge i_clk or negedge i_rst_n) begin
                    if (!i_rst_n)
                        taken_vld_pipe <= '0;
                    else
                        taken_vld_pipe[0] <= i_is_taken_vld;
                end
            end else begin : GEN_MULTI_STAGE
                always_ff @(posedge i_clk or negedge i_rst_n) begin
                    if (!i_rst_n)
                        taken_vld_pipe <= '0;
                    else
                        taken_vld_pipe  <= {taken_vld_pipe[PIPELINE_DEPTH-2:0], i_is_taken_vld};
                end
            end

            assign is_taken_vld   = taken_vld_pipe[PIPELINE_DEPTH-1];
        end
    endgenerate

    generate
        if (FEEDBACK_DEPTH == 0) begin : GEN_SNAPSHOT_DIRECT
            assign snap_to_core = snap_from_core;
            assign is_snap_vld  = core_pred_vld;
        end else begin : GEN_SNAPSHOT_PIPE
            logic [FEEDBACK_DEPTH-1:0] snap_vld_pipe;
            tage_snap_t                snap_pipe [0:FEEDBACK_DEPTH-1];

            if (FEEDBACK_DEPTH == 1) begin : GEN_SNAPSHOT_ONE
                always_ff @(posedge i_clk or negedge i_rst_n) begin
                    if (!i_rst_n) begin
                        snap_vld_pipe <= '0;
                        snap_pipe[0]  <= '0;
                    end else begin
                        snap_vld_pipe[0] <= flush_younger ? 1'b0 : core_pred_vld;
                        snap_pipe[0]     <= snap_from_core;
                    end
                end
            end else begin : GEN_SNAPSHOT_MULTI
                always_ff @(posedge i_clk or negedge i_rst_n) begin
                    if (!i_rst_n) begin
                        snap_vld_pipe <= '0;
                        for (int i = 0; i < FEEDBACK_DEPTH; i++)
                            snap_pipe[i] <= '0;
                    end else begin
                        if (flush_younger)
                            snap_vld_pipe <= {{(FEEDBACK_DEPTH-1){1'b0}}, 1'b0};
                        else
                            snap_vld_pipe <= {snap_vld_pipe[FEEDBACK_DEPTH-2:0], core_pred_vld};

                        snap_pipe[0] <= snap_from_core;
                        for (int i = 1; i < FEEDBACK_DEPTH; i++)
                            snap_pipe[i] <= snap_pipe[i-1];
                    end
                end
            end

            assign snap_to_core = snap_pipe[FEEDBACK_DEPTH-1];
            assign is_snap_vld  = snap_vld_pipe[FEEDBACK_DEPTH-1];
        end
    endgenerate

    // ========================================================================
    // TAGE Core 核心实例化
    // ========================================================================
    tage_predictor_core #(
        .GHR_LEN          (GHR_LEN),
        .BIMODAL_SIZE     (BIMODAL_SIZE),
        .BIMODAL_CTR_W    (BIMODAL_CTR_W),
        .NUM_TABLES       (NUM_TABLES),
        .TAG_CTR_W        (TAG_CTR_W),
        .TAG_USE_W        (TAG_USE_W),
        .PREDICT_LATENCY  (CORE_LATENCY),
        .AGE_INTERVAL     (AGE_INTERVAL),
        .HIST_LENS_LUT    (HIST_LENS_LUT),
        .TABLE_ENTRIES_LUT(TABLE_ENTRIES_LUT),
        .TAG_WIDTH_LUT    (TAG_WIDTH_LUT)
    ) core (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),
        .i_pc             (i_pc),

        .i_predict_vld    (i_is_taken_vld),
        .i_actual_taken   (i_actual_taken),

        .i_is_taken_vld    (is_taken_vld),
        .i_is_snap_vld     (is_snap_vld),

        .i_input_snap_bus (snap_to_core),
        .o_output_snap_bus(snap_from_core),

        .o_pred_vld       (core_pred_vld),
        .o_pred_taken     (o_pred_taken),
        .o_pred_wrong     (resolve_wrong)
    );

    assign o_pred_vld = core_pred_vld;

endmodule
