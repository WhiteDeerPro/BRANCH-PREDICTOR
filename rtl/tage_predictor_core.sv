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

    logic [BIMODAL_IDX_W-1:0]               bimodal_idx;
    logic [BIMODAL_CTR_W-1:0]               bimodal_ctr;

    logic [MAX_TAG_WIDTH-1:0]               hash_regs_pack [NUM_TABLES];

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
    logic [GHR_LEN-1:0] specu_ghr_lookup;
    logic [GHR_LEN-1:0] specu_ghr_next;

    always_comb begin
        commit_ghr_resolve = {ghr_restore[GHR_LEN-2:0], actual_taken_restore};
        specu_ghr_lookup   = pred_wrong_int ? commit_ghr_resolve : specu_ghr;
        specu_ghr_next     = i_predict_vld ? {specu_ghr_lookup[GHR_LEN-2:0], o_pred_taken} :
                                             specu_ghr_lookup;
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            commit_ghr <= '0;
            specu_ghr  <= '0;
        end else begin
            if (update_vld)
                commit_ghr <= commit_ghr_resolve;
            if (pred_wrong_int || i_predict_vld)
                specu_ghr <= specu_ghr_next;
        end
    end






    function automatic logic [BIMODAL_IDX_W-1:0] fold_pc_bimodal(input logic [31:0] pc);
        fold_pc_bimodal = '0;
        for (int b = 2; b < 32; b++)
            fold_pc_bimodal[(b-2) % BIMODAL_IDX_W] = fold_pc_bimodal[(b-2) % BIMODAL_IDX_W] ^ pc[b];
    endfunction

    assign bimodal_idx = fold_pc_bimodal(i_pc);

    logic [BIMODAL_CTR_W-1:0] bimodal_wr_data;
    logic [BIMODAL_IDX_W-1:0] bimodal_wr_addr;
    logic                     bimodal_wr_en;

    always_comb begin
        bimodal_wr_addr = provider_idx_restore[BIMODAL_IDX_W-1:0];
        if (actual_taken_restore)
            bimodal_wr_data = (provider_ctr_restore[BIMODAL_CTR_W-1:0] != {BIMODAL_CTR_W{1'b1}}) ? provider_ctr_restore[BIMODAL_CTR_W-1:0] + 1'b1 : provider_ctr_restore[BIMODAL_CTR_W-1:0];
        else
            bimodal_wr_data = (provider_ctr_restore[BIMODAL_CTR_W-1:0] != 0) ? provider_ctr_restore[BIMODAL_CTR_W-1:0] - 1'b1 : provider_ctr_restore[BIMODAL_CTR_W-1:0];
    end
    assign bimodal_wr_en = update_vld && (provider_id_restore == NUM_TABLES);

    tage_ram_wr #(
        .DEPTH(BIMODAL_SIZE),
        .WIDTH(BIMODAL_CTR_W)
    ) ram_wr_inst_bimodal (
        .i_clk     (i_clk),
        .i_wr_en   (bimodal_wr_en),
        .i_wr_addr (bimodal_wr_addr),
        .i_wr_data (bimodal_wr_data),
        .i_rd_addr (bimodal_idx),
        .o_rd_data (bimodal_ctr)
    );

    // =========================================================================
    // TAGE 表 generate 块
    // =========================================================================
    generate
        for (genvar t = 0; t < NUM_TABLES; t++) begin : GEN_TAGE_TABLE_PRED
            localparam int V_HIST_LEN   = HIST_LENS_LUT[(t+1)*32-1 -: 32];
            localparam int V_ENTRIES    = TABLE_ENTRIES_LUT[(t+1)*32-1 -: 32];
            localparam int V_TAG_WIDTH  = TAG_WIDTH_LUT[(t+1)*8-1 -: 8];
            localparam int V_IDX_WIDTH  = $clog2(V_ENTRIES);
            localparam int V_RAM_WIDTH  = TAG_CTR_W + TAG_USE_W + V_TAG_WIDTH;

            wire   [V_TAG_WIDTH-1:0] local_hash_restore = snap_in.hash_regs[t][V_TAG_WIDTH-1:0];

            logic [V_TAG_WIDTH-1:0] commit_hash_reg;
            logic [V_TAG_WIDTH-1:0] specu_hash_reg;
            logic [V_TAG_WIDTH-1:0] commit_hash_resolve;
            logic [V_TAG_WIDTH-1:0] specu_hash_lookup;
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
            assign specu_hash_lookup   = pred_wrong_int ? commit_hash_resolve : specu_hash_reg;
            assign specu_hash_next     = i_predict_vld ? fold_hash(specu_hash_lookup,
                                                                    specu_ghr_lookup[V_HIST_LEN-1],
                                                                    o_pred_taken) :
                                                        specu_hash_lookup;

            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    commit_hash_reg <= '0;
                    specu_hash_reg  <= '0;
                end else begin
                    if (update_vld)
                        commit_hash_reg <= commit_hash_resolve;
                    if (pred_wrong_int || i_predict_vld)
                        specu_hash_reg <= specu_hash_next;
                end
            end

            logic [V_IDX_WIDTH-1:0] local_idx_raw;
            logic [V_TAG_WIDTH-1:0] local_tag_raw;
            logic [V_IDX_WIDTH-1:0] local_pc_idx_fold;
            logic [V_TAG_WIDTH-1:0] local_pc_tag_fold;
            assign local_pc_idx_fold = fold_pc_idx(i_pc);
            assign local_pc_tag_fold = fold_pc_tag(i_pc);
            assign local_idx_raw = local_pc_idx_fold ^ specu_hash_lookup[V_IDX_WIDTH-1:0];
            assign local_tag_raw = local_pc_tag_fold ^ specu_hash_lookup;

            wire [MAX_IDX_WIDTH-1:0] table_idx = {{(MAX_IDX_WIDTH-V_IDX_WIDTH){1'b0}}, local_idx_raw};

            wire [V_RAM_WIDTH-1:0] ram_data;
            logic                     wr_en_local;
            logic [V_IDX_WIDTH-1:0]   wr_addr_local;
            logic [V_RAM_WIDTH-1:0]   wr_data_local;

            logic [TAG_CTR_W-1:0] init_alloc_ctr;

            assign init_alloc_ctr = actual_taken_restore ? {1'b1,{(TAG_CTR_W-1){1'b0}}} : { 1'b0, {(TAG_CTR_W-1){1'b1}}};

            assign wr_en_local = update_vld && ((t == provider_id_restore) ||
                                 (do_alloc && alloc_vld_restore && t == alloc_id_restore));

            assign wr_addr_local = (t == provider_id_restore)                     ? provider_idx_restore[V_IDX_WIDTH-1:0] :
                                   (t == alloc_id_restore && do_alloc && alloc_vld_restore) ? alloc_idx_restore[V_IDX_WIDTH-1:0] :
                                   '0;

            assign wr_data_local = (t == provider_id_restore)                     ? { provider_tag_restore[V_TAG_WIDTH-1:0],
                                                                                       calc_provider_ctr,
                                                                                       calc_provider_useful } :
                                   (t == alloc_id_restore && do_alloc && alloc_vld_restore) ? { alloc_tag_restore[V_TAG_WIDTH-1:0],
                                                                                       init_alloc_ctr,
                                                                                       {TAG_USE_W{1'b0}} } :
                                   '0;

            tage_ram_wr #(
                .DEPTH(V_ENTRIES),
                .WIDTH(V_RAM_WIDTH)
            ) ram_wr_inst (
                .i_clk     (i_clk),
                .i_wr_en   (wr_en_local),
                .i_wr_addr (wr_addr_local),
                .i_wr_data (wr_data_local),
                .i_rd_addr (local_idx_raw),
                .o_rd_data (ram_data)
            );

            wire [V_TAG_WIDTH-1:0] raw_sampled_tag;
            wire [TAG_CTR_W-1:0]   raw_sampled_ctr;
            wire [TAG_USE_W-1:0]   raw_sampled_useful;

            assign raw_sampled_tag    = ram_data[V_RAM_WIDTH-1 -: V_TAG_WIDTH];
            assign raw_sampled_ctr    = ram_data[TAG_CTR_W+TAG_USE_W-1 -: TAG_CTR_W];
            assign raw_sampled_useful = ram_data[TAG_USE_W-1:0];

            assign tag_tables[t]    = {{(MAX_TAG_WIDTH-V_TAG_WIDTH){1'b0}}, raw_sampled_tag};
            assign ctr_tables[t]    = raw_sampled_ctr;
            assign useful_tables[t] = raw_sampled_useful;

            wire hit;
            assign hit = (tag_tables[t] == local_tag_raw);

            assign tage_hit[t]       = hit;
            assign tage_idx[t]       = table_idx;
            assign tage_ctr[t]       = ctr_tables[t];
            assign tage_useful[t]    = useful_tables[t];
            assign tage_tag[t]       = {{(MAX_TAG_WIDTH-V_TAG_WIDTH){1'b0}}, local_tag_raw};
            assign hash_regs_pack[t]        = {{(MAX_TAG_WIDTH-V_TAG_WIDTH){1'b0}}, specu_hash_lookup};
        end
    endgenerate

    // =========================================================================
    // Provider / Alt / Alloc 分配
    // =========================================================================
    always_comb begin
        provider_id     = NUM_TABLES;
        provider_tag    = '0;
        provider_idx    = bimodal_idx;
        provider_ctr    = bimodal_ctr;
        provider_useful = '0;

        alt_id          = NUM_TABLES;
        alt_tag         = '0;
        alt_idx         = bimodal_idx;
        alt_ctr         = bimodal_ctr;
        alt_useful      = '0;

        alloc_id         = NUM_TABLES;
        alloc_tag        = '0;
        alloc_idx        = '0;
        alloc_ctr        = '0;
        alloc_useful     = '0;
        alloc_vld        = 1'b0;

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

        // 分配候选：useful == 0 的表，且必须比当前 provider 的历史长度更长
        // 修正：若 provider 为双模态表（provider_id == NUM_TABLES），则任何 TAGE 表均可分配
        for (int i = 0; i < NUM_TABLES; i++) begin
            if (tage_useful[i] == '0 && 
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
    always_comb begin
        if (provider_id == NUM_TABLES)
            o_pred_taken = bimodal_ctr[BIMODAL_CTR_W-1];
        else
            o_pred_taken = provider_ctr[TAG_CTR_W-1];
    end

    // =========================================================================
    // 快照打包
    // =========================================================================
    always_comb begin
        snap_out.pred_taken          = o_pred_taken;
        snap_out.actual_taken        = 1'b0;
        
        snap_out.ghr                 = specu_ghr_lookup;
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
        
        for (int t = 0; t < NUM_TABLES; t++)
            snap_out.hash_regs[t]    = hash_regs_pack[t];
    end
    assign o_output_snap_bus = snap_out;

    // =========================================================================
    // 更新路径组合逻辑
    // =========================================================================
    wire provider_pred_dir = provider_ctr_restore[TAG_CTR_W-1];
    wire provider_wrong    = (provider_pred_dir != actual_taken_restore);
    wire alt_pred_dir      = alt_ctr_restore[TAG_CTR_W-1];
    wire alt_wrong         = (alt_pred_dir != actual_taken_restore);

    always_comb begin
        calc_provider_ctr    = provider_ctr_restore;
        calc_provider_useful = provider_useful_restore;
        do_alloc             = 1'b0;

        if (actual_taken_restore)
            calc_provider_ctr = (provider_ctr_restore != {TAG_CTR_W{1'b1}}) ? provider_ctr_restore + 1'b1 : provider_ctr_restore;
        else
            calc_provider_ctr = (provider_ctr_restore != 0) ? provider_ctr_restore - 1'b1 : provider_ctr_restore;

        if (provider_wrong != alt_wrong) begin
            if (!pred_wrong_int)
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
