/******************************************************************************
 *  Project    : MuroSync
 *  File       : murosync_serdes_array_axi_ctrl.sv
 *  Created    : 2026-01-20
 *  Author     : Mikhail Vasilev
 *
 *  Description:
 *  AXI4-Lite control/status block for the MuroSync SERDES array.
 *
 *  Provides a small memory-mapped register file for firmware-driven bring-up
 *  and diagnostics, including W1P control pulses (CDC to core_clk), loopback
 *  control (level sync to core_clk), and CDC-clean SERDES status reporting into
 *  the AXI clock domain. Debug registers expose a sampled dbg bus for visibility.
 *
 *  Notes:
 *    - SERDES_STATUS is built only from synchronized status inputs (not dbg).
 *    - Uses `default_nettype none (restored to wire at end of file).
 *
 *  Copyright (c) 2026 Mikhail Vasilev / MuroSync
 *
 *  License:
 *  This file is currently released under a restricted research license.
 *  Licensing terms may change in future revisions of the project.
 *
 *  Commercial use, redistribution, or integration into commercial products
 *  requires an explicit license agreement.
 *
 *  For licensing inquiries, please contact:
 *      info@murosync.com
 *
 *****************************************************************************/

`default_nettype none

module murosync_serdes_array_axi_ctrl #(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_NUM_REGS   = 17,  // +5 diagnostic registers (0x030..0x040)

    // Keep same address-width convention as top:
    parameter integer OPT_MEM_ADDR_BITS_P  = $clog2(C_S00_AXI_NUM_REGS),
    parameter integer ADDR_WIDTH_NEEDED    = OPT_MEM_ADDR_BITS_P + 3
)(
    // AXI4-Lite slave ports
    input  wire                                s00_axi_aclk,
    input  wire                                s00_axi_aresetn,
    input  wire [ADDR_WIDTH_NEEDED-1:0]        s00_axi_awaddr,
    input  wire [2:0]                          s00_axi_awprot,
    input  wire                                s00_axi_awvalid,
    output wire                                s00_axi_awready,
    input  wire [C_S00_AXI_DATA_WIDTH-1:0]     s00_axi_wdata,
    input  wire [(C_S00_AXI_DATA_WIDTH/8)-1:0] s00_axi_wstrb,
    input  wire                                s00_axi_wvalid,
    output wire                                s00_axi_wready,
    output wire [1:0]                          s00_axi_bresp,
    output wire                                s00_axi_bvalid,
    input  wire                                s00_axi_bready,
    input  wire [ADDR_WIDTH_NEEDED-1:0]        s00_axi_araddr,
    input  wire [2:0]                          s00_axi_arprot,
    input  wire                                s00_axi_arvalid,
    output wire                                s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1:0]     s00_axi_rdata,
    output wire [1:0]                          s00_axi_rresp,
    output wire                                s00_axi_rvalid,
    input  wire                                s00_axi_rready,

    // Core-domain clock/reset (from top / GT freerun)
    input  wire                                core_clk,
    input  wire                                core_reset_all_in, // ACTIVE HIGH

    // CONTROL OUT (core_clk domain)
    output wire [2:0]                          loopback_ctrl,
    output wire                                link_down_latched_reset_pulse,
    output wire                                gt_reset_all_pulse,

    // STATUS IN (core_clk domain)
    input  wire                                link_up,
    input  wire                                link_down_latched,
    input  wire [3:0]                          pll_lock_in,

    // New dedicated status vectors (core_clk domain)
    input  wire [3:0]                          gtpowergood_in,
    input  wire [3:0]                          txpmaresetdone_in,
    input  wire [3:0]                          rxpmaresetdone_in,

    // Debug-only bus (core_clk domain)
    input  wire [63:0]                         dbg_in,

    //Link Integrity / Physical Loopback Testing
    output wire                                link_test_ctrl_rst_axi_pulse,
    output wire                                link_test_ctrl_en_core,
    output wire [15:0]                         link_test_cnfg,
    output wire [31:0]                         link_test_patt,
    input  wire [31:0]                         link_test_err_cnt,
    input  wire [31:0]                         link_test_wrd_cnt,

    // Diagnostic inputs from link test engine (rx_clk domain — 2FF sync below)
    input  wire [3:0]                          link_test_fsm_state,
    input  wire [3:0]                          link_test_rx_aligned,
    input  wire [3:0]                          link_test_rx_comma_seen,
    input  wire [3:0]                          link_test_rx_charisk,
    input  wire                                link_test_checker_locked,
    input  wire [63:0]                         link_test_rx_data,
    input  wire [63:0]                         link_test_exp_data,

    // Diagnostic inputs from link test engine (tx_clk domain — 2FF sync below)
    input  wire [63:0]                         link_test_tx_data,
    input  wire [15:0]                         link_test_tx_counter_ch0,
    input  wire [15:0]                         link_test_tx_counter_ch1,
    input  wire [15:0]                         link_test_tx_counter_ch2,
    input  wire [15:0]                         link_test_tx_counter_ch3,
    input  wire                                link_test_tx_comma_active,
    input  wire [11:0]                         link_test_tx_comma_count,

    // Tier 1 sticky diagnostics (rx_clk domain — 2FF sync below)
    input  wire                                link_test_ever_locked,
    input  wire [3:0]                          link_test_last_fsm_state,

    //=== GT DEBUG INPUT PORTS ===//
    input wire [3:0]  gt_debug_rxcommadet_out,
    input wire [3:0]  gt_debug_rxbyteisaligned_out,
    input wire [3:0]  gt_debug_rxbyterealign_out,
    input wire [11:0] gt_debug_rxbufstatus_out, 
    input wire [7:0]  gt_debug_txbufstatus_out,
    input wire [3:0]  gt_debug_rxsyncdone_out,
    input wire [3:0]  gt_debug_rxphaligndone_out,
    input wire [3:0]  gt_debug_eyescandataerror_out,
    input wire [3:0]  gt_debug_rxresetdone_out,
    input wire [3:0]  gt_debug_txresetdone_out,
    input wire [3:0]  gt_debug_rxpmaresetdone_out,
    input wire [3:0]  gt_debug_txpmaresetdone_out,

    // Tier 2 link_test diagnostic snapshots (rx_clk domain — CDC below)
    input  wire [31:0]                         link_test_time_to_lock,
    input  wire [31:0]                         link_test_locked_cycle_cnt,
    input  wire [63:0]                         link_test_rx_data_at_lock,
    input  wire [63:0]                         link_test_rx_data_at_first_err,

    // Tier 2 per-channel error counters (rx_clk domain — CDC below)
    input  wire [15:0]                         link_test_err_cnt_ch0,
    input  wire [15:0]                         link_test_err_cnt_ch1,
    input  wire [15:0]                         link_test_err_cnt_ch2,
    input  wire [15:0]                         link_test_err_cnt_ch3,

    // Tier 2 GT sticky event counters (RXUSRCLK2 domain — CDC below)
    input  wire [63:0]                         gt_debug_rxbyterealign_cnt,     // 4 × 16-bit packed
    input  wire [63:0]                         gt_debug_eyescandataerror_cnt   // 4 × 16-bit packed
);

    wire axi_clk   = s00_axi_aclk;
    wire axi_rst_n = s00_axi_aresetn;

    wire core_rst_n = ~core_reset_all_in; // ACTIVE HIGH -> rst_n

    logic [C_S00_AXI_DATA_WIDTH-1:0] slv_reg    [0:C_S00_AXI_NUM_REGS-1];
    logic [C_S00_AXI_DATA_WIDTH-1:0] axi_reg_rd [0:C_S00_AXI_NUM_REGS-1];

    // ------------------------------------------------------------
    // REG MAP (word offsets)
    // ------------------------------------------------------------
    localparam int SERDES_CTRL           = 'h0;  // W1P
    localparam int SERDES_LOOPBACK       = 'h1;  // RW
    localparam int SERDES_STATUS         = 'h2;  // RO
    localparam int SERDES_DBG_LO         = 'h3;  // RO
    localparam int SERDES_DBG_HI         = 'h4;  // RO
    localparam int SERDES_TEST_CONST     = 'h5;  // RO
    localparam int SERDES_TEST_SCRATCH   = 'h6;  // RW

    localparam int SERDES_LNK_TEST_CTRL  = 'h7;  // RW Offset 0x1C: [0]-Enable, [1]-Reset (W1P)
    localparam int SERDES_LNK_TEST_CNFG  = 'h8;  // RW Offset 0x20: [1:0] Test Mode, [7:4] Channel Mask
    localparam int SERDES_LNK_TEST_PATT  = 'h9;  // RW Offset 0x24: Fixed Test Pattern
    localparam int SERDES_LNK_RX_ERR_CNT = 'hA;  // RO Offset 0x28: RX Error Counter
    localparam int SERDES_LNK_RX_WRD_CNT  = 'hB;  // RO Offset 0x2C: RX Word Counter

    // Diagnostic registers (RO) — link test FSM internal state
    localparam int SERDES_LNK_DIAG_STATUS  = 'hC;  // RO Offset 0x30
    localparam int SERDES_LNK_DIAG_RX_LO   = 'hD;  // RO Offset 0x34
    localparam int SERDES_LNK_DIAG_RX_HI   = 'hE;  // RO Offset 0x38
    localparam int SERDES_LNK_DIAG_EXP_LO  = 'hF;  // RO Offset 0x3C
    localparam int SERDES_LNK_DIAG_EXP_HI  = 'h10; // RO Offset 0x40

    localparam int SERDES_LNK_DIAG_TX_DATA_LO     = 'h11; // RO Offset 0x44
    localparam int SERDES_LNK_DIAG_TX_DATA_HI     = 'h12; // RO Offset 0x48
    localparam int SERDES_LNK_DIAG_TX_COUNTERS_LO = 'h13; // RO Offset 0x4C (CH1, CH0)
    localparam int SERDES_LNK_DIAG_TX_COUNTERS_HI = 'h14; // RO Offset 0x50 (CH3, CH2)
    localparam int SERDES_LNK_DIAG_TX_STATUS      = 'h15; // RO Offset 0x54

    // Tier 1 sticky diagnostics register
    localparam int SERDES_LNK_DIAG_STATUS2     = 'h1C; // RO Offset 0x70

    // === Tier 2: Link Test Snapshots and Per-Channel Counters (0x80 = 'h20 onwards) ===
    // NOTE: offsets 'h1D..'h1F (0x74..0x7C) are reserved for future use.
    localparam int LNK_TIME_TO_LOCK            = 'h20; // RO 0x80  cycles WAIT_ALIGN -> LOCKED
    localparam int LNK_LOCKED_CYCLE_CNT        = 'h21; // RO 0x84  total cycles in LOCKED
    localparam int LNK_RX_DATA_AT_LOCK_LO      = 'h22; // RO 0x88  rx_data_at_lock[31:0]
    localparam int LNK_RX_DATA_AT_LOCK_HI      = 'h23; // RO 0x8C  rx_data_at_lock[63:32]
    localparam int LNK_RX_DATA_AT_FIRST_ERR_LO = 'h24; // RO 0x90  rx_data_at_first_err[31:0]
    localparam int LNK_RX_DATA_AT_FIRST_ERR_HI = 'h25; // RO 0x94  rx_data_at_first_err[63:32]

    // === Tier 2: Per-Channel Error Counters (0xA4 = 'h29 onwards, 16-bit each) ===
    localparam int LNK_ERR_CNT_CH0             = 'h26; // RO 0x98  per-channel error cnt CH0
    localparam int LNK_ERR_CNT_CH1             = 'h27; // RO 0x9C  per-channel error cnt CH1
    localparam int LNK_ERR_CNT_CH2             = 'h28; // RO 0xA0  per-channel error cnt CH2
    localparam int LNK_ERR_CNT_CH3             = 'h29; // RO 0xA4  per-channel error cnt CH3

    // === Tier 2: GT Sticky Counters (packed 16-bit per channel) ===
    localparam int GT_RXBYTEREALIGN_CNT_LO      = 'h2A; // RO 0xA8  [15:0]=CH0, [31:16]=CH1
    localparam int GT_RXBYTEREALIGN_CNT_HI      = 'h2B; // RO 0xAC  [15:0]=CH2, [31:16]=CH3
    localparam int GT_EYESCANDATAERROR_CNT_LO   = 'h2C; // RO 0xB0  [15:0]=CH0, [31:16]=CH1
    localparam int GT_EYESCANDATAERROR_CNT_HI   = 'h2D; // RO 0xB4  [15:0]=CH2, [31:16]=CH3
    // Total Tier 2 new registers: 14 (offsets 'h20..'h2D = indices 32..45)
    // C_S00_AXI_NUM_REGS must be >= 46 ('h2E) to cover all registers.

    // GT DEBUG REGISTERS
    localparam int GT_DEBUG_COMMA_ALIGN  = 'h16; // RO Offset 0x58
    localparam int GT_DEBUG_RXBUF_STATUS = 'h17; // RO Offset 0x5C
    localparam int GT_DEBUG_TXBUF_STATUS = 'h18; // RO Offset 0x60
    localparam int GT_DEBUG_SYNC_STATUS  = 'h19; // RO Offset 0x64
    localparam int GT_DEBUG_SIGNAL_QUAL  = 'h1A; // RO Offset 0x68
    localparam int GT_DEBUG_RESET_STATUS = 'h1B; // RO Offset 0x6C

    // SERDES_CTRL bits (W1P)
    localparam int SERDES_CTRL_LINK_DOWN_LATCHED_RESET = 0;
    localparam int SERDES_CTRL_GT_RESET_ALL_PULSE      = 1;

    // SERDES_STATUS bit fields (NEW layout)
    localparam int SERDES_STATUS_LINK_UP            = 0;
    localparam int SERDES_STATUS_LINK_DOWN_LATCHED  = 1;

    localparam int SERDES_STATUS_PLL_LOCK_CH0       = 16;  // [19:16]
    localparam int SERDES_STATUS_GTPWRGOOD_CH0      = 20;  // [23:20]
    localparam int SERDES_STATUS_TXPMARESETDONE_CH0 = 24;  // [27:24]
    localparam int SERDES_STATUS_RXPMARESETDONE_CH0 = 28;  // [31:28]

    // SERDES_LNK_TEST_CTRL bit fields
    localparam int LNK_TEST_CTRL_EN      = 0; // Bit [0]: 1 = Enable Link Test Mode
    localparam int LNK_TEST_CTRL_RST     = 1; // Bit [1]: 1 = Pulse to reset counters (W1P)

    // ------------------------------------------------------------
    // AXI slave (register file)  <-- 1:1 with wavecap pattern
    // ------------------------------------------------------------
    murosync_serdes_array_S00_AXI #(
        .C_S_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (ADDR_WIDTH_NEEDED),
        .C_S_AXI_NUM_REGS   (C_S00_AXI_NUM_REGS),
        .OPT_MEM_ADDR_BITS  (OPT_MEM_ADDR_BITS_P - 1)
    ) u_axi 
    (
        .S_AXI_ACLK    (axi_clk),
        .S_AXI_ARESETN (axi_rst_n),

        .S_AXI_AWADDR  (s00_axi_awaddr),
        .S_AXI_AWPROT  (s00_axi_awprot),
        .S_AXI_AWVALID (s00_axi_awvalid),
        .S_AXI_AWREADY (s00_axi_awready),

        .S_AXI_WDATA   (s00_axi_wdata),
        .S_AXI_WSTRB   (s00_axi_wstrb),
        .S_AXI_WVALID  (s00_axi_wvalid),
        .S_AXI_WREADY  (s00_axi_wready),

        .S_AXI_BRESP   (s00_axi_bresp),
        .S_AXI_BVALID  (s00_axi_bvalid),
        .S_AXI_BREADY  (s00_axi_bready),

        .S_AXI_ARADDR  (s00_axi_araddr),
        .S_AXI_ARPROT  (s00_axi_arprot),
        .S_AXI_ARVALID (s00_axi_arvalid),
        .S_AXI_ARREADY (s00_axi_arready),

        .S_AXI_RDATA   (s00_axi_rdata),
        .S_AXI_RRESP   (s00_axi_rresp),
        .S_AXI_RVALID  (s00_axi_rvalid),
        .S_AXI_RREADY  (s00_axi_rready),

        .slv_reg       (slv_reg),
        .axi_reg_rd    (axi_reg_rd)
  );

    // ------------------------------------------------------------
    // CONTROL: pulses AXI->core
    // ------------------------------------------------------------
    wire link_down_latched_reset_axi = slv_reg[SERDES_CTRL][SERDES_CTRL_LINK_DOWN_LATCHED_RESET];
    wire gt_reset_all_axi            = slv_reg[SERDES_CTRL][SERDES_CTRL_GT_RESET_ALL_PULSE];

    murosync_cdc_slow_to_fast #(.SYNC_STAGES(3)) u_cdc_latch_reset 
    (
        .clk   (core_clk),
        .rst_n (core_rst_n),

        .in    (link_down_latched_reset_axi),
        .out   (link_down_latched_reset_pulse)
    );

    murosync_cdc_slow_to_fast #(.SYNC_STAGES(3)) u_cdc_gt_reset_pulse (
        .clk   (core_clk),
        .rst_n (core_rst_n),

        .in    (gt_reset_all_axi),
        .out   (gt_reset_all_pulse)
    );

    // ------------------------------------------------------------
    // LOOPBACK: level sync axi_clk -> core_clk (2FF per bit)
    // ------------------------------------------------------------
    wire [2:0] loopback_axi = slv_reg[SERDES_LOOPBACK][2:0];

    (* ASYNC_REG="TRUE" *) logic [1:0] lb0_sync, lb1_sync, lb2_sync;
    always @(posedge core_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            lb0_sync <= 2'b00;
            lb1_sync <= 2'b00;
            lb2_sync <= 2'b00;
        end else 
        begin
            lb0_sync <= {lb0_sync[0], loopback_axi[0]};
            lb1_sync <= {lb1_sync[0], loopback_axi[1]};
            lb2_sync <= {lb2_sync[0], loopback_axi[2]};
        end
    end
    assign loopback_ctrl = {lb2_sync[1], lb1_sync[1], lb0_sync[1]};

    // ------------------------------------------------------------
    // STATUS: core->AXI (2FF into axi_clk)
    // ------------------------------------------------------------
    (* ASYNC_REG="TRUE" *) logic [1:0] link_up_sync;
    (* ASYNC_REG="TRUE" *) logic [1:0] link_lat_sync;
    always @(posedge axi_clk or negedge axi_rst_n) 
    begin
        if (!axi_rst_n) 
        begin
            link_up_sync  <= 2'b00;
            link_lat_sync <= 2'b00;
        end 
        else 
        begin
            link_up_sync  <= {link_up_sync[0],  link_up};
            link_lat_sync <= {link_lat_sync[0], link_down_latched};
        end
    end

    wire link_up_axi      = link_up_sync[1];
    wire link_latched_axi = link_lat_sync[1];

    (* ASYNC_REG="TRUE" *) logic [1:0] pll0_sync, pll1_sync, pll2_sync, pll3_sync;
    always @(posedge axi_clk or negedge axi_rst_n) 
    begin
        if (!axi_rst_n) 
        begin
            pll0_sync <= 2'b00; 
            pll1_sync <= 2'b00; 
            pll2_sync <= 2'b00; 
            pll3_sync <= 2'b00;
        end else 
        begin
            pll0_sync <= {pll0_sync[0], pll_lock_in[0]};
            pll1_sync <= {pll1_sync[0], pll_lock_in[1]};
            pll2_sync <= {pll2_sync[0], pll_lock_in[2]};
            pll3_sync <= {pll3_sync[0], pll_lock_in[3]};
        end
    end
    wire [3:0] pll_lock_axi = {pll3_sync[1], pll2_sync[1], pll1_sync[1], pll0_sync[1]};

    // Dedicated status vectors (CDC-clean)
    (* ASYNC_REG="TRUE" *) logic [1:0] gtp_sync [0:3];
    (* ASYNC_REG="TRUE" *) logic [1:0] txp_sync [0:3];
    (* ASYNC_REG="TRUE" *) logic [1:0] rxp_sync [0:3];

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) 
        begin : g_status_vec_sync
            always @(posedge axi_clk or negedge axi_rst_n) 
            begin
                if (!axi_rst_n) 
                begin
                    gtp_sync[gi] <= 2'b00;
                    txp_sync[gi] <= 2'b00;
                    rxp_sync[gi] <= 2'b00;
                end 
                else 
                begin
                    gtp_sync[gi] <= {gtp_sync[gi][0], gtpowergood_in[gi]};
                    txp_sync[gi] <= {txp_sync[gi][0], txpmaresetdone_in[gi]};
                    rxp_sync[gi] <= {rxp_sync[gi][0], rxpmaresetdone_in[gi]};
                end
            end
        end
    endgenerate

    wire [3:0] gtpowergood_axi    = {gtp_sync[3][1], gtp_sync[2][1], gtp_sync[1][1], gtp_sync[0][1]};
    wire [3:0] txpmaresetdone_axi = {txp_sync[3][1], txp_sync[2][1], txp_sync[1][1], txp_sync[0][1]};
    wire [3:0] rxpmaresetdone_axi = {rxp_sync[3][1], rxp_sync[2][1], rxp_sync[1][1], rxp_sync[0][1]};

    // ------------------------------------------------------------
    // dbg_in sampled into axi_clk for debug regs (debug-only!)
    // ------------------------------------------------------------
    logic [63:0] dbg_axi_r;
    always @(posedge axi_clk or negedge axi_rst_n) 
    begin
        if (!axi_rst_n) dbg_axi_r <= 64'h0;
        else           dbg_axi_r <= dbg_in;
    end

    // ------------------------------------------------------------
    // READBACK MAP
    // ------------------------------------------------------------
    assign axi_reg_rd[SERDES_CTRL]     = 32'h0; // WO by convention
    assign axi_reg_rd[SERDES_LOOPBACK] = {29'h0, loopback_axi};

    // IMPORTANT: SERDES_STATUS uses CDC-clean status signals
    assign axi_reg_rd[SERDES_STATUS] = (link_up_axi        << SERDES_STATUS_LINK_UP)            |
                                       (link_latched_axi   << SERDES_STATUS_LINK_DOWN_LATCHED)  |
                                       (pll_lock_axi       << SERDES_STATUS_PLL_LOCK_CH0)       |
                                       (gtpowergood_axi    << SERDES_STATUS_GTPWRGOOD_CH0)      |
                                       (txpmaresetdone_axi << SERDES_STATUS_TXPMARESETDONE_CH0) |
                                       (rxpmaresetdone_axi << SERDES_STATUS_RXPMARESETDONE_CH0);

    // DBG regs remain debug-only (may be async-sampled; do not use for decisions)
    assign axi_reg_rd[SERDES_DBG_LO] = dbg_axi_r[31:0];
    assign axi_reg_rd[SERDES_DBG_HI] = dbg_axi_r[63:32];

    // ------------------------------------------------------------
    // AXI Infrastructure Verification REGISTERS
    // ------------------------------------------------------------
    localparam logic [31:0] MUROSYNC_TEST_MAGIC = 32'h4D55_524F; // "MURO"
    assign axi_reg_rd[SERDES_TEST_CONST]   = MUROSYNC_TEST_MAGIC;
    assign axi_reg_rd[SERDES_TEST_SCRATCH] = slv_reg[SERDES_TEST_SCRATCH];

    // ------------------------------------------------------------
    // Link Integrity / Physical Loopback Testing REGISTERS
    // ------------------------------------------------------------
    wire       link_test_ctrl_en_axi  = slv_reg[SERDES_LNK_TEST_CTRL][LNK_TEST_CTRL_EN];
    wire       link_test_ctrl_rst_axi = slv_reg[SERDES_LNK_TEST_CTRL][LNK_TEST_CTRL_RST];
    wire [15:0] link_test_cnfg_axi    = slv_reg[SERDES_LNK_TEST_CNFG][15:0];
    assign     link_test_patt         = slv_reg[SERDES_LNK_TEST_PATT];

    murosync_cdc_slow_to_fast #(.SYNC_STAGES(3)) u_cdc_link_test_ctrl_rst
    (
        .clk   (core_clk),
        .rst_n (core_rst_n),

        .in    (link_test_ctrl_rst_axi),
        .out   (link_test_ctrl_rst_axi_pulse)
    );

    (* ASYNC_REG="TRUE" *) logic [1:0] link_test_en_sync;
    always @(posedge core_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) link_test_en_sync <= 2'b0;
        else             link_test_en_sync <= {link_test_en_sync[0], link_test_ctrl_en_axi};
    end
    assign link_test_ctrl_en_core = link_test_en_sync[1];

    (* ASYNC_REG="TRUE" *) logic [15:0] link_test_cnfg_sync_0, link_test_cnfg_sync_1;
    always @(posedge core_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            link_test_cnfg_sync_0 <= 16'h0000;
            link_test_cnfg_sync_1 <= 16'h0000;
        end 
        else 
        begin
            link_test_cnfg_sync_0 <= link_test_cnfg_axi;
            link_test_cnfg_sync_1 <= link_test_cnfg_sync_0;
        end
    end
    assign link_test_cnfg = link_test_cnfg_sync_1;


    (* ASYNC_REG="TRUE" *) reg [31:0] link_test_err_cnt_s0, link_test_err_cnt_axi;
    (* ASYNC_REG="TRUE" *) reg [31:0] link_test_wrd_cnt_s0, link_test_wrd_cnt_axi;

    always @(posedge axi_clk or negedge axi_rst_n)
    begin
        if (!axi_rst_n) 
        begin
            link_test_err_cnt_s0  <= 32'b0;
            link_test_err_cnt_axi <= 32'b0;
            link_test_wrd_cnt_s0  <= 32'b0;
            link_test_wrd_cnt_axi <= 32'b0;
        end else 
        begin
            link_test_err_cnt_s0  <= link_test_err_cnt;
            link_test_err_cnt_axi <= link_test_err_cnt_s0;
            link_test_wrd_cnt_s0  <= link_test_wrd_cnt;
            link_test_wrd_cnt_axi <= link_test_wrd_cnt_s0;
        end
    end
    assign axi_reg_rd[SERDES_LNK_RX_ERR_CNT] = link_test_err_cnt_axi;
    assign axi_reg_rd[SERDES_LNK_RX_WRD_CNT] = link_test_wrd_cnt_axi;

    // Link Test Control and Configuration (Full RW support)
    assign axi_reg_rd[SERDES_LNK_TEST_CTRL] = slv_reg[SERDES_LNK_TEST_CTRL];
    assign axi_reg_rd[SERDES_LNK_TEST_CNFG] = slv_reg[SERDES_LNK_TEST_CNFG];
    assign axi_reg_rd[SERDES_LNK_TEST_PATT] = slv_reg[SERDES_LNK_TEST_PATT];

    // ------------------------------------------------------------
    // Diagnostic CDC: rx_clk domain → axi_clk
    // Uses murosync_cdc_level_sync module instances (pureCOLD pattern).
    // Vivado never optimizes away module instances.
    // Debug-only: bits not coherent with each other, safe for monitoring.
    // ------------------------------------------------------------

    wire [3:0] diag_fsm_axi;
    wire [3:0] diag_aligned_axi;
    wire [3:0] diag_comma_axi;
    wire [3:0] diag_charisk_axi;
    wire       diag_locked_axi;

    murosync_cdc_level_sync #(.WIDTH(4), .SYNC_STAGES(2)) u_cdc_diag_fsm (
        .clk  (axi_clk),
        .rst_n(axi_rst_n),
        .in   (link_test_fsm_state),
        .out  (diag_fsm_axi)
    );

    murosync_cdc_level_sync #(.WIDTH(4), .SYNC_STAGES(2)) u_cdc_diag_aligned (
        .clk  (axi_clk),
        .rst_n(axi_rst_n),
        .in   (link_test_rx_aligned),
        .out  (diag_aligned_axi)
    );

    murosync_cdc_level_sync #(.WIDTH(4), .SYNC_STAGES(2)) u_cdc_diag_comma (
        .clk  (axi_clk),
        .rst_n(axi_rst_n),
        .in   (link_test_rx_comma_seen),
        .out  (diag_comma_axi)
    );

    murosync_cdc_level_sync #(.WIDTH(4), .SYNC_STAGES(2)) u_cdc_diag_charisk (
        .clk  (axi_clk),
        .rst_n(axi_rst_n),
        .in   (link_test_rx_charisk),
        .out  (diag_charisk_axi)
    );

    murosync_cdc_level_sync #(.WIDTH(1), .SYNC_STAGES(2)) u_cdc_diag_locked (
        .clk  (axi_clk),
        .rst_n(axi_rst_n),
        .in   (link_test_checker_locked),
        .out  (diag_locked_axi)
    );

    // 64-bit buses: single-register sample (debug-only, no coherence guarantee)
    (* keep = "true" *) logic [63:0] diag_rx_data_axi;
    (* keep = "true" *) logic [63:0] diag_exp_data_axi;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            diag_rx_data_axi  <= 64'h0;
            diag_exp_data_axi <= 64'h0;
        end else begin
            diag_rx_data_axi  <= link_test_rx_data;
            diag_exp_data_axi <= link_test_exp_data;
        end
    end

    // TX diagnostic registers CDC
    (* keep = "true" *) logic [63:0] diag_tx_data_axi;
    (* keep = "true" *) logic [63:0] diag_tx_counters_axi;
    (* keep = "true" *) logic [31:0] diag_tx_status_axi;

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            diag_tx_data_axi     <= 64'h0;
            diag_tx_counters_axi <= 64'h0;
            diag_tx_status_axi   <= 32'h0;
        end else begin
            diag_tx_data_axi     <= link_test_tx_data;
            diag_tx_counters_axi <= {link_test_tx_counter_ch3, link_test_tx_counter_ch2, link_test_tx_counter_ch1, link_test_tx_counter_ch0};
            diag_tx_status_axi   <= {19'h0, link_test_tx_comma_count, link_test_tx_comma_active};
        end
    end

    // LNK_DIAG_STATUS: [3:0] fsm | [7:4] aligned | [11:8] comma | [15:12] charisk | [16] locked
    assign axi_reg_rd[SERDES_LNK_DIAG_STATUS] = {
        15'h0,
        diag_locked_axi,
        diag_charisk_axi,
        diag_comma_axi,
        diag_aligned_axi,
        diag_fsm_axi
    };
    assign axi_reg_rd[SERDES_LNK_DIAG_RX_LO]  = diag_rx_data_axi[31:0];
    assign axi_reg_rd[SERDES_LNK_DIAG_RX_HI]  = diag_rx_data_axi[63:32];
    assign axi_reg_rd[SERDES_LNK_DIAG_EXP_LO] = diag_exp_data_axi[31:0];
    assign axi_reg_rd[SERDES_LNK_DIAG_EXP_HI] = diag_exp_data_axi[63:32];

    assign axi_reg_rd[SERDES_LNK_DIAG_TX_DATA_LO]     = diag_tx_data_axi[31:0];
    assign axi_reg_rd[SERDES_LNK_DIAG_TX_DATA_HI]     = diag_tx_data_axi[63:32];
    assign axi_reg_rd[SERDES_LNK_DIAG_TX_COUNTERS_LO] = diag_tx_counters_axi[31:0];
    assign axi_reg_rd[SERDES_LNK_DIAG_TX_COUNTERS_HI] = diag_tx_counters_axi[63:32];
    assign axi_reg_rd[SERDES_LNK_DIAG_TX_STATUS]      = diag_tx_status_axi;

    // Tier 1 sticky diagnostics CDC: rx_clk → axi_clk
    wire       diag_ever_locked_axi;
    wire [3:0] diag_last_fsm_state_axi;

    murosync_cdc_level_sync #(.WIDTH(1), .SYNC_STAGES(2)) u_cdc_diag_ever_locked (
        .clk  (axi_clk),
        .rst_n(axi_rst_n),
        .in   (link_test_ever_locked),
        .out  (diag_ever_locked_axi)
    );

    murosync_cdc_level_sync #(.WIDTH(4), .SYNC_STAGES(2)) u_cdc_diag_last_fsm (
        .clk  (axi_clk),
        .rst_n(axi_rst_n),
        .in   (link_test_last_fsm_state),
        .out  (diag_last_fsm_state_axi)
    );

    // LNK_DIAG_STATUS2: [0] ever_locked | [7:4] last_fsm_state
    assign axi_reg_rd[SERDES_LNK_DIAG_STATUS2] = {
        24'h0,
        diag_last_fsm_state_axi,
        3'h0,
        diag_ever_locked_axi
    };

    // GT DEBUG REGISTERS CDC
    (* keep = "true" *) logic [31:0] gt_debug_comma_align_axi;
    (* keep = "true" *) logic [31:0] gt_debug_rxbuf_status_axi;
    (* keep = "true" *) logic [31:0] gt_debug_txbuf_status_axi;
    (* keep = "true" *) logic [31:0] gt_debug_sync_status_axi;
    (* keep = "true" *) logic [31:0] gt_debug_signal_qual_axi;
    (* keep = "true" *) logic [31:0] gt_debug_reset_status_axi;

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            gt_debug_comma_align_axi  <= 32'h0;
            gt_debug_rxbuf_status_axi <= 32'h0;
            gt_debug_txbuf_status_axi <= 32'h0;
            gt_debug_sync_status_axi  <= 32'h0;
            gt_debug_signal_qual_axi  <= 32'h0;
            gt_debug_reset_status_axi <= 32'h0;
        end else begin
            gt_debug_comma_align_axi  <= {16'b0, gt_debug_rxbyterealign_out, gt_debug_rxbyteisaligned_out, gt_debug_rxcommadet_out};
            gt_debug_rxbuf_status_axi <= {20'b0, gt_debug_rxbufstatus_out};
            gt_debug_txbuf_status_axi <= {24'b0, gt_debug_txbufstatus_out};
            gt_debug_sync_status_axi  <= {20'b0, gt_debug_rxphaligndone_out, gt_debug_rxsyncdone_out}; // Note: rxcdrlock_out is not available natively in all configs, using just the others
            gt_debug_signal_qual_axi  <= {28'b0, gt_debug_eyescandataerror_out};
            gt_debug_reset_status_axi <= {16'b0, gt_debug_txpmaresetdone_out, gt_debug_rxpmaresetdone_out, gt_debug_txresetdone_out, gt_debug_rxresetdone_out};
        end
    end

    assign axi_reg_rd[GT_DEBUG_COMMA_ALIGN]  = gt_debug_comma_align_axi;
    assign axi_reg_rd[GT_DEBUG_RXBUF_STATUS] = gt_debug_rxbuf_status_axi;
    assign axi_reg_rd[GT_DEBUG_TXBUF_STATUS] = gt_debug_txbuf_status_axi;
    assign axi_reg_rd[GT_DEBUG_SYNC_STATUS]  = gt_debug_sync_status_axi;
    assign axi_reg_rd[GT_DEBUG_SIGNAL_QUAL]  = gt_debug_signal_qual_axi;
    assign axi_reg_rd[GT_DEBUG_RESET_STATUS] = gt_debug_reset_status_axi;

    // ============================================================
    // Tier 2 CDC: rx_clk domain -> axi_clk
    // Using level_sync (eventually consistent — acceptable for diagnostic counters and
    // frozen snapshots). Snapshots (rx_data_at_lock, rx_data_at_first_err) are frozen
    // after first latch so no coherence risk. Counters may be off by 1-2 reads — acceptable.
    // ============================================================

    // -- time_to_lock (32-bit, frozen after first LOCKED) --
    wire [31:0] diag_time_to_lock_axi;
    murosync_cdc_level_sync #(.WIDTH(32), .SYNC_STAGES(2)) u_cdc_t2_time_to_lock (
        .clk  (axi_clk), .rst_n(axi_rst_n),
        .in   (link_test_time_to_lock),
        .out  (diag_time_to_lock_axi)
    );

    // -- locked_cycle_cnt (32-bit, running counter) --
    wire [31:0] diag_locked_cycle_cnt_axi;
    murosync_cdc_level_sync #(.WIDTH(32), .SYNC_STAGES(2)) u_cdc_t2_locked_cnt (
        .clk  (axi_clk), .rst_n(axi_rst_n),
        .in   (link_test_locked_cycle_cnt),
        .out  (diag_locked_cycle_cnt_axi)
    );

    // -- rx_data_at_lock (64-bit, frozen snapshot) --
    wire [63:0] diag_rx_data_at_lock_axi;
    murosync_cdc_level_sync #(.WIDTH(64), .SYNC_STAGES(2)) u_cdc_t2_rx_at_lock (
        .clk  (axi_clk), .rst_n(axi_rst_n),
        .in   (link_test_rx_data_at_lock),
        .out  (diag_rx_data_at_lock_axi)
    );

    // -- rx_data_at_first_err (64-bit, frozen snapshot) --
    wire [63:0] diag_rx_data_at_first_err_axi;
    murosync_cdc_level_sync #(.WIDTH(64), .SYNC_STAGES(2)) u_cdc_t2_rx_at_err (
        .clk  (axi_clk), .rst_n(axi_rst_n),
        .in   (link_test_rx_data_at_first_err),
        .out  (diag_rx_data_at_first_err_axi)
    );

    // -- per-channel error counters (16-bit each) --
    wire [15:0] diag_err_cnt_ch0_axi;
    wire [15:0] diag_err_cnt_ch1_axi;
    wire [15:0] diag_err_cnt_ch2_axi;
    wire [15:0] diag_err_cnt_ch3_axi;
    murosync_cdc_level_sync #(.WIDTH(16), .SYNC_STAGES(2)) u_cdc_t2_err_ch0 (
        .clk(axi_clk), .rst_n(axi_rst_n), .in(link_test_err_cnt_ch0), .out(diag_err_cnt_ch0_axi)
    );
    murosync_cdc_level_sync #(.WIDTH(16), .SYNC_STAGES(2)) u_cdc_t2_err_ch1 (
        .clk(axi_clk), .rst_n(axi_rst_n), .in(link_test_err_cnt_ch1), .out(diag_err_cnt_ch1_axi)
    );
    murosync_cdc_level_sync #(.WIDTH(16), .SYNC_STAGES(2)) u_cdc_t2_err_ch2 (
        .clk(axi_clk), .rst_n(axi_rst_n), .in(link_test_err_cnt_ch2), .out(diag_err_cnt_ch2_axi)
    );
    murosync_cdc_level_sync #(.WIDTH(16), .SYNC_STAGES(2)) u_cdc_t2_err_ch3 (
        .clk(axi_clk), .rst_n(axi_rst_n), .in(link_test_err_cnt_ch3), .out(diag_err_cnt_ch3_axi)
    );

    // -- GT sticky counters (sampled directly, debug-only, eventual consistency) --
    (* keep = "true" *) logic [63:0] gt_rxbyterealign_cnt_axi;
    (* keep = "true" *) logic [63:0] gt_eyescandataerror_cnt_axi;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            gt_rxbyterealign_cnt_axi    <= 64'h0;
            gt_eyescandataerror_cnt_axi <= 64'h0;
        end else begin
            gt_rxbyterealign_cnt_axi    <= gt_debug_rxbyterealign_cnt;
            gt_eyescandataerror_cnt_axi <= gt_debug_eyescandataerror_cnt;
        end
    end

    // Tier 2 AXI register read assignments
    assign axi_reg_rd[LNK_TIME_TO_LOCK]            = diag_time_to_lock_axi;
    assign axi_reg_rd[LNK_LOCKED_CYCLE_CNT]        = diag_locked_cycle_cnt_axi;
    assign axi_reg_rd[LNK_RX_DATA_AT_LOCK_LO]      = diag_rx_data_at_lock_axi[31:0];
    assign axi_reg_rd[LNK_RX_DATA_AT_LOCK_HI]      = diag_rx_data_at_lock_axi[63:32];
    assign axi_reg_rd[LNK_RX_DATA_AT_FIRST_ERR_LO] = diag_rx_data_at_first_err_axi[31:0];
    assign axi_reg_rd[LNK_RX_DATA_AT_FIRST_ERR_HI] = diag_rx_data_at_first_err_axi[63:32];
    assign axi_reg_rd[LNK_ERR_CNT_CH0]             = {16'h0, diag_err_cnt_ch0_axi};
    assign axi_reg_rd[LNK_ERR_CNT_CH1]             = {16'h0, diag_err_cnt_ch1_axi};
    assign axi_reg_rd[LNK_ERR_CNT_CH2]             = {16'h0, diag_err_cnt_ch2_axi};
    assign axi_reg_rd[LNK_ERR_CNT_CH3]             = {16'h0, diag_err_cnt_ch3_axi};
    assign axi_reg_rd[GT_RXBYTEREALIGN_CNT_LO]     = {gt_rxbyterealign_cnt_axi[31:16], gt_rxbyterealign_cnt_axi[15:0]};    // CH1[31:16], CH0[15:0]
    assign axi_reg_rd[GT_RXBYTEREALIGN_CNT_HI]     = {gt_rxbyterealign_cnt_axi[63:48], gt_rxbyterealign_cnt_axi[47:32]};  // CH3[31:16], CH2[15:0]
    assign axi_reg_rd[GT_EYESCANDATAERROR_CNT_LO]  = {gt_eyescandataerror_cnt_axi[31:16], gt_eyescandataerror_cnt_axi[15:0]};
    assign axi_reg_rd[GT_EYESCANDATAERROR_CNT_HI]  = {gt_eyescandataerror_cnt_axi[63:48], gt_eyescandataerror_cnt_axi[47:32]};

endmodule
`default_nettype wire
