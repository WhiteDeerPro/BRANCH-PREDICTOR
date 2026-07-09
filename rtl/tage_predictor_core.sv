// =========================================================================
// TAGE 预测器核心
// 依赖: tage_pkg.sv, tage_ram_wr.sv
// =========================================================================

module tage_predictor_core #(
    // 从 package 继承默认值，允许外部覆盖
    parameter int GHR_LEN          = tage_pkg::GHR_LEN,
    parameter int BIMODAL_SIZE     = tage_pkg::BIMODAL_SIZE,
    parameter int BIMODAL_CTR_W    = tage_pkg::BIMODAL_CTR_W,
    parameter int NUM_TABLES       = tage_pkg::NUM_TABLES,
    parameter int TAG_CTR_W        = tage_pkg::TAG_CTR_W,
    parameter int TAG_USE_W        = tage_pkg::TAG_USE_W,
    parameter int PREDICT_LATENCY  = 1,
    parameter int AGE_INTERVAL     = 4096,
    parameter int U_AGING_MODE     = tage_pkg::U_AGING_MODE,
    parameter int U_RESET_SCAN_ENTRIES = tage_pkg::U_RESET_SCAN_ENTRIES,
    parameter bit USE_ALT_ON_NA    = tage_pkg::USE_ALT_ON_NA,
    parameter int USE_ALT_CTR_W    = tage_pkg::USE_ALT_CTR_W,
    parameter int USE_ALT_CTR_INIT = tage_pkg::USE_ALT_CTR_INIT,
    parameter bit USE_ALT_REQUIRE_U_ZERO = tage_pkg::USE_ALT_REQUIRE_U_ZERO,
    parameter bit UPDATE_ALT_ON_U_ZERO = tage_pkg::UPDATE_ALT_ON_U_ZERO,
    parameter int ALLOC_POLICY     = tage_pkg::ALLOC_POLICY,
    parameter bit ALLOC_FAIL_DEC_U = tage_pkg::ALLOC_FAIL_DEC_U,
    parameter int ALLOC_FAIL_TICK_W = tage_pkg::ALLOC_FAIL_TICK_W,
    // 从 package 继承 LUT 参数
    parameter bit [NUM_TABLES*32-1:0] HIST_LENS_LUT     = tage_pkg::HIST_LENS_LUT,
    parameter bit [NUM_TABLES*32-1:0] TABLE_ENTRIES_LUT = tage_pkg::TABLE_ENTRIES_LUT,
    parameter bit [NUM_TABLES*8-1:0]  TAG_WIDTH_LUT     = tage_pkg::TAG_WIDTH_LUT
) (
    input  logic                                      i_clk,
    input  logic                                      i_rst_n,
    input  logic [31:0]                               i_pc,

    input  logic                                      i_predict_vld,

    input  logic                                      i_actual_taken,

    input  logic                                      i_is_snap_vld,  

    input  logic                                      i_is_taken_vld,

    input  logic [$bits(tage_pkg::tage_snap_t)-1:0]   i_input_snap_bus,
    output logic [$bits(tage_pkg::tage_snap_t)-1:0]   o_output_snap_bus,
    
    output logic                                      o_pred_vld,
    output logic                                      o_pred_taken,
    output logic                                      o_pred_wrong
);

    import tage_pkg::*;

    // =========================================================================
    // 内部参数推导
    // =========================================================================
    localparam int BIMODAL_IDX_W = $clog2(BIMODAL_SIZE);
    localparam int ID_WIDTH      = $clog2(NUM_TABLES+1);
    localparam int MAX_IDX_WIDTH = tage_pkg::MAX_IDX_WIDTH;
    localparam int MAX_TAG_WIDTH = tage_pkg::MAX_TAG_WIDTH;
    localparam int AGE_SCAN_W    = (U_RESET_SCAN_ENTRIES <= 1) ? 1 : $clog2(U_RESET_SCAN_ENTRIES);

    // =========================================================================
    // 内部信号声明
    // =========================================================================
    logic [GHR_LEN-1:0]                     commit_ghr;
    logic [GHR_LEN-1:0]                     specu_ghr;
    logic [ID_WIDTH-1:0]                    provider_id, alt_id, alloc_id;
    logic [MAX_IDX_WIDTH-1:0]               provider_idx, alt_idx, alloc_idx;
    logic [TAG_CTR_W-1:0]                   provider_ctr, alt_ctr, alloc_ctr;
    logic [TAG_USE_W-1:0]                   provider_useful, alt_useful, alloc_useful;
    logic [MAX_TAG_WIDTH-1:0]               provider_tag, alt_tag, alloc_tag;

    logic [BIMODAL_IDX_W-1:0]               bimodal_idx_raw;
    logic [BIMODAL_IDX_W-1:0]               bimodal_idx_lookup;
    logic [BIMODAL_CTR_W-1:0]               bimodal_ctr;

    logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] hash_regs_raw;
    logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] hash_regs_lookup;
    logic [NUM_TABLES-1:0][MAX_IDX_WIDTH-1:0] tage_idx_raw;
    logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] tage_tag_raw;
    logic [NUM_TABLES-1:0][MAX_IDX_WIDTH-1:0] tage_idx_lookup_raw;
    logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] tage_tag_lookup_raw;

    logic [MAX_TAG_WIDTH-1:0]               tag_tables    [NUM_TABLES];
    logic [TAG_CTR_W-1:0]                   ctr_tables    [NUM_TABLES];
    logic [TAG_USE_W-1:0]                   useful_tables [NUM_TABLES];

    logic [NUM_TABLES-1:0]                      tage_hit;
    logic [NUM_TABLES-1:0][MAX_IDX_WIDTH-1:0]   tage_idx;
    logic [NUM_TABLES-1:0][TAG_CTR_W-1:0]       tage_ctr;
    logic [NUM_TABLES-1:0][TAG_USE_W-1:0]       tage_useful;
    logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0]   tage_tag;

    logic                                   alloc_vld;
    logic                                   do_alloc;
    logic [TAG_CTR_W-1:0]                   calc_provider_ctr;
    logic [TAG_USE_W-1:0]                   calc_provider_useful;
    logic [TAG_CTR_W-1:0]                   calc_alt_ctr;
    logic                                   predict_lookup_vld;
    logic                                   predict_decision_vld;
    logic                                   pred_taken_decision;
    logic                                   provider_weak_decision;
    logic                                   provider_pseudo_na;
    logic                                   alt_pred_decision;
    logic                                   use_alt_prediction;
    logic signed [USE_ALT_CTR_W-1:0]        use_alt_ctr;
    logic signed [USE_ALT_CTR_W-1:0]        use_alt_ctr_next;
    logic [15:0]                            alloc_lfsr;
    logic [ALLOC_FAIL_TICK_W-1:0]           alloc_fail_tick;
    logic                                   alloc_fail_dec_fire;

    logic [GHR_LEN-1:0]                     specu_ghr_lookup_raw;
    logic [GHR_LEN-1:0]                     specu_ghr_lookup_ctx;

    localparam int AGE_COUNTER_W = (AGE_INTERVAL <= 1) ? 1 : $clog2(AGE_INTERVAL);
    logic [AGE_COUNTER_W-1:0]               age_counter;
    logic                                   age_tick;
    logic                                   global_age_active;
    logic [AGE_SCAN_W-1:0]                  global_age_idx;

    tage_snap_t snap_in, snap_out;

    // =========================================================================
    // 快照解包
    // =========================================================================
    assign snap_in = tage_snap_t'(i_input_snap_bus);

    wire                     pred_taken_restore      = snap_in.pred_taken;
    wire                     actual_taken_restore    = i_actual_taken;

    wire [GHR_LEN-1:0]       ghr_restore             = snap_in.ghr;

    wire [MAX_TAG_WIDTH-1:0] provider_tag_restore    = snap_in.provider_tag;
    wire [MAX_IDX_WIDTH-1:0] provider_idx_restore    = snap_in.provider_idx;
    wire [TAG_CTR_W-1:0]     provider_ctr_restore    = snap_in.provider_ctr;
    wire [TAG_USE_W-1:0]     provider_useful_restore = snap_in.provider_useful;
    wire [ID_WIDTH-1:0]      provider_id_restore     = snap_in.provider_id;

    wire [MAX_TAG_WIDTH-1:0] alt_tag_restore         = snap_in.alt_tag;
    wire [MAX_IDX_WIDTH-1:0] alt_idx_restore         = snap_in.alt_idx;
    wire [TAG_CTR_W-1:0]     alt_ctr_restore         = snap_in.alt_ctr;
    wire [TAG_USE_W-1:0]     alt_useful_restore      = snap_in.alt_useful;
    wire [ID_WIDTH-1:0]      alt_id_restore          = snap_in.alt_id;

    wire [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] table_tag_restore    = snap_in.table_tag;
    wire [NUM_TABLES-1:0][TAG_USE_W-1:0]     table_useful_restore = snap_in.table_useful;
    wire [NUM_TABLES-1:0][TAG_CTR_W-1:0]     table_ctr_restore    = snap_in.table_ctr;
    wire [NUM_TABLES-1:0][MAX_IDX_WIDTH-1:0] table_idx_restore    = snap_in.table_idx;

    wire [MAX_TAG_WIDTH-1:0] alloc_tag_restore       = snap_in.alloc_tag;
    wire [TAG_USE_W-1:0]     alloc_useful_restore    = snap_in.alloc_useful;
    wire [TAG_CTR_W-1:0]     alloc_ctr_restore       = snap_in.alloc_ctr;
    wire [MAX_IDX_WIDTH-1:0] alloc_idx_restore       = snap_in.alloc_idx;
    wire [ID_WIDTH-1:0]      alloc_id_restore        = snap_in.alloc_id;
    
    wire                     alloc_vld_restore       = snap_in.alloc_vld;

    logic is_taken_vld;
    logic is_snap_vld;
    assign is_taken_vld = i_is_taken_vld;
    assign is_snap_vld  = i_is_snap_vld;

    wire update_vld      = is_taken_vld && is_snap_vld;
    wire pred_wrong_int  = update_vld && (pred_taken_restore != actual_taken_restore);
    
    assign o_pred_wrong = pred_wrong_int;   // 输出错误标志

    // =========================================================================
    // GHR 与双模态表
    // =========================================================================
    

	
    logic [GHR_LEN-1:0] commit_ghr_resolve;
    logic [GHR_LEN-1:0] specu_ghr_next;

    always_comb begin
        commit_ghr_resolve = {ghr_restore[GHR_LEN-2:0], actual_taken_restore};
        specu_ghr_lookup_raw = pred_wrong_int ? commit_ghr_resolve : specu_ghr;
        specu_ghr_next       = predict_decision_vld ? {specu_ghr_lookup_ctx[GHR_LEN-2:0], pred_taken_decision} :
                                                       specu_ghr_lookup_raw;
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            commit_ghr <= '0;
            specu_ghr  <= '0;
        end else begin
            if (update_vld)
                commit_ghr <= commit_ghr_resolve;
            if (pred_wrong_int || predict_decision_vld)
                specu_ghr <= specu_ghr_next;
        end
    end

    generate
        if (AGE_INTERVAL <= 0 || U_AGING_MODE == tage_pkg::AGE_MODE_NONE) begin : GEN_NO_AGING
            assign age_tick = 1'b0;
            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    age_counter       <= '0;
                    global_age_active <= 1'b0;
                    global_age_idx    <= '0;
                end else begin
                    age_counter       <= '0;
                    global_age_active <= 1'b0;
                    global_age_idx    <= '0;
                end
            end
        end else begin : GEN_USEFUL_AGING
            assign age_tick = (age_counter == AGE_INTERVAL-1);
            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    age_counter       <= '0;
                    global_age_active <= 1'b0;
                    global_age_idx    <= '0;
                end else begin
                    if (age_tick)
                        age_counter <= '0;
                    else
                        age_counter <= age_counter + 1'b1;

                    if (U_AGING_MODE == tage_pkg::AGE_MODE_GLOBAL_SHIFT) begin
                        if (age_tick && !global_age_active) begin
                            global_age_active <= 1'b1;
                            global_age_idx    <= '0;
                        end else if (global_age_active) begin
                            if (global_age_idx == U_RESET_SCAN_ENTRIES-1) begin
                                global_age_active <= 1'b0;
                                global_age_idx    <= '0;
                            end else begin
                                global_age_idx <= global_age_idx + 1'b1;
                            end
                        end
                    end else begin
                        global_age_active <= 1'b0;
                        global_age_idx    <= '0;
                    end
                end
            end
        end
    endgenerate






    function automatic logic signed [USE_ALT_CTR_W-1:0] sat_signed_update(
        input logic signed [USE_ALT_CTR_W-1:0] ctr,
        input logic                            inc
    );
        int signed tmp;
        int signed max_v;
        int signed min_v;
        begin
            tmp   = ctr;
            max_v = (1 <<< (USE_ALT_CTR_W-1)) - 1;
            min_v = -(1 <<< (USE_ALT_CTR_W-1));
            if (inc) begin
                if (tmp < max_v)
                    tmp = tmp + 1;
            end else begin
                if (tmp > min_v)
                    tmp = tmp - 1;
            end
            sat_signed_update = tmp[USE_ALT_CTR_W-1:0];
        end
    endfunction

    function automatic logic [TAG_CTR_W-1:0] sat_ctr_update(
        input logic [TAG_CTR_W-1:0] ctr,
        input logic                 taken
    );
        begin
            if (taken)
                sat_ctr_update = (ctr != {TAG_CTR_W{1'b1}}) ? ctr + 1'b1 : ctr;
            else
                sat_ctr_update = (ctr != '0) ? ctr - 1'b1 : ctr;
        end
    endfunction

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            use_alt_ctr     <= USE_ALT_CTR_INIT[USE_ALT_CTR_W-1:0];
            alloc_lfsr      <= 16'hace1;
            alloc_fail_tick <= '0;
        end else begin
            use_alt_ctr <= use_alt_ctr_next;
            if (predict_decision_vld || update_vld)
                alloc_lfsr <= {alloc_lfsr[14:0],
                               alloc_lfsr[15] ^ alloc_lfsr[13] ^ alloc_lfsr[12] ^ alloc_lfsr[10]};
            if (update_vld && do_alloc && !alloc_vld_restore) begin
                if (alloc_fail_tick != {ALLOC_FAIL_TICK_W{1'b1}})
                    alloc_fail_tick <= alloc_fail_tick + 1'b1;
            end else if (update_vld && do_alloc && alloc_vld_restore) begin
                if (alloc_fail_tick != '0)
                    alloc_fail_tick <= alloc_fail_tick - 1'b1;
            end
        end
    end

    assign alloc_fail_dec_fire = ALLOC_FAIL_DEC_U &&
                                 (alloc_lfsr[ALLOC_FAIL_TICK_W-1:0] <= alloc_fail_tick);

    function automatic logic [BIMODAL_IDX_W-1:0] fold_pc_bimodal(input logic [31:0] pc);
        fold_pc_bimodal = '0;
        for (int b = 2; b < 32; b++)
            fold_pc_bimodal[(b-2) % BIMODAL_IDX_W] = fold_pc_bimodal[(b-2) % BIMODAL_IDX_W] ^ pc[b];
    endfunction

    assign bimodal_idx_raw = fold_pc_bimodal(i_pc);

    logic [BIMODAL_CTR_W-1:0] bimodal_wr_data;
    logic [BIMODAL_IDX_W-1:0] bimodal_wr_addr;
    logic                     bimodal_wr_en;
    logic                     bimodal_wr_provider;
    logic                     bimodal_wr_alt;
    logic [BIMODAL_CTR_W-1:0] bimodal_wr_src_ctr;

    always_comb begin
        bimodal_wr_addr    = bimodal_wr_alt ? alt_idx_restore[BIMODAL_IDX_W-1:0] :
                                             provider_idx_restore[BIMODAL_IDX_W-1:0];
        bimodal_wr_src_ctr = bimodal_wr_alt ? alt_ctr_restore[BIMODAL_CTR_W-1:0] :
                                             provider_ctr_restore[BIMODAL_CTR_W-1:0];
        if (actual_taken_restore)
            bimodal_wr_data = (bimodal_wr_src_ctr != {BIMODAL_CTR_W{1'b1}}) ? bimodal_wr_src_ctr + 1'b1 : bimodal_wr_src_ctr;
        else
            bimodal_wr_data = (bimodal_wr_src_ctr != 0) ? bimodal_wr_src_ctr - 1'b1 : bimodal_wr_src_ctr;
    end
    assign bimodal_wr_provider = update_vld && (provider_id_restore == NUM_TABLES);
    assign bimodal_wr_alt      = update_vld && UPDATE_ALT_ON_U_ZERO &&
                                 (provider_id_restore != NUM_TABLES) &&
                                 (provider_useful_restore == '0) &&
                                 (alt_id_restore == NUM_TABLES);
    assign bimodal_wr_en = bimodal_wr_provider || bimodal_wr_alt;

    tage_ram_wr #(
        .DEPTH(BIMODAL_SIZE),
        .WIDTH(BIMODAL_CTR_W)
    ) ram_wr_inst_bimodal (
        .i_clk     (i_clk),
        .i_wr_en   (bimodal_wr_en),
        .i_wr_addr (bimodal_wr_addr),
        .i_wr_data (bimodal_wr_data),
        .i_rd_addr (bimodal_idx_lookup),
        .o_rd_data (bimodal_ctr),
        .i_age_rd_addr('0),
        .o_age_rd_data()
    );

    generate
        if (PREDICT_LATENCY == 0) begin : GEN_LOOKUP_DIRECT
            assign predict_lookup_vld  = i_predict_vld;
            assign bimodal_idx_lookup  = bimodal_idx_raw;
            assign specu_ghr_lookup_ctx = specu_ghr_lookup_raw;
            assign tage_idx_lookup_raw = tage_idx_raw;
            assign tage_tag_lookup_raw = tage_tag_raw;
            assign hash_regs_lookup    = hash_regs_raw;
            assign predict_decision_vld = i_predict_vld;
        end else begin : GEN_LOOKUP_REGISTERED
            logic lookup_vld_q;
            logic [BIMODAL_IDX_W-1:0]                 bimodal_idx_q;
            logic [GHR_LEN-1:0]                       specu_ghr_lookup_q;
            logic [NUM_TABLES-1:0][MAX_IDX_WIDTH-1:0] tage_idx_q;
            logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] tage_tag_q;
            logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] hash_regs_q;

            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    lookup_vld_q       <= 1'b0;
                    bimodal_idx_q      <= '0;
                    specu_ghr_lookup_q <= '0;
                    tage_idx_q         <= '0;
                    tage_tag_q         <= '0;
                    hash_regs_q        <= '0;
                end else begin
                    lookup_vld_q       <= pred_wrong_int ? 1'b0 : i_predict_vld;
                    bimodal_idx_q      <= bimodal_idx_raw;
                    specu_ghr_lookup_q <= specu_ghr_lookup_raw;
                    tage_idx_q         <= tage_idx_raw;
                    tage_tag_q         <= tage_tag_raw;
                    hash_regs_q        <= hash_regs_raw;
                end
            end

            assign predict_lookup_vld   = lookup_vld_q;
            assign bimodal_idx_lookup   = bimodal_idx_q;
            assign specu_ghr_lookup_ctx = specu_ghr_lookup_q;
            assign tage_idx_lookup_raw  = tage_idx_q;
            assign tage_tag_lookup_raw  = tage_tag_q;
            assign hash_regs_lookup     = hash_regs_q;
            assign predict_decision_vld = lookup_vld_q && !pred_wrong_int;
        end
    endgenerate;

    // =========================================================================
    // TAGE 表 generate 块
    // =========================================================================
    generate
        for (genvar t = 0; t < NUM_TABLES; t++) begin : GEN_TAGE_TABLE_PRED
            localparam int V_HIST_LEN   = HIST_LENS_LUT[(NUM_TABLES-t)*32-1 -: 32];
            localparam int V_ENTRIES    = TABLE_ENTRIES_LUT[(NUM_TABLES-t)*32-1 -: 32];
            localparam int V_TAG_WIDTH  = TAG_WIDTH_LUT[(NUM_TABLES-t)*8-1 -: 8];
            localparam int V_IDX_WIDTH  = $clog2(V_ENTRIES);
            localparam int V_RAM_WIDTH  = TAG_CTR_W + TAG_USE_W + V_TAG_WIDTH;

            wire   [V_TAG_WIDTH-1:0] local_hash_restore = snap_in.hash_regs[t][V_TAG_WIDTH-1:0];

            logic [V_TAG_WIDTH-1:0] commit_hash_reg;
            logic [V_TAG_WIDTH-1:0] specu_hash_reg;
            logic [V_TAG_WIDTH-1:0] commit_hash_resolve;
            logic [V_TAG_WIDTH-1:0] specu_hash_lookup_raw;
            logic [V_TAG_WIDTH-1:0] specu_hash_lookup_ctx;
            logic [V_TAG_WIDTH-1:0] specu_hash_next;

            function automatic logic [V_TAG_WIDTH-1:0] fold_hash(
                input logic [V_TAG_WIDTH-1:0] curr_hash,
                input logic                   drop_bit,
                input logic                   bit_in
            );
                if (((V_HIST_LEN / V_TAG_WIDTH) % 2) == 0) begin
                    fold_hash = { curr_hash[V_TAG_WIDTH-2:0],
                                  curr_hash[V_TAG_WIDTH-1] ^ drop_bit ^ bit_in };
                end else begin
                    fold_hash = { curr_hash[V_TAG_WIDTH-2:0],
                                  curr_hash[V_TAG_WIDTH-1] ^ curr_hash[0] ^ drop_bit ^ bit_in };
                end
            endfunction

            function automatic logic [V_IDX_WIDTH-1:0] fold_pc_idx(input logic [31:0] pc);
                fold_pc_idx = '0;
                for (int b = 2; b < 32; b++)
                    fold_pc_idx[(b-2) % V_IDX_WIDTH] = fold_pc_idx[(b-2) % V_IDX_WIDTH] ^ pc[b];
            endfunction

            function automatic logic [V_TAG_WIDTH-1:0] fold_pc_tag(input logic [31:0] pc);
                fold_pc_tag = '0;
                for (int b = 2; b < 32; b++)
                    fold_pc_tag[(b-2) % V_TAG_WIDTH] = fold_pc_tag[(b-2) % V_TAG_WIDTH] ^ pc[b];
            endfunction

            assign commit_hash_resolve = fold_hash(local_hash_restore,
                                                    ghr_restore[V_HIST_LEN-1],
                                                    actual_taken_restore);
            assign specu_hash_lookup_raw = pred_wrong_int ? commit_hash_resolve : specu_hash_reg;
            assign specu_hash_lookup_ctx = hash_regs_lookup[t][V_TAG_WIDTH-1:0];
            assign specu_hash_next       = predict_decision_vld ? fold_hash(specu_hash_lookup_ctx,
                                                                            specu_ghr_lookup_ctx[V_HIST_LEN-1],
                                                                            pred_taken_decision) :
                                                                  specu_hash_lookup_raw;

            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    commit_hash_reg <= '0;
                    specu_hash_reg  <= '0;
                end else begin
                    if (update_vld)
                        commit_hash_reg <= commit_hash_resolve;
                    if (pred_wrong_int || predict_decision_vld)
                        specu_hash_reg <= specu_hash_next;
                end
            end

            logic [V_IDX_WIDTH-1:0] local_idx_raw;
            logic [V_TAG_WIDTH-1:0] local_tag_raw;
            logic [V_IDX_WIDTH-1:0] local_idx_lookup;
            logic [V_TAG_WIDTH-1:0] local_tag_lookup;
            logic [V_IDX_WIDTH-1:0] local_pc_idx_fold;
            logic [V_TAG_WIDTH-1:0] local_pc_tag_fold;
            assign local_pc_idx_fold = fold_pc_idx(i_pc);
            assign local_pc_tag_fold = fold_pc_tag(i_pc);
            assign local_idx_raw = local_pc_idx_fold ^ specu_hash_lookup_raw[V_IDX_WIDTH-1:0];
            assign local_tag_raw = local_pc_tag_fold ^ specu_hash_lookup_raw;
            assign local_idx_lookup = tage_idx_lookup_raw[t][V_IDX_WIDTH-1:0];
            assign local_tag_lookup = tage_tag_lookup_raw[t][V_TAG_WIDTH-1:0];

            wire [MAX_IDX_WIDTH-1:0] table_idx = {{(MAX_IDX_WIDTH-V_IDX_WIDTH){1'b0}}, local_idx_raw};
            wire [MAX_IDX_WIDTH-1:0] table_idx_lookup = {{(MAX_IDX_WIDTH-V_IDX_WIDTH){1'b0}}, local_idx_lookup};

            wire [V_RAM_WIDTH-1:0] ram_data;
            wire [V_RAM_WIDTH-1:0]    age_ram_data;
            logic                     wr_provider_en_local;
            logic                     wr_alt_en_local;
            logic                     wr_alloc_en_local;
            logic                     wr_alloc_fail_dec_en_local;
            logic                     wr_touched_age_en_local;
            logic                     wr_global_age_en_local;
            logic                     wr_age_en_local;
            logic                     wr_en_local;
            logic [V_IDX_WIDTH-1:0]   wr_addr_local;
            logic [V_RAM_WIDTH-1:0]   wr_data_local;
            logic [V_IDX_WIDTH-1:0]   age_rd_addr_local;
            wire [V_TAG_WIDTH-1:0]    raw_sampled_tag;
            wire [TAG_CTR_W-1:0]      raw_sampled_ctr;
            wire [TAG_USE_W-1:0]      raw_sampled_useful;
            wire [V_TAG_WIDTH-1:0]    raw_age_tag;
            wire [TAG_CTR_W-1:0]      raw_age_ctr;
            wire [TAG_USE_W-1:0]      raw_age_useful;

            logic [TAG_CTR_W-1:0] init_alloc_ctr;

            assign init_alloc_ctr = actual_taken_restore ? {1'b1,{(TAG_CTR_W-1){1'b0}}} : { 1'b0, {(TAG_CTR_W-1){1'b1}}};

            assign wr_provider_en_local = update_vld && (t == provider_id_restore);
            assign wr_alt_en_local = update_vld && UPDATE_ALT_ON_U_ZERO &&
                                     (provider_id_restore != NUM_TABLES) &&
                                     (provider_useful_restore == '0) &&
                                     (t == alt_id_restore);
            assign wr_alloc_en_local = update_vld && do_alloc && alloc_vld_restore &&
                                       (t == alloc_id_restore);
            assign wr_alloc_fail_dec_en_local = update_vld && do_alloc && !alloc_vld_restore &&
                                                alloc_fail_dec_fire &&
                                                (provider_id_restore == NUM_TABLES || t > provider_id_restore) &&
                                                (table_useful_restore[t] != '0);
            assign wr_touched_age_en_local = (U_AGING_MODE == tage_pkg::AGE_MODE_TOUCHED_DEC) &&
                                             age_tick && predict_lookup_vld &&
                                             !(wr_provider_en_local || wr_alt_en_local ||
                                               wr_alloc_en_local || wr_alloc_fail_dec_en_local) &&
                                             (raw_sampled_useful != '0);
            assign wr_global_age_en_local = (U_AGING_MODE == tage_pkg::AGE_MODE_GLOBAL_SHIFT) &&
                                            global_age_active &&
                                            (global_age_idx < V_ENTRIES) &&
                                            !(wr_provider_en_local || wr_alt_en_local ||
                                              wr_alloc_en_local || wr_alloc_fail_dec_en_local) &&
                                            (raw_age_useful != '0);
            assign wr_age_en_local = wr_touched_age_en_local || wr_global_age_en_local;
            assign wr_en_local = wr_provider_en_local || wr_alt_en_local ||
                                 wr_alloc_en_local || wr_alloc_fail_dec_en_local ||
                                 wr_age_en_local;

            assign wr_addr_local = wr_provider_en_local       ? provider_idx_restore[V_IDX_WIDTH-1:0] :
                                   wr_alt_en_local            ? alt_idx_restore[V_IDX_WIDTH-1:0] :
                                   wr_alloc_en_local          ? alloc_idx_restore[V_IDX_WIDTH-1:0] :
                                   wr_alloc_fail_dec_en_local ? table_idx_restore[t][V_IDX_WIDTH-1:0] :
                                   wr_global_age_en_local     ? global_age_idx[V_IDX_WIDTH-1:0] :
                                                                local_idx_lookup;

            assign wr_data_local = wr_provider_en_local       ? { provider_tag_restore[V_TAG_WIDTH-1:0],
                                                                  calc_provider_ctr,
                                                                  calc_provider_useful } :
                                   wr_alt_en_local            ? { alt_tag_restore[V_TAG_WIDTH-1:0],
                                                                  calc_alt_ctr,
                                                                  alt_useful_restore } :
                                   wr_alloc_en_local          ? { alloc_tag_restore[V_TAG_WIDTH-1:0],
                                                                  init_alloc_ctr,
                                                                  {TAG_USE_W{1'b0}} } :
                                   wr_alloc_fail_dec_en_local ? { table_tag_restore[t][V_TAG_WIDTH-1:0],
                                                                  table_ctr_restore[t],
                                                                  table_useful_restore[t] - 1'b1 } :
                                   wr_global_age_en_local     ? { raw_age_tag,
                                                                  raw_age_ctr,
                                                                  raw_age_useful >> 1 } :
                                                                { raw_sampled_tag,
                                                                  raw_sampled_ctr,
                                                                  raw_sampled_useful - 1'b1 };
            assign age_rd_addr_local = global_age_idx[V_IDX_WIDTH-1:0];

            tage_ram_wr #(
                .DEPTH(V_ENTRIES),
                .WIDTH(V_RAM_WIDTH)
            ) ram_wr_inst (
                .i_clk     (i_clk),
                .i_wr_en   (wr_en_local),
                .i_wr_addr (wr_addr_local),
                .i_wr_data (wr_data_local),
                .i_rd_addr (local_idx_lookup),
                .o_rd_data (ram_data),
                .i_age_rd_addr(age_rd_addr_local),
                .o_age_rd_data(age_ram_data)
            );

            assign raw_sampled_tag    = ram_data[V_RAM_WIDTH-1 -: V_TAG_WIDTH];
            assign raw_sampled_ctr    = ram_data[TAG_CTR_W+TAG_USE_W-1 -: TAG_CTR_W];
            assign raw_sampled_useful = ram_data[TAG_USE_W-1:0];
            assign raw_age_tag        = age_ram_data[V_RAM_WIDTH-1 -: V_TAG_WIDTH];
            assign raw_age_ctr        = age_ram_data[TAG_CTR_W+TAG_USE_W-1 -: TAG_CTR_W];
            assign raw_age_useful     = age_ram_data[TAG_USE_W-1:0];

            assign tag_tables[t]    = {{(MAX_TAG_WIDTH-V_TAG_WIDTH){1'b0}}, raw_sampled_tag};
            assign ctr_tables[t]    = raw_sampled_ctr;
            assign useful_tables[t] = raw_sampled_useful;

            wire hit;
            assign hit = predict_lookup_vld && (tag_tables[t] == local_tag_lookup);

            assign tage_hit[t]       = hit;
            assign tage_idx[t]       = table_idx_lookup;
            assign tage_ctr[t]       = ctr_tables[t];
            assign tage_useful[t]    = useful_tables[t];
            assign tage_tag[t]       = {{(MAX_TAG_WIDTH-V_TAG_WIDTH){1'b0}}, local_tag_lookup};
            assign tage_idx_raw[t]   = table_idx;
            assign tage_tag_raw[t]   = {{(MAX_TAG_WIDTH-V_TAG_WIDTH){1'b0}}, local_tag_raw};
            assign hash_regs_raw[t]  = {{(MAX_TAG_WIDTH-V_TAG_WIDTH){1'b0}}, specu_hash_lookup_raw};
        end
    endgenerate

    // =========================================================================
    // Provider / Alt / Alloc 分配
    // =========================================================================
    always_comb begin
        int alloc_base;
        int alloc_start;
        int alloc_offset;

        provider_id     = NUM_TABLES;
        provider_tag    = '0;
        provider_idx    = bimodal_idx_lookup;
        provider_ctr    = bimodal_ctr;
        provider_useful = '0;

        alt_id          = NUM_TABLES;
        alt_tag         = '0;
        alt_idx         = bimodal_idx_lookup;
        alt_ctr         = bimodal_ctr;
        alt_useful      = '0;

        alloc_id         = NUM_TABLES;
        alloc_tag        = '0;
        alloc_idx        = '0;
        alloc_ctr        = '0;
        alloc_useful     = '0;
        alloc_vld        = 1'b0;
        alloc_base       = (provider_id == NUM_TABLES) ? 0 : provider_id + 1;
        alloc_offset     = alloc_lfsr[0] + (alloc_lfsr[0] & alloc_lfsr[1]);
        alloc_start      = alloc_base;

        // 寻找 provider 和 alt（命中表，优先选索引大的作为 provider，次大作为 alt）
        for (int i = NUM_TABLES-1; i >= 0; i--) begin
            if (tage_hit[i]) begin
                if (provider_id == NUM_TABLES) begin
                    provider_id     = i;
                    provider_tag    = tage_tag[i];
                    provider_idx    = tage_idx[i];
                    provider_ctr    = tage_ctr[i];
                    provider_useful = tage_useful[i];
                end else if (alt_id == NUM_TABLES) begin
                    alt_id          = i;
                    alt_tag         = tage_tag[i];
                    alt_idx         = tage_idx[i];
                    alt_ctr         = tage_ctr[i];
                    alt_useful      = tage_useful[i];
                end
            end
        end

        alloc_base  = (provider_id == NUM_TABLES) ? 0 : provider_id + 1;
        alloc_start = alloc_base;
        if (ALLOC_POLICY == tage_pkg::ALLOC_POLICY_LFSR_START) begin
            alloc_start = alloc_base + alloc_offset;
            if (alloc_start >= NUM_TABLES)
                alloc_start = NUM_TABLES - 1;
        end

        // 分配候选：useful == 0 的表，且必须比当前 provider 的历史长度更长
        // 修正：若 provider 为双模态表（provider_id == NUM_TABLES），则任何 TAGE 表均可分配
        for (int i = 0; i < NUM_TABLES; i++) begin
            if (tage_useful[i] == '0 && 
                (i >= alloc_start) &&
                (provider_id == NUM_TABLES || i > provider_id) &&
                alloc_id == NUM_TABLES) begin
                alloc_id     = i;
                alloc_tag    = tage_tag[i];
                alloc_idx    = tage_idx[i];
                alloc_ctr    = tage_ctr[i];
                alloc_useful = tage_useful[i];
                alloc_vld    = 1'b1;
            end
        end
    end

    // =========================================================================
    // 预测输出
    // =========================================================================
    assign provider_weak_decision = (provider_ctr == {1'b0, {(TAG_CTR_W-1){1'b1}}}) ||
                                    (provider_ctr == {1'b1, {(TAG_CTR_W-1){1'b0}}});
    assign provider_pseudo_na = (provider_id != NUM_TABLES) &&
                                provider_weak_decision &&
                                (!USE_ALT_REQUIRE_U_ZERO || provider_useful == '0);
    assign alt_pred_decision = (alt_id == NUM_TABLES) ? bimodal_ctr[BIMODAL_CTR_W-1] :
                                                       alt_ctr[TAG_CTR_W-1];
    assign use_alt_prediction = USE_ALT_ON_NA && provider_pseudo_na && (use_alt_ctr >= 0);

    always_comb begin
        if (use_alt_prediction)
            pred_taken_decision = alt_pred_decision;
        else if (provider_id == NUM_TABLES)
            pred_taken_decision = bimodal_ctr[BIMODAL_CTR_W-1];
        else
            pred_taken_decision = provider_ctr[TAG_CTR_W-1];
    end

    // =========================================================================
    // 快照打包
    // =========================================================================
    always_comb begin
        snap_out.pred_taken          = pred_taken_decision;
        snap_out.actual_taken        = 1'b0;
        
        snap_out.ghr                 = specu_ghr_lookup_ctx;
        snap_out.provider_tag        = provider_tag;
        snap_out.provider_idx        = provider_idx;
        snap_out.provider_ctr        = provider_ctr;
        snap_out.provider_useful     = provider_useful;
        snap_out.provider_id         = provider_id;
        snap_out.alt_tag             = alt_tag;
        snap_out.alt_idx             = alt_idx;
        snap_out.alt_ctr             = alt_ctr;
        snap_out.alt_useful          = alt_useful;
        snap_out.alt_id              = alt_id;
        snap_out.alloc_tag           = alloc_tag;
        snap_out.alloc_useful        = alloc_useful;
        snap_out.alloc_ctr           = alloc_ctr;
        snap_out.alloc_idx           = alloc_idx;
        snap_out.alloc_id            = alloc_id;
        snap_out.alloc_vld           = alloc_vld;
        
        for (int t = 0; t < NUM_TABLES; t++) begin
            snap_out.hash_regs[t]    = hash_regs_lookup[t];
            snap_out.table_tag[t]     = tag_tables[t];
            snap_out.table_idx[t]     = tage_idx[t];
            snap_out.table_ctr[t]     = tage_ctr[t];
            snap_out.table_useful[t]  = tage_useful[t];
        end
    end

    generate
        if (PREDICT_LATENCY == 2) begin : GEN_OUTPUT_REGISTER
            logic pred_vld_q;
            logic pred_taken_q;
            logic [$bits(tage_pkg::tage_snap_t)-1:0] snap_bus_q;

            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    pred_vld_q   <= 1'b0;
                    pred_taken_q <= 1'b0;
                    snap_bus_q   <= '0;
                end else if (pred_wrong_int) begin
                    pred_vld_q   <= 1'b0;
                    pred_taken_q <= 1'b0;
                    snap_bus_q   <= '0;
                end else begin
                    pred_vld_q   <= predict_decision_vld;
                    pred_taken_q <= pred_taken_decision;
                    snap_bus_q   <= snap_out;
                end
            end

            assign o_pred_vld         = pred_vld_q;
            assign o_pred_taken       = pred_taken_q;
            assign o_output_snap_bus  = snap_bus_q;
        end else begin : GEN_OUTPUT_DIRECT
            assign o_pred_vld         = predict_decision_vld;
            assign o_pred_taken       = pred_taken_decision;
            assign o_output_snap_bus  = snap_out;
        end
    endgenerate

    // =========================================================================
    // 更新路径组合逻辑
    // =========================================================================
    wire provider_pred_dir = provider_ctr_restore[TAG_CTR_W-1];
    wire provider_wrong    = (provider_pred_dir != actual_taken_restore);
    wire alt_pred_dir      = alt_ctr_restore[TAG_CTR_W-1];
    wire alt_wrong         = (alt_pred_dir != actual_taken_restore);

    always_comb begin
        use_alt_ctr_next = use_alt_ctr;
        if (update_vld &&
            USE_ALT_ON_NA &&
            provider_id_restore != NUM_TABLES &&
            ((provider_ctr_restore == {1'b0, {(TAG_CTR_W-1){1'b1}}}) ||
             (provider_ctr_restore == {1'b1, {(TAG_CTR_W-1){1'b0}}})) &&
            (!USE_ALT_REQUIRE_U_ZERO || provider_useful_restore == '0) &&
            (provider_pred_dir != alt_pred_dir)) begin
            use_alt_ctr_next = sat_signed_update(use_alt_ctr, alt_pred_dir == actual_taken_restore);
        end
    end

    always_comb begin
        calc_provider_ctr    = provider_ctr_restore;
        calc_provider_useful = provider_useful_restore;
        calc_alt_ctr         = alt_ctr_restore;
        do_alloc             = 1'b0;

        calc_provider_ctr = sat_ctr_update(provider_ctr_restore, actual_taken_restore);
        calc_alt_ctr      = sat_ctr_update(alt_ctr_restore, actual_taken_restore);

        if (provider_pred_dir != alt_pred_dir) begin
            if (!provider_wrong)
                calc_provider_useful = (provider_useful_restore != {TAG_USE_W{1'b1}}) ? provider_useful_restore + 1'b1 : provider_useful_restore;
            else
                calc_provider_useful = (provider_useful_restore != 0) ? provider_useful_restore - 1'b1 : provider_useful_restore;
        end

        case ({pred_wrong_int, provider_wrong, alt_wrong})
            3'b110, 3'b111: do_alloc = 1'b1;
            default:        do_alloc = 1'b0;
        endcase
    end

endmodule
