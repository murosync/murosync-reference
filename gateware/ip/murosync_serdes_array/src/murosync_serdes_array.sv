/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_serdes_array.sv
 * Created    : 2026-01-20
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   Top-level 4-channel GT SERDES array with integrated AXI4-Lite control.
 *
 *   Provides reference clock buffering, GT wrapper integration, link-up/latch
 *   logic, and a compact AXI register map for firmware bring-up and health
 *   telemetry (LINK_UP, sticky LINK_DOWN_LATCHED, per-channel lock/powergood/
 *   resetdone vectors). A 64-bit dbg bus is exported for ILA/telemetry only.
 *
 * Notes:
 *   - Rollback-safe: AXI can generate GT reset/loopback controls, but they may
 *     be intentionally not applied to the GT during debug.
 *   - `default_nettype none` is used for stricter compile-time checks.
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

module murosync_serdes_array #(
    parameter string MODE = "MASTER", // "MASTER" / "SLAVE"

    parameter bit IS_SLAVE  = (MODE == "SLAVE"),
    parameter bit IS_MASTER = (MODE == "MASTER"),

    parameter integer C_S00_AXI_DATA_WIDTH = 32,

    // CTRL, LOOPBACK, STATUS, DBG_LO, DBG_HI, TEST_CONST, TEST_SCRATCH
    // +14 Tier 2 diagnostic registers (0x80..0xB4, indices 32..45)
    // +2  Stage 5 LNK_EXP_DATA_AT_FIRST_ERR_LO/HI (0xB8/0xBC, indices 46..47)
    parameter integer C_S00_AXI_NUM_REGS   = 48,

    // Pattern copied from axis_wavecap_streamer.sv
    parameter integer OPT_MEM_ADDR_BITS    = $clog2(C_S00_AXI_NUM_REGS),
    parameter integer ADDR_WIDTH_NEEDED    = OPT_MEM_ADDR_BITS + 3
)(
    // Differential reference clock inputs
    input  wire mgtrefclk0_x0y1_p,
    input  wire mgtrefclk0_x0y1_n,

    // Serial data ports for transceiver channel 0..3

    input  wire muro_gth_slave_rxn_in,
    input  wire muro_gth_slave_rxp_in,
    output wire muro_gth_slave_txn_out,
    output wire muro_gth_slave_txp_out,

    input  wire muro_gth_aux_0_rxn_in,
    input  wire muro_gth_aux_0_rxp_in,
    output wire muro_gth_aux_0_txn_out,
    output wire muro_gth_aux_0_txp_out,

    input  wire muro_gth_aux_1_rxn_in,
    input  wire muro_gth_aux_1_rxp_in,
    output wire muro_gth_aux_1_txn_out,
    output wire muro_gth_aux_1_txp_out,

    input  wire muro_gth_aux_2_rxn_in,
    input  wire muro_gth_aux_2_rxp_in,
    output wire muro_gth_aux_2_txn_out,
    output wire muro_gth_aux_2_txp_out,

    input  wire muro_gth_master_0_rxn_in,
    input  wire muro_gth_master_0_rxp_in,
    output wire muro_gth_master_0_txn_out,
    output wire muro_gth_master_0_txp_out,

    input  wire muro_gth_master_1_rxn_in,
    input  wire muro_gth_master_1_rxp_in,
    output wire muro_gth_master_1_txn_out,
    output wire muro_gth_master_1_txp_out,

    input  wire muro_gth_master_2_rxn_in,
    input  wire muro_gth_master_2_rxp_in,
    output wire muro_gth_master_2_txn_out,
    output wire muro_gth_master_2_txp_out,

    input  wire muro_gth_master_3_rxn_in,
    input  wire muro_gth_master_3_rxp_in,
    output wire muro_gth_master_3_txn_out,
    output wire muro_gth_master_3_txp_out,

    // RECOVERED CLOCK 
    output wire        slave_recclk_out,        // recovered clock from SLAVE[0] (RXUSRCLK2)
    output wire        slave_recclk_alive_out,  // alive latch (NOT lock indicator)

    // Free-running clock + global reset
    input  wire hb_gtwiz_reset_clk_freerun_in,
    input  wire hb_gtwiz_reset_all_in,

    // Link status ports (external optional pulse)
    input  wire link_down_latched_reset_in,
    output wire link_status_out,
    output reg  link_down_latched_out = 1'b1,

    // PLL lock status
    output wire [3:0] pll_lock_out,

    // Debug outputs for ILA
    output wire [63:0] dbg,
    output wire        refclk_out,    // fabric-legal refclk/2 AFTER BUFG_GT
 
    // ============================================================
    // AXI4-Lite slave interface (INTEGRATED)
    // ============================================================
    input  wire                         s00_axi_aclk,
    input  wire                         s00_axi_aresetn,
    input  wire [ADDR_WIDTH_NEEDED-1:0] s00_axi_awaddr,
    input  wire [2:0]                   s00_axi_awprot,
    input  wire                         s00_axi_awvalid,
    output wire                         s00_axi_awready,
    input  wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_wdata,
    input  wire [(C_S00_AXI_DATA_WIDTH/8)-1:0] s00_axi_wstrb,
    input  wire                         s00_axi_wvalid,
    output wire                         s00_axi_wready,
    output wire [1:0]                   s00_axi_bresp,
    output wire                         s00_axi_bvalid,
    input  wire                         s00_axi_bready,
    input  wire [ADDR_WIDTH_NEEDED-1:0] s00_axi_araddr,
    input  wire [2:0]                   s00_axi_arprot,
    input  wire                         s00_axi_arvalid,
    output wire                         s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_rdata,
    output wire [1:0]                   s00_axi_rresp,
    output wire                         s00_axi_rvalid,
    input  wire                         s00_axi_rready
);

    // ============================================================
    // MODE select (compile-time)
    initial 
    begin
        if (!(IS_SLAVE || IS_MASTER)) 
        begin
            $fatal(1, "murosync_serdes_array: invalid MODE='%s' (use 'MASTER' or 'SLAVE')", MODE);
        end
    end
  
    // ============================================================
    // RECOVERED CLOCK
    // ============================================================  
    wire gtwiz_userclk_rx_recclk_int;
    wire gtwiz_userclk_rx_recclk_alive_int;
    
    assign slave_recclk_out       = IS_SLAVE ? gtwiz_userclk_rx_recclk_int       : 1'b0;
    assign slave_recclk_alive_out = IS_SLAVE ? gtwiz_userclk_rx_recclk_alive_int : 1'b0;
    
    // ============================================================
    // RX PORTS WITH MUX
    // ============================================================

    wire [3:0] gthrxn_int_slave = {muro_gth_aux_2_rxn_in,  muro_gth_aux_1_rxn_in,  muro_gth_aux_0_rxn_in,  muro_gth_slave_rxn_in};
    wire [3:0] gthrxp_int_slave = {muro_gth_aux_2_rxp_in,  muro_gth_aux_1_rxp_in,  muro_gth_aux_0_rxp_in,  muro_gth_slave_rxp_in};

    wire [3:0] gthrxn_int_master = {muro_gth_master_3_rxn_in, muro_gth_master_2_rxn_in, muro_gth_master_1_rxn_in, muro_gth_master_0_rxn_in};
    wire [3:0] gthrxp_int_master = {muro_gth_master_3_rxp_in, muro_gth_master_2_rxp_in, muro_gth_master_1_rxp_in, muro_gth_master_0_rxp_in};

    wire [3:0] gthrxn_int = IS_SLAVE ? gthrxn_int_slave : gthrxn_int_master;
    wire [3:0] gthrxp_int = IS_SLAVE ? gthrxp_int_slave : gthrxp_int_master;

    // ============================================================
    // TX PORTS WITH DEMUX
    // ============================================================

    wire [3:0] gthtxn_int;
    wire [3:0] gthtxp_int;

    assign {muro_gth_aux_2_txn_out, muro_gth_aux_1_txn_out, muro_gth_aux_0_txn_out, muro_gth_slave_txn_out} = IS_SLAVE ? gthtxn_int : 4'b0000; 
    assign {muro_gth_aux_2_txp_out, muro_gth_aux_1_txp_out, muro_gth_aux_0_txp_out, muro_gth_slave_txp_out} = IS_SLAVE ? gthtxp_int : 4'b0000;
    
    assign {muro_gth_master_3_txn_out, muro_gth_master_2_txn_out, muro_gth_master_1_txn_out, muro_gth_master_0_txn_out} = IS_MASTER ? gthtxn_int : 4'b0000;
    assign {muro_gth_master_3_txp_out, muro_gth_master_2_txp_out, muro_gth_master_1_txp_out, muro_gth_master_0_txp_out} = IS_MASTER ? gthtxp_int : 4'b0000;
    
    // ============================================================
    // BUFFERS
    // ============================================================
    wire hb_gtwiz_reset_all_buf_int;
    IBUF u_ibuf_reset_all 
    (
        .I (hb_gtwiz_reset_all_in),
        .O (hb_gtwiz_reset_all_buf_int)
    );

    wire hb_gtwiz_reset_clk_freerun_buf_int;
    BUFG u_bufg_freerun 
    (
        .I (hb_gtwiz_reset_clk_freerun_in),
        .O (hb_gtwiz_reset_clk_freerun_buf_int)
    );

    // Refclk (GT-only + ODIV2 -> BUFG_GT)
    wire mgtrefclk0_x0y1_int;
    wire mgtrefclk0_x0y1_odiv2_int;

    IBUFDS_GTE4 #(
        .REFCLK_EN_TX_PATH  (1'b0),
        .REFCLK_HROW_CK_SEL (2'b00),
        .REFCLK_ICNTL_RX    (2'b00)
    ) u_ibufds_gte4_refclk 
    (
        .I     (mgtrefclk0_x0y1_p),
        .IB    (mgtrefclk0_x0y1_n),
        .CEB   (1'b0),
        .O     (mgtrefclk0_x0y1_int),
        .ODIV2 (mgtrefclk0_x0y1_odiv2_int)
    );

    wire mgtrefclk0_x0y1_div2_bufg;
    BUFG_GT u_bufg_gt_refclk_div2 
    (
        .I       (mgtrefclk0_x0y1_odiv2_int),
        .CE      (1'b1),
        .CEMASK  (1'b0),
        .CLR     (1'b0),
        .CLRMASK (1'b0),
        .DIV     (3'b000),
        .O       (mgtrefclk0_x0y1_div2_bufg)
    );
    assign refclk_out = mgtrefclk0_x0y1_div2_bufg;

    wire hb_gtwiz_reset_all_int = hb_gtwiz_reset_all_buf_int;

    // ============================================================
    // Signals to/from GT wrapper
    // ============================================================
    wire [3:0] gtpowergood_int;
    wire [3:0] rxpmaresetdone_int;
    wire [3:0] txpmaresetdone_int;

    wire       gtwiz_reset_tx_done_int;
    wire       gtwiz_reset_rx_done_int;
    wire       gtwiz_reset_rx_cdr_stable_int;
    wire       gtwiz_userclk_tx_active_int;
    wire       gtwiz_userclk_rx_active_int;

    wire [3:0] pll_lock_int;

    // AXI-driven control (generated, but GT application is currently disabled)
    wire [2:0] loopback_ctrl;
    wire       link_latch_reset_axi;
    wire       gt_reset_all_pulse_axi;

    // AXI Link Test controls
    wire        link_test_ctrl_rst_axi_pulse;
    wire        link_test_ctrl_en_core;
    wire [15:0] link_test_cnfg;
    wire [31:0] link_test_patt;
    wire [31:0] link_test_err_cnt;
    wire [31:0] link_test_wrd_cnt;

    // Diagnostic wires: link test engine → axi_ctrl (rx_clk domain, synced in axi_ctrl)
    wire [3:0]  link_test_diag_fsm_state;
    wire [3:0]  link_test_diag_rx_aligned;
    wire [3:0]  link_test_diag_rx_aligned_seen;
    wire [3:0]  link_test_diag_rx_charisk;
    wire        link_test_diag_checker_locked;
    wire [63:0] link_test_diag_rx_data;
    wire [63:0] link_test_diag_exp_data;

    // Diagnostic wires: link test engine → axi_ctrl (tx_clk domain, synced in axi_ctrl)
    wire [63:0] link_test_diag_tx_data;
    wire [15:0] link_test_diag_tx_counter_ch0;
    wire [15:0] link_test_diag_tx_counter_ch1;
    wire [15:0] link_test_diag_tx_counter_ch2;
    wire [15:0] link_test_diag_tx_counter_ch3;
    wire        link_test_diag_tx_comma_active;
    wire [11:0] link_test_diag_tx_comma_count;
    wire        link_test_diag_ever_locked;
    wire [3:0]  link_test_diag_last_fsm_state;

    // Tier 2: link_test diagnostic snapshots and counters (rx_clk domain)
    wire [31:0] link_test_diag_time_to_lock;
    wire [31:0] link_test_diag_locked_cycle_cnt;
    wire [63:0] link_test_diag_rx_data_at_lock;
    wire [63:0] link_test_diag_rx_data_at_first_err;
    wire [63:0] link_test_diag_exp_data_at_first_err;
    wire [15:0] link_test_diag_err_cnt_ch0;
    wire [15:0] link_test_diag_err_cnt_ch1;
    wire [15:0] link_test_diag_err_cnt_ch2;
    wire [15:0] link_test_diag_err_cnt_ch3;
    wire        link_test_diag_rx_data_at_lock_valid;
    wire        link_test_diag_first_err_valid;

    // Tier 2: GT sticky event counters (packed 16-bit per channel, 4 channels = 64 bits)
    wire [63:0] gt_debug_rxbyterealign_cnt_int;
    wire [63:0] gt_debug_eyescandataerror_cnt_int;

    // ============================================================
    // LINK STATUS (bring-up definition: "GT is alive")
    // ============================================================
    wire link_up_raw = (&gtpowergood_int) &
                       (&txpmaresetdone_int) &
                       (&rxpmaresetdone_int) &
                       gtwiz_reset_tx_done_int &
                       gtwiz_reset_rx_done_int &
                       gtwiz_userclk_tx_active_int &
                       gtwiz_userclk_rx_active_int;

    assign link_status_out = link_up_raw;
    assign pll_lock_out    = pll_lock_int;

    // ============================================================
    // LINK LATCH
    // ============================================================
    wire link_latch_reset_comb = link_down_latched_reset_in | link_latch_reset_axi;

    always @(posedge hb_gtwiz_reset_clk_freerun_buf_int)
    begin
        if (hb_gtwiz_reset_all_int)      link_down_latched_out <= 1'b1;
        else if (link_latch_reset_comb)  link_down_latched_out <= 1'b0;
        else if (!link_up_raw)           link_down_latched_out <= 1'b1;
    end

    // ============================================================
    // DEBUG BUS (core domain)
    // NOTE:
    //  - dbg is for ILA/telemetry only
    //  - SERDES_STATUS is now built from dedicated inputs to axi_ctrl
    // ============================================================
    assign dbg[0]     = hb_gtwiz_reset_all_int;
    assign dbg[1]     = link_up_raw;
    assign dbg[2]     = link_down_latched_out;
    assign dbg[3]     = link_latch_reset_comb;

    assign dbg[7:4]   = gtpowergood_int;
    assign dbg[11:8]  = txpmaresetdone_int;
    assign dbg[15:12] = rxpmaresetdone_int;

    assign dbg[16]    = gtwiz_reset_tx_done_int;
    assign dbg[17]    = gtwiz_reset_rx_done_int;
    assign dbg[18]    = gtwiz_reset_rx_cdr_stable_int;

    assign dbg[19]    = gtwiz_userclk_tx_active_int;
    assign dbg[20]    = gtwiz_userclk_rx_active_int;

    assign dbg[25]    = refclk_out;

    assign dbg[29:26] = pll_lock_out;
    assign dbg[63:30] = '0;

    // ============================================================
    // AXI CTRL
    // ============================================================
    murosync_serdes_array_axi_ctrl #(
        .C_S00_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH),
        .C_S00_AXI_NUM_REGS   (C_S00_AXI_NUM_REGS)
    ) u_axi_ctrl 
    (
        // AXI
        .s00_axi_aclk     (s00_axi_aclk),
        .s00_axi_aresetn  (s00_axi_aresetn),
        .s00_axi_awaddr   (s00_axi_awaddr),
        .s00_axi_awprot   (s00_axi_awprot),
        .s00_axi_awvalid  (s00_axi_awvalid),
        .s00_axi_awready  (s00_axi_awready),
        .s00_axi_wdata    (s00_axi_wdata),
        .s00_axi_wstrb    (s00_axi_wstrb),
        .s00_axi_wvalid   (s00_axi_wvalid),
        .s00_axi_wready   (s00_axi_wready),
        .s00_axi_bresp    (s00_axi_bresp),
        .s00_axi_bvalid   (s00_axi_bvalid),
        .s00_axi_bready   (s00_axi_bready),
        .s00_axi_araddr   (s00_axi_araddr),
        .s00_axi_arprot   (s00_axi_arprot),
        .s00_axi_arvalid  (s00_axi_arvalid),
        .s00_axi_arready  (s00_axi_arready),
        .s00_axi_rdata    (s00_axi_rdata),
        .s00_axi_rresp    (s00_axi_rresp),
        .s00_axi_rvalid   (s00_axi_rvalid),
        .s00_axi_rready   (s00_axi_rready),

        // Core domain
        .core_clk          (hb_gtwiz_reset_clk_freerun_buf_int),
        .core_reset_all_in (hb_gtwiz_reset_all_int),

        // CONTROL OUT
        .loopback_ctrl                (loopback_ctrl),
        .link_down_latched_reset_pulse (link_latch_reset_axi),
        .gt_reset_all_pulse            (gt_reset_all_pulse_axi),

        // STATUS IN (core_clk domain)
        .link_up           (link_status_out),
        .link_down_latched (link_down_latched_out),
        .pll_lock_in       (pll_lock_int),

        // New dedicated status vectors (core_clk domain)
        .gtpowergood_in    (gtpowergood_int),
        .txpmaresetdone_in (txpmaresetdone_int),
        .rxpmaresetdone_in (rxpmaresetdone_int),

        // Debug-only bus
        .dbg_in            (dbg),

        // Link Integrity Testing
        .link_test_ctrl_rst_axi_pulse (link_test_ctrl_rst_axi_pulse),
        .link_test_ctrl_en_core       (link_test_ctrl_en_core),
        .link_test_cnfg               (link_test_cnfg),
        .link_test_patt               (link_test_patt),
        .link_test_err_cnt            (link_test_err_cnt),
        .link_test_wrd_cnt            (link_test_wrd_cnt),

        // Diagnostic inputs from link test engine
        .link_test_fsm_state          (link_test_diag_fsm_state),
        .link_test_rx_aligned         (link_test_diag_rx_aligned),
        .link_test_rx_aligned_seen    (link_test_diag_rx_aligned_seen),
        .link_test_rx_charisk         (link_test_diag_rx_charisk),
        .link_test_checker_locked     (link_test_diag_checker_locked),
        .link_test_rx_data            (link_test_diag_rx_data),
        .link_test_exp_data           (link_test_diag_exp_data),

        // Diagnostic inputs from link test engine (TX)
        .link_test_tx_data            (link_test_diag_tx_data),
        .link_test_tx_counter_ch0     (link_test_diag_tx_counter_ch0),
        .link_test_tx_counter_ch1     (link_test_diag_tx_counter_ch1),
        .link_test_tx_counter_ch2     (link_test_diag_tx_counter_ch2),
        .link_test_tx_counter_ch3     (link_test_diag_tx_counter_ch3),
        .link_test_tx_comma_active    (link_test_diag_tx_comma_active),
        .link_test_tx_comma_count     (link_test_diag_tx_comma_count),
        .link_test_ever_locked        (link_test_diag_ever_locked),
        .link_test_last_fsm_state     (link_test_diag_last_fsm_state),

        // Tier 2 link_test diagnostic inputs
        .link_test_time_to_lock          (link_test_diag_time_to_lock),
        .link_test_locked_cycle_cnt      (link_test_diag_locked_cycle_cnt),
        .link_test_rx_data_at_lock       (link_test_diag_rx_data_at_lock),
        .link_test_rx_data_at_first_err  (link_test_diag_rx_data_at_first_err),
        .link_test_exp_data_at_first_err (link_test_diag_exp_data_at_first_err),
        .link_test_err_cnt_ch0           (link_test_diag_err_cnt_ch0),
        .link_test_err_cnt_ch1           (link_test_diag_err_cnt_ch1),
        .link_test_err_cnt_ch2           (link_test_diag_err_cnt_ch2),
        .link_test_err_cnt_ch3           (link_test_diag_err_cnt_ch3),

        // Tier 2 GT sticky counters
        .gt_debug_rxbyterealign_cnt      (gt_debug_rxbyterealign_cnt_int),
        .gt_debug_eyescandataerror_cnt   (gt_debug_eyescandataerror_cnt_int),

        // GT debug signals from wrapper
        .gt_debug_rxcommadet_out      (gt_debug_rxcommadet_int),
        .gt_debug_rxbyteisaligned_out (gt_debug_rxbyteisaligned_int),
        .gt_debug_rxbyterealign_out   (gt_debug_rxbyterealign_int),
        .gt_debug_rxbufstatus_out     (gt_debug_rxbufstatus_int),
        .gt_debug_txbufstatus_out     (gt_debug_txbufstatus_int),
        .gt_debug_rxsyncdone_out      (gt_debug_rxsyncdone_int),
        .gt_debug_rxphaligndone_out   (gt_debug_rxphaligndone_int),
        .gt_debug_eyescandataerror_out(gt_debug_eyescandataerror_int),
        .gt_debug_rxresetdone_out     (gt_debug_rxresetdone_int),
        .gt_debug_txresetdone_out     (gt_debug_txresetdone_int),
        .gt_debug_rxpmaresetdone_out  (rxpmaresetdone_int),
        .gt_debug_txpmaresetdone_out  (txpmaresetdone_int),

        // Snapshot valid bits — Tier 2
        .link_test_rx_data_at_lock_valid (link_test_diag_rx_data_at_lock_valid),
        .link_test_first_err_valid       (link_test_diag_first_err_valid)
    );

    // Wire declarations - must come BEFORE GT wrapper instantiation to avoid implicit 1-bit nets
    wire [63:0] link_test_tx_data;
    wire [63:0] gtwiz_userdata_rx_int;
    wire        gt_userclk_rx_usrclk2_int;
    wire        gt_userclk_tx_usrclk2_int;
    wire [7:0]  link_test_txctrl2;  // TXCHARISK: K28.5 comma control from link test
    wire [31:0] rxctrl2_int;   // RXBYTEISALIGNED + RXBYTEISCOMMA (8 bits × 4 channels)
                               // NOTE: connected to GT but not currently consumed.
                               // rxbyteisaligned is sourced from dedicated wizard port
                               // (gt_debug_rxbyteisaligned_int) — see u_link_test inst.
                               // Reserved for future diagnostics (BYTEISCOMMA, etc).
    wire [63:0] rxctrl0_int;   // RXCHARISK + RXCHARISCOMMA (16 bits × 4 channels)
    wire [31:0] rxctrl3_int;   // RXNOTINTABLE (8 bits × 4 channels) — kept for future diagnostics

    wire [3:0]  gt_debug_rxcommadet_int;
    wire [3:0]  gt_debug_rxbyteisaligned_int;
    wire [3:0]  gt_debug_rxbyterealign_int;
    wire [11:0] gt_debug_rxbufstatus_int;
    wire [7:0]  gt_debug_txbufstatus_int;
    wire [3:0]  gt_debug_rxsyncdone_int;
    wire [3:0]  gt_debug_rxphaligndone_int;
    wire [3:0]  gt_debug_eyescandataerror_int;
    wire [3:0]  gt_debug_rxresetdone_int;
    wire [3:0]  gt_debug_txresetdone_int;

    // ============================================================
    // RXCHARISK extraction from RXCTRL0
    // ============================================================
    // Per pg182 (v1.7) page 2886: rxctrl0_out = 16 × Num.channels
    // For 4 channels, rxctrl0_int is [63:0], packed as:
    //   CH0 (X0Y4) → rxctrl0_int[15:0]
    //   CH1 (X0Y5) → rxctrl0_int[31:16]
    //   CH2 (X0Y6) → rxctrl0_int[47:32]
    //   CH3 (X0Y7) → rxctrl0_int[63:48]
    //
    // Within each 16-bit per-channel slice, for 8B/10B + 16-bit user data:
    //   bit [0] = RXCHARISK byte 0 (lower byte)
    //   bit [1] = RXCHARISK byte 1 (upper byte)
    //   bits [15:2] = RXCHARISCOMMA / RXDISPERR / unused (depends on RX internal data width)
    //
    // Per pg182 page 4469: "active portion is least significant bit-aligned"
    // Reference: ADI util_adxcvr_xch.v: .RXCTRL0({rx_charisk_open_s, rx_charisk})
    //
    // We OR byte0 | byte1 because either K-symbol byte should flag the cycle as
    // containing control characters — the link-test checker uses this to skip
    // K-symbol cycles when counting data words.
    //
    // History: prior implementation pulled rxcharisk from RXCTRL3 which is
    // RXNOTINTABLE (8B/10B decode error). On non-aligned channels NOTINTABLE
    // is high most of the time, which masqueraded as "K-symbols detected"
    // while in reality the bytes were undecodable garbage. Fixed 2026-05-20.
    wire [3:0]  rxcharisk_int = {
        rxctrl0_int[49] | rxctrl0_int[48],  // CH3 (X0Y7): rxctrl0[16*3+1:16*3] = [49:48]
        rxctrl0_int[33] | rxctrl0_int[32],  // CH2 (X0Y6): rxctrl0[16*2+1:16*2] = [33:32]
        rxctrl0_int[17] | rxctrl0_int[16],  // CH1 (X0Y5): rxctrl0[16*1+1:16*1] = [17:16]
        rxctrl0_int[1]  | rxctrl0_int[0]    // CH0 (X0Y4): rxctrl0[16*0+1:16*0] = [1:0]
    };

    // ============================================================
    // GT wrapper (simplified wrapper internally uses murosync_gtwizard_ports)
    // ============================================================
    murosync_gt_wrapper #(
        .NCH          (4),
        .TX_MASTER_CH (0),
        .RX_MASTER_CH (0)
    ) u_gtw 
    (
        .gthrxn_in  (gthrxn_int),
        .gthrxp_in  (gthrxp_int),
        .gthtxn_out (gthtxn_int),
        .gthtxp_out (gthtxp_int),

        .gtwiz_reset_clk_freerun_in (hb_gtwiz_reset_clk_freerun_buf_int),

        // rollback-safe: keep ONLY external reset applied to GT
        //.gtwiz_reset_all_in (hb_gtwiz_reset_all_int),
        .gtwiz_reset_all_in (hb_gtwiz_reset_all_int | gt_reset_all_pulse_axi),

        // Tie off extra reset controls (unused in this top-level right now)
        .gtwiz_reset_tx_pll_and_datapath_in (1'b0),
        .gtwiz_reset_tx_datapath_in         (1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in (1'b0),
        .gtwiz_reset_rx_datapath_in         (1'b0),

        .gtwiz_userdata_tx_in (link_test_ctrl_en_core ? link_test_tx_data : 64'h0),
        .gtwiz_userdata_rx_out(gtwiz_userdata_rx_int),

        // Feed the GT reference clock (raw from IBUFDS_GTE4)
        .gtrefclk00_in      (mgtrefclk0_x0y1_int),
        .qpll0outclk_out    (),
        .qpll0outrefclk_out (),

        // 8B10B encoder/decoder enabled — required for K28.5 comma detection
        .rx8b10ben_in ({4{1'b1}}),
        .tx8b10ben_in ({4{1'b1}}),
        .txctrl0_in   (64'h0),
        .txctrl1_in   (64'h0),
        .txctrl2_in ({
            6'h0, link_test_txctrl2[7:6],   // CH3 (X0Y7): TXCHARISK at [25:24]
            6'h0, link_test_txctrl2[5:4],   // CH2 (X0Y6): TXCHARISK at [17:16]
            6'h0, link_test_txctrl2[3:2],   // CH1 (X0Y5): TXCHARISK at [9:8]
            6'h0, link_test_txctrl2[1:0]    // CH0 (X0Y4): TXCHARISK at [1:0]
        }),

        .gtpowergood_out            (gtpowergood_int),
        .rxctrl0_out                (rxctrl0_int),
        .rxctrl1_out                (),
        .rxctrl2_out                (rxctrl2_int),  // rxbyteisaligned + rxbyteiscomma
        .rxctrl3_out                (rxctrl3_int),  // RXNOTINTABLE — diagnostic only

        .rxpmaresetdone_out         (rxpmaresetdone_int),
        .txpmaresetdone_out         (txpmaresetdone_int),

        .gtwiz_reset_rx_cdr_stable_out (gtwiz_reset_rx_cdr_stable_int),
        .gtwiz_reset_tx_done_out       (gtwiz_reset_tx_done_int),
        .gtwiz_reset_rx_done_out       (gtwiz_reset_rx_done_int),

        .gtwiz_userclk_tx_active_out   (gtwiz_userclk_tx_active_int),
        .gtwiz_userclk_rx_active_out   (gtwiz_userclk_rx_active_int),

        // GT debug signals
        .gt_debug_rxcommadet_out      (gt_debug_rxcommadet_int),
        .gt_debug_rxbyteisaligned_out (gt_debug_rxbyteisaligned_int),
        .gt_debug_rxbyterealign_out   (gt_debug_rxbyterealign_int),
        .gt_debug_rxbufstatus_out     (gt_debug_rxbufstatus_int),
        .gt_debug_txbufstatus_out     (gt_debug_txbufstatus_int),
        .gt_debug_rxsyncdone_out      (gt_debug_rxsyncdone_int),
        .gt_debug_rxphaligndone_out   (gt_debug_rxphaligndone_int),
        .gt_debug_eyescandataerror_out(gt_debug_eyescandataerror_int),
        .gt_debug_rxresetdone_out     (gt_debug_rxresetdone_int),
        .gt_debug_txresetdone_out     (gt_debug_txresetdone_int),

        // rollback-safe: force normal mode while debugging (3 bits per channel)
        //.loopback_in ({4{3'b000}}),
        .loopback_in ({4{loopback_ctrl}}),

        // raw lock outs (optional, reserved for future debug)
        .cplllock_out  (),
        .qpll0lock_out (),
        .qpll1lock_out (),

        .pll_lock_out (pll_lock_int),
        
        .gtwiz_userclk_rx_recclk_out(gtwiz_userclk_rx_recclk_int),
        .gtwiz_userclk_rx_recclk_active_out(gtwiz_userclk_rx_recclk_alive_int),

        .gtwiz_userclk_rx_usrclk2_out (gt_userclk_rx_usrclk2_int),
        .gtwiz_userclk_tx_usrclk2_out (gt_userclk_tx_usrclk2_int),

        // Tier 2 GT sticky event counters
        .gt_debug_rxbyterealign_cnt_out    (gt_debug_rxbyterealign_cnt_int),
        .gt_debug_eyescandataerror_cnt_out (gt_debug_eyescandataerror_cnt_int)
    );

    // ============================================================
    // Link Test Engine — CDC into GT clock domains
    // ============================================================

    // enable: freerun domain (link_test_ctrl_en_core) → rx_clk domain
    wire link_test_enable_rx;
    murosync_cdc_level_sync #(.WIDTH(1), .SYNC_STAGES(2)) u_cdc_lte_en_rx (
        .clk   (gt_userclk_rx_usrclk2_int),
        .rst_n (gtwiz_userclk_rx_active_int),
        .in    (link_test_ctrl_en_core),
        .out   (link_test_enable_rx)
    );

    // enable: freerun domain → tx_clk domain
    wire link_test_enable_tx;
    murosync_cdc_level_sync #(.WIDTH(1), .SYNC_STAGES(2)) u_cdc_lte_en_tx (
        .clk   (gt_userclk_tx_usrclk2_int),
        .rst_n (gtwiz_userclk_tx_active_int),
        .in    (link_test_ctrl_en_core),
        .out   (link_test_enable_tx)
    );

    // reset_counters: freerun domain → rx_clk domain
    wire link_test_rst_cnt_rx;
    murosync_cdc_level_sync #(.WIDTH(1), .SYNC_STAGES(2)) u_cdc_lte_rst_rx (
        .clk   (gt_userclk_rx_usrclk2_int),
        .rst_n (gtwiz_userclk_rx_active_int),
        .in    (link_test_ctrl_rst_axi_pulse),
        .out   (link_test_rst_cnt_rx)
    );

    // reset_counters: freerun domain → tx_clk domain
    wire link_test_rst_cnt_tx;
    murosync_cdc_level_sync #(.WIDTH(1), .SYNC_STAGES(2)) u_cdc_lte_rst_tx (
        .clk   (gt_userclk_tx_usrclk2_int),
        .rst_n (gtwiz_userclk_tx_active_int),
        .in    (link_test_ctrl_rst_axi_pulse),
        .out   (link_test_rst_cnt_tx)
    );

    murosync_serdes_link_test #(
        .IS_SLAVE (IS_SLAVE)
    ) u_link_test (
        .tx_clk            (gt_userclk_tx_usrclk2_int),
        .rx_clk            (gt_userclk_rx_usrclk2_int),
        .core_rst_n        (gtwiz_userclk_rx_active_int),
        .tx_enable_in      (link_test_enable_tx),
        .rx_enable_in      (link_test_enable_rx),
        .tx_reset_counters (link_test_rst_cnt_tx),
        .rx_reset_counters (link_test_rst_cnt_rx),
        .cnfg            (link_test_cnfg),
        .fixed_patt      (link_test_patt),
        .rxbyteisaligned (gt_debug_rxbyteisaligned_int),  // Clean per-channel signal from GT Wizard dedicated port
                                                          //   (was: manual unpacking from rxctrl2_int — bit position
                                                          //    was wrong for current IP configuration; bypassed.
                                                          //    Verified by ground-truth probe 2026-05-21.)
        .rxcharisk       (rxcharisk_int),           // K-symbol indicator — skip in checker
        .tx_data         (link_test_tx_data),
        .rx_data         (gtwiz_userdata_rx_int),
        .txctrl2_out     (link_test_txctrl2),      // 8B10B K-symbol control
        .err_cnt         (link_test_err_cnt),
        .wrd_cnt         (link_test_wrd_cnt),

        // Diagnostic outputs → axi_ctrl → AXI registers → firmware
        .diag_fsm_state        (link_test_diag_fsm_state),
        .diag_rx_aligned       (link_test_diag_rx_aligned),
        .diag_rx_aligned_seen  (link_test_diag_rx_aligned_seen),
        .diag_rx_charisk       (link_test_diag_rx_charisk),
        .diag_checker_locked   (link_test_diag_checker_locked),
        .diag_rx_data          (link_test_diag_rx_data),
        .diag_exp_data         (link_test_diag_exp_data),

        // Diagnostic outputs (TX)
        .diag_tx_data           (link_test_diag_tx_data),
        .diag_tx_counter_ch0    (link_test_diag_tx_counter_ch0),
        .diag_tx_counter_ch1    (link_test_diag_tx_counter_ch1),
        .diag_tx_counter_ch2    (link_test_diag_tx_counter_ch2),
        .diag_tx_counter_ch3    (link_test_diag_tx_counter_ch3),
        .diag_tx_comma_active   (link_test_diag_tx_comma_active),
        .diag_tx_comma_count    (link_test_diag_tx_comma_count),
        .diag_ever_locked       (link_test_diag_ever_locked),
        .diag_last_fsm_state    (link_test_diag_last_fsm_state),

        // Tier 2 diagnostic outputs from link_test
        .diag_time_to_lock          (link_test_diag_time_to_lock),
        .diag_locked_cycle_cnt      (link_test_diag_locked_cycle_cnt),
        .diag_rx_data_at_lock       (link_test_diag_rx_data_at_lock),
        .diag_rx_data_at_first_err  (link_test_diag_rx_data_at_first_err),
        .diag_exp_data_at_first_err (link_test_diag_exp_data_at_first_err),
        .diag_err_cnt_ch0           (link_test_diag_err_cnt_ch0),
        .diag_err_cnt_ch1           (link_test_diag_err_cnt_ch1),
        .diag_err_cnt_ch2           (link_test_diag_err_cnt_ch2),
        .diag_err_cnt_ch3           (link_test_diag_err_cnt_ch3),
        .diag_rx_data_at_lock_valid (link_test_diag_rx_data_at_lock_valid),
        .diag_first_err_valid       (link_test_diag_first_err_valid)
    );

endmodule
`default_nettype wire
