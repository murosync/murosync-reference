/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_gt_wrapper.sv
 * Created    : 2026-01-20
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   N-channel GT Wizard wrapper with deterministic user-clock generation.
 *
 *   Selects one TX and one RX master channel for outclk sourcing, generates
 *   TXUSRCLK/TXUSRCLK2 and RXUSRCLK/RXUSRCLK2 via dedicated helper blocks,
 *   and fan-outs the resulting user clocks to all GT channels. The actual
 *   GT Wizard instance is isolated behind `murosync_gtwizard_ports` to keep
 *   the top-level stable across Wizard re-generation/port changes.
 *
 *   Exposes firmware-friendly status/telemetry: per-channel gtpowergood,
 *   rxcdrlock, pmaresetdone, and PLL lock vectors, plus reset-done and
 *   userclk-active flags.
 *
 * Notes:
 *   - `default_nettype none` is used to prevent implicit nets.
 *   - Loopback is provided as 3 bits per channel (standard GT loopback bus).
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

module murosync_gt_wrapper #(

    parameter int NCH = 4,
    parameter int TX_MASTER_CH = 0,
    parameter int RX_MASTER_CH = 0,
    parameter bit IS_SLAVE = 1'b0,

    parameter int P_TX_FREQ_RATIO_SOURCE_TO_USRCLK  = 1,
    parameter int P_TX_FREQ_RATIO_USRCLK_TO_USRCLK2 = 1,
    parameter int P_RX_FREQ_RATIO_SOURCE_TO_USRCLK  = 1,
    parameter int P_RX_FREQ_RATIO_USRCLK_TO_USRCLK2 = 1
)(
    input  wire [NCH-1:0] gthrxn_in,
    input  wire [NCH-1:0] gthrxp_in,
    output wire [NCH-1:0] gthtxn_out,
    output wire [NCH-1:0] gthtxp_out,

    input  wire           gtwiz_reset_clk_freerun_in,
    input  wire           gtwiz_reset_all_in,

    input  wire           gtwiz_reset_tx_pll_and_datapath_in,
    input  wire           gtwiz_reset_tx_datapath_in,
    input  wire           gtwiz_reset_rx_pll_and_datapath_in,
    input  wire           gtwiz_reset_rx_datapath_in,

    output wire           gtwiz_reset_rx_cdr_stable_out,
    output wire           gtwiz_reset_tx_done_out,
    output wire           gtwiz_reset_rx_done_out,

    input  wire [63:0]    gtwiz_userdata_tx_in,
    output wire [63:0]    gtwiz_userdata_rx_out,

    input  wire           gtrefclk00_in,
    output wire           qpll0outclk_out,
    output wire           qpll0outrefclk_out,

    input  wire [NCH-1:0] rx8b10ben_in,
    input  wire [NCH-1:0] tx8b10ben_in,

    input  wire [63:0]    txctrl0_in,
    input  wire [63:0]    txctrl1_in,
    input  wire [31:0]    txctrl2_in,

    output wire [NCH-1:0] gtpowergood_out,  
    output wire [NCH-1:0] rxcdrlock_out,
    output wire [63:0]    rxctrl0_out,
    output wire [63:0]    rxctrl1_out,
    output wire [31:0]    rxctrl2_out,
    output wire [31:0]    rxctrl3_out,

    output wire [NCH-1:0] rxpmaresetdone_out,
    output wire [NCH-1:0] txpmaresetdone_out,

    output wire           gtwiz_userclk_tx_active_out,
    output wire           gtwiz_userclk_rx_active_out,

    // 3 bits per channel (GT loopback bus)
    input  wire [3*NCH-1:0] loopback_in,

    // Raw lock indicators (useful for AXI status)
    output wire [NCH-1:0] cplllock_out,
    output wire           qpll0lock_out,
    output wire           qpll1lock_out,

    // Unified lock per-channel (derived)
    output wire [NCH-1:0] pll_lock_out,
    
    // Recovered clock
    output wire gtwiz_userclk_rx_recclk_out,
    output wire gtwiz_userclk_rx_recclk_active_out,

    // 312.5 MHz GT datapath clocks (for clocking logic in RXUSRCLK2/TXUSRCLK2 domain)
    output wire gtwiz_userclk_rx_usrclk2_out,
    output wire gtwiz_userclk_tx_usrclk2_out,

    //=== GT DEBUG PORTS ===//
    output wire [NCH-1:0]   gt_debug_rxcommadet_out,
    output wire [NCH-1:0]   gt_debug_rxbyteisaligned_out, 
    output wire [NCH-1:0]   gt_debug_rxbyterealign_out,
    output wire [3*NCH-1:0] gt_debug_rxbufstatus_out,
    output wire [2*NCH-1:0] gt_debug_txbufstatus_out,
    output wire [NCH-1:0]   gt_debug_rxsyncdone_out,
    output wire [NCH-1:0]   gt_debug_rxphaligndone_out,
    output wire [NCH-1:0]   gt_debug_eyescandataerror_out,
    output wire [NCH-1:0]   gt_debug_rxresetdone_out,
    output wire [NCH-1:0]   gt_debug_txresetdone_out,

    // Tier 2 GT sticky event counters (packed 16-bit per channel, NCH channels)
    output wire [NCH*16-1:0] gt_debug_rxbyterealign_cnt_out,     // 16-bit per channel, accumulated rxbyterealign pulses
    output wire [NCH*16-1:0] gt_debug_eyescandataerror_cnt_out   // 16-bit per channel, accumulated eyescandataerror pulses
);

    // --------------------------------------------------------------------------
    // GT outclks (from wizard) used as sources for userclk generation
    // --------------------------------------------------------------------------
    wire [NCH-1:0] txoutclk_int;
    wire [NCH-1:0] rxoutclk_int;

    // --------------------------------------------------------------------------
    // User clocks generated from selected master channel
    // --------------------------------------------------------------------------
    wire gtwiz_userclk_tx_usrclk;
    wire gtwiz_userclk_tx_usrclk2;
    wire gtwiz_userclk_rx_usrclk;
    wire gtwiz_userclk_rx_usrclk2;

    // RX userclk reset — same in both modes.
    wire gtwiz_userclk_rx_reset_int =
         gtwiz_reset_all_in |
         gtwiz_reset_rx_pll_and_datapath_in |
         gtwiz_reset_rx_datapath_in;

    // TX userclk reset.
    //   MASTER: gated by TX-datapath events (TX clock is local TXOUTCLK).
    //   SLAVE (loop timing): TX user clock is sourced from the RX recovered
    //     clock, so it must be reset by the SAME events as the RX userclk.
    //     Otherwise the TX BUFG_GT could release CLR on a recovered clock that
    //     has not locked yet (RX CDR is not ready until MASTER sends commas),
    //     asserting tx_active on an unstable clock. Tie TX reset to RX on SLAVE.
    wire gtwiz_userclk_tx_reset_int = IS_SLAVE ?
         gtwiz_userclk_rx_reset_int :
        (gtwiz_reset_all_in |
         gtwiz_reset_tx_pll_and_datapath_in |
         gtwiz_reset_tx_datapath_in);

    murosync_gt_userclk_tx #(
        .P_FREQ_RATIO_SOURCE_TO_USRCLK  (P_TX_FREQ_RATIO_SOURCE_TO_USRCLK),
        .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (P_TX_FREQ_RATIO_USRCLK_TO_USRCLK2)
    ) u_userclk_tx (
        // Loop timing: SLAVE clocks its TX user domain from the RX recovered
        // clock (RXOUTCLK of master RX channel) so tx_clk == rx_clk in fabric,
        // making the link_test cascade (rx_data_r<=rx_data, txctrl2_out<=
        // rxcharisk) safe same-clock registers. MASTER keeps its own TXOUTCLK.
        // BUFG_GT passes either source transparently (helper is BUFG_GT).
        .gtwiz_userclk_tx_srcclk_in   (IS_SLAVE ? rxoutclk_int[RX_MASTER_CH]
                                                : txoutclk_int[TX_MASTER_CH]),
        .gtwiz_userclk_tx_reset_in    (gtwiz_userclk_tx_reset_int),
        .gtwiz_userclk_tx_usrclk_out  (gtwiz_userclk_tx_usrclk),
        .gtwiz_userclk_tx_usrclk2_out (gtwiz_userclk_tx_usrclk2),
        .gtwiz_userclk_tx_active_out  (gtwiz_userclk_tx_active_out)
    );

    murosync_gt_userclk_rx #(
        .P_FREQ_RATIO_SOURCE_TO_USRCLK  (P_RX_FREQ_RATIO_SOURCE_TO_USRCLK),
        .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (P_RX_FREQ_RATIO_USRCLK_TO_USRCLK2)
    ) u_userclk_rx (
        .gtwiz_userclk_rx_srcclk_in   (rxoutclk_int[RX_MASTER_CH]),
        .gtwiz_userclk_rx_reset_in    (gtwiz_userclk_rx_reset_int),
        .gtwiz_userclk_rx_usrclk_out  (gtwiz_userclk_rx_usrclk),
        .gtwiz_userclk_rx_usrclk2_out (gtwiz_userclk_rx_usrclk2),
        .gtwiz_userclk_rx_active_out  (gtwiz_userclk_rx_active_out)
    );

    // Replicate user clocks to all channels
    wire [NCH-1:0] txusrclk_int  = {NCH{gtwiz_userclk_tx_usrclk}};
    wire [NCH-1:0] txusrclk2_int = {NCH{gtwiz_userclk_tx_usrclk2}};
    wire [NCH-1:0] rxusrclk_int  = {NCH{gtwiz_userclk_rx_usrclk}};
    wire [NCH-1:0] rxusrclk2_int = {NCH{gtwiz_userclk_rx_usrclk2}};
    
    // --------------------------------------------------------------------------
    // GT outclks (from wizard) used as sources for userclk generation
    // --------------------------------------------------------------------------
    // Export recovered RX fabric clock (RXUSRCLK2) from selected master channel.
    // In SLAVE instantiation, RX_MASTER_CH = 0 corresponds to SLAVE[0] lane (in serdes_array packing).
    assign gtwiz_userclk_rx_recclk_out = gtwiz_userclk_rx_usrclk2;

    // NOTE: gtwiz_userclk_rx_active_out is an "RXUSRCLK2 domain alive" latch (clock toggled after reset).
    // It does NOT guarantee CDR lock / link stability. For "true valid", combine with:
    //   rxcdrlock_out[RX_MASTER_CH] and gtwiz_reset_rx_cdr_stable_out.
    assign gtwiz_userclk_rx_recclk_active_out = gtwiz_userclk_rx_active_out;

    // Export 312.5 MHz datapath clocks for external logic clocked in the GT user domain
    assign gtwiz_userclk_rx_usrclk2_out = gtwiz_userclk_rx_usrclk2;
    assign gtwiz_userclk_tx_usrclk2_out = gtwiz_userclk_tx_usrclk2;

    // --------------------------------------------------------------------------
    // GT Wizard ports wrapper (stable interface)
    // --------------------------------------------------------------------------
    murosync_gtwizard_ports #(
        .NCH(NCH)
    ) u_ports 
    (
        .gthrxn_in                          (gthrxn_in),
        .gthrxp_in                          (gthrxp_in),
        .gthtxn_out                         (gthtxn_out),
        .gthtxp_out                         (gthtxp_out),

        .gtwiz_reset_clk_freerun_in         (gtwiz_reset_clk_freerun_in),
        .gtwiz_reset_all_in                 (gtwiz_reset_all_in),
        .gtwiz_reset_tx_pll_and_datapath_in (gtwiz_reset_tx_pll_and_datapath_in),
        .gtwiz_reset_tx_datapath_in         (gtwiz_reset_tx_datapath_in),
        .gtwiz_reset_rx_pll_and_datapath_in (gtwiz_reset_rx_pll_and_datapath_in),
        .gtwiz_reset_rx_datapath_in         (gtwiz_reset_rx_datapath_in),

        .gtwiz_userclk_tx_active_in         (gtwiz_userclk_tx_active_out),
        .gtwiz_userclk_rx_active_in         (gtwiz_userclk_rx_active_out),

        .gtwiz_reset_rx_cdr_stable_out      (gtwiz_reset_rx_cdr_stable_out),
        .gtwiz_reset_tx_done_out            (gtwiz_reset_tx_done_out),
        .gtwiz_reset_rx_done_out            (gtwiz_reset_rx_done_out),

        .gtwiz_userdata_tx_in               (gtwiz_userdata_tx_in),
        .gtwiz_userdata_rx_out              (gtwiz_userdata_rx_out),

        .gtrefclk00_in                      (gtrefclk00_in),
        .qpll0outclk_out                    (qpll0outclk_out),
        .qpll0outrefclk_out                 (qpll0outrefclk_out),

        .rx8b10ben_in                       (rx8b10ben_in),
        .tx8b10ben_in                       (tx8b10ben_in),

        .txctrl0_in                         (txctrl0_in),
        .txctrl1_in                         (txctrl1_in),
        .txctrl2_in                         (txctrl2_in),

        .rxusrclk_in                        (rxusrclk_int),
        .rxusrclk2_in                       (rxusrclk2_int),
        .txusrclk_in                        (txusrclk_int),
        .txusrclk2_in                       (txusrclk2_int),

        .gtpowergood_out                    (gtpowergood_out),
        .rxcdrlock_out                      (rxcdrlock_out),
        .rxctrl0_out                        (rxctrl0_out),
        .rxctrl1_out                        (rxctrl1_out),
        .rxctrl2_out                        (rxctrl2_out),
        .rxctrl3_out                        (rxctrl3_out),

        .rxoutclk_out                       (rxoutclk_int),
        .txoutclk_out                       (txoutclk_int),

        .rxpmaresetdone_out                 (rxpmaresetdone_out),
        .txpmaresetdone_out                 (txpmaresetdone_out),

        .loopback_in                        (loopback_in),

        .cplllock_out                       (cplllock_out),
        .qpll0lock_out                      (qpll0lock_out),
        .qpll1lock_out                      (qpll1lock_out),

        .rxcommadet_out                     (gt_debug_rxcommadet_out),
        .rxbyteisaligned_out                (gt_debug_rxbyteisaligned_out),
        .rxbyterealign_out                  (gt_debug_rxbyterealign_out),
        .rxbufstatus_out                    (gt_debug_rxbufstatus_out),
        .txbufstatus_out                    (gt_debug_txbufstatus_out),
        .rxsyncdone_out                     (gt_debug_rxsyncdone_out),
        .rxphaligndone_out                  (gt_debug_rxphaligndone_out),
        .eyescandataerror_out               (gt_debug_eyescandataerror_out),
        .rxresetdone_out                    (gt_debug_rxresetdone_out),
        .txresetdone_out                    (gt_debug_txresetdone_out),

        .pll_lock_vec_out                   (pll_lock_out)
    );

    // ============================================================
    // Tier 2: rxbyterealign sticky event counters — per channel
    // rxbyterealign is a 1-cycle pulse from GT Wizard signalling that the
    // GT re-acquired byte alignment. Each pulse counted separately.
    // Frequent pulses indicate channel instability.
    // Width: 16 bits per channel (65535 events max).
    // Clock: gt_userclk_rx_usrclk2 (RXUSRCLK2 domain).
    // Reset: asynchronous positive-edge gtwiz_reset_all_in.
    // CDC: handled in axi_ctrl (level_sync, eventual consistency — acceptable for diagnostics).
    // ============================================================
    wire gt_userclk_rx_usrclk2_int = gtwiz_userclk_rx_usrclk2;

    reg [15:0] rxbyterealign_cnt [0:NCH-1];

    genvar gi_rea;
    generate
        for (gi_rea = 0; gi_rea < NCH; gi_rea = gi_rea + 1) begin : g_rxbyterealign_cnt
            always @(posedge gt_userclk_rx_usrclk2_int or posedge gtwiz_reset_all_in)
            begin
                if (gtwiz_reset_all_in)                                rxbyterealign_cnt[gi_rea] <= 16'b0;
                else if (gt_debug_rxbyterealign_out[gi_rea])           rxbyterealign_cnt[gi_rea] <= rxbyterealign_cnt[gi_rea] + 1;
            end
        end
    endgenerate

    // ============================================================
    // Tier 2: eyescandataerror sticky event counters — per channel
    // eyescandataerror pulses from GT Wizard when eye scan logic detects
    // a bit error during sampling. Direct signal quality indicator.
    // Width: 16 bits per channel.
    // Reset: tied to gtwiz_reset_all_in.
    // ============================================================
    reg [15:0] eyescandataerror_cnt [0:NCH-1];

    genvar gi_eye;
    generate
        for (gi_eye = 0; gi_eye < NCH; gi_eye = gi_eye + 1) begin : g_eyescan_cnt
            always @(posedge gt_userclk_rx_usrclk2_int or posedge gtwiz_reset_all_in)
            begin
                if (gtwiz_reset_all_in)                                  eyescandataerror_cnt[gi_eye] <= 16'b0;
                else if (gt_debug_eyescandataerror_out[gi_eye])          eyescandataerror_cnt[gi_eye] <= eyescandataerror_cnt[gi_eye] + 1;
            end
        end
    endgenerate

    // Pack per-channel sticky counters into flat vectors for cleaner port mapping
    genvar gi_pack;
    generate
        for (gi_pack = 0; gi_pack < NCH; gi_pack = gi_pack + 1) begin : g_pack_sticky
            assign gt_debug_rxbyterealign_cnt_out[gi_pack*16 +: 16]    = rxbyterealign_cnt[gi_pack];
            assign gt_debug_eyescandataerror_cnt_out[gi_pack*16 +: 16] = eyescandataerror_cnt[gi_pack];
        end
    endgenerate

endmodule

`default_nettype wire
