// =========================================================================
// TAGE 共用类型定义及全局参数（含 LUT）
// =========================================================================

package tage_pkg;

    // Default profile: one bimodal base table plus five tagged TAGE tables.
    // Tagged table order is T1..T5, with monotonically increasing history.
    parameter int GHR_LEN          = 130;
    parameter int BIMODAL_SIZE     = 2048;
    parameter int BIMODAL_CTR_W    = 3;      
    parameter int NUM_TABLES       = 5;      
    parameter int TAG_CTR_W        = 3;
    parameter int TAG_USE_W        = 2;
    localparam int ID_WIDTH        = $clog2(NUM_TABLES+1);
    localparam int MAX_IDX_WIDTH   = 11;
    localparam int MAX_TAG_WIDTH   = 12;
    localparam int MAX_TAGGED_ENTRIES = 512;

    localparam int AGE_MODE_NONE         = 0;
    localparam int AGE_MODE_TOUCHED_DEC  = 1;
    localparam int AGE_MODE_GLOBAL_SHIFT = 2;

    localparam int ALLOC_POLICY_FIRST       = 0;
    localparam int ALLOC_POLICY_LFSR_START  = 1;

    parameter int U_AGING_MODE          = AGE_MODE_TOUCHED_DEC;
    parameter int U_RESET_SCAN_ENTRIES  = MAX_TAGGED_ENTRIES;
    parameter bit USE_ALT_ON_NA         = 1'b0;
    parameter int USE_ALT_CTR_W         = 4;
    parameter int USE_ALT_CTR_INIT      = 0;
    parameter bit USE_ALT_REQUIRE_U_ZERO = 1'b1;
    parameter bit UPDATE_ALT_ON_U_ZERO  = 1'b1;
    parameter int ALLOC_POLICY          = ALLOC_POLICY_FIRST;
    parameter bit ALLOC_FAIL_DEC_U      = 1'b1;
    parameter int ALLOC_FAIL_TICK_W     = 4;

    // 各 tagged 表配置 LUT，按 T1..T5 自然顺序书写。
    // Core 中表号越大表示历史越长，用于 provider/alloc 优先级。
    parameter bit [NUM_TABLES*32-1:0] HIST_LENS_LUT = {
        32'd6, 32'd13, 32'd27, 32'd56, 32'd130
    };

    parameter bit [NUM_TABLES*32-1:0] TABLE_ENTRIES_LUT = {
        32'd512, 32'd512, 32'd256, 32'd256, 32'd128
    };

    parameter bit [NUM_TABLES*8-1:0]  TAG_WIDTH_LUT = {
        8'd9, 8'd9, 8'd9, 8'd10, 8'd12
    };

    // ========================================================================
    // 新增结构体：不需要放入延迟线的决策信息（provider/alt/alloc）
    // ========================================================================
    typedef struct packed {
        logic [MAX_TAG_WIDTH-1:0] alt_tag;
        logic [TAG_USE_W-1:0]     alt_useful;
        logic [TAG_CTR_W-1:0]     alt_ctr;
        logic [MAX_IDX_WIDTH-1:0] alt_idx;
        logic [ID_WIDTH-1:0]      alt_id;

        logic [MAX_TAG_WIDTH-1:0] provider_tag;
        logic [TAG_USE_W-1:0]     provider_useful;
        logic [TAG_CTR_W-1:0]     provider_ctr;
        logic [MAX_IDX_WIDTH-1:0] provider_idx;
        logic [ID_WIDTH-1:0]      provider_id;

        logic [MAX_TAG_WIDTH-1:0] alloc_tag;
        logic [TAG_USE_W-1:0]     alloc_useful;
        logic [TAG_CTR_W-1:0]     alloc_ctr;
        logic [MAX_IDX_WIDTH-1:0] alloc_idx;
        logic [ID_WIDTH-1:0]      alloc_id;
        logic                     alloc_vld;
        
    } tage_decision_t;

    // ========================================================================
    // 新增结构体：需要放入延迟线的预测状态（GHR + hash 寄存器）
    // ========================================================================
    typedef struct packed {
        logic                                     pred_taken;
        logic                                     actual_taken;
        logic [GHR_LEN-1:0]                       ghr;
        logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] hash_regs;
    } tage_state_t;

    // ========================================================================
    // 原始完整快照（保持兼容，可基于上述两个结构体组合，但为不改动 core 保留原样）
    // ========================================================================
    typedef struct packed {
        logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] hash_regs;
        logic [MAX_TAG_WIDTH-1:0]                 alt_tag;
        logic [TAG_USE_W-1:0]                     alt_useful;
        logic [TAG_CTR_W-1:0]                     alt_ctr;
        logic [MAX_IDX_WIDTH-1:0]                 alt_idx;
        logic [ID_WIDTH-1:0]                      alt_id;
        logic [NUM_TABLES-1:0][MAX_TAG_WIDTH-1:0] table_tag;
        logic [NUM_TABLES-1:0][TAG_USE_W-1:0]     table_useful;
        logic [NUM_TABLES-1:0][TAG_CTR_W-1:0]     table_ctr;
        logic [NUM_TABLES-1:0][MAX_IDX_WIDTH-1:0] table_idx;
        logic [MAX_TAG_WIDTH-1:0]                 provider_tag;
        logic [TAG_USE_W-1:0]                     provider_useful;
        logic [TAG_CTR_W-1:0]                     provider_ctr;
        logic [MAX_IDX_WIDTH-1:0]                 provider_idx;
        logic [ID_WIDTH-1:0]                      provider_id;
        logic [MAX_TAG_WIDTH-1:0]                 alloc_tag;
        logic [TAG_USE_W-1:0]                     alloc_useful;
        logic [TAG_CTR_W-1:0]                     alloc_ctr;
        logic [MAX_IDX_WIDTH-1:0]                 alloc_idx;
        logic [ID_WIDTH-1:0]                      alloc_id;
        logic                                     alloc_vld;
        logic [GHR_LEN-1:0]                       ghr;
        logic                                     pred_taken;
        logic                                     actual_taken;
    } tage_snap_t;

endpackage
