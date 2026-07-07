// =========================================================================
// TAGE 共用类型定义及全局参数（含 LUT）
// =========================================================================

package tage_pkg;

    parameter int GHR_LEN          = 120;
    parameter int BIMODAL_SIZE     = 1024;
    parameter int BIMODAL_CTR_W    = 3;      
    parameter int NUM_TABLES       = 5;      
    parameter int TAG_CTR_W        = 3;
    parameter int TAG_USE_W        = 2;
    localparam int ID_WIDTH        = $clog2(NUM_TABLES+1);
    localparam int MAX_IDX_WIDTH   = 10;
    localparam int MAX_TAG_WIDTH   = 12;

    // 各表配置 LUT
    parameter bit [NUM_TABLES*32-1:0] HIST_LENS_LUT = {
        32'd12, 32'd24, 32'd48, 32'd96, 32'd120
    };

    parameter bit [NUM_TABLES*32-1:0] TABLE_ENTRIES_LUT = {
        32'd1024, 32'd1024, 32'd1024, 32'd1024, 32'd1024
    };

    parameter bit [NUM_TABLES*8-1:0]  TAG_WIDTH_LUT = {
        8'd12, 8'd12, 8'd12, 8'd12, 8'd12
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