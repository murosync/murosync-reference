/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_gtwizard_ports.sv
 * Created    : 2026-01-20
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   Stable port-level wrapper around the Xilinx GT Wizard instance.
 *
 *   This module isolates the vendor-generated GT Wizard from the rest of the
 *   MuroSync design by providing a project-controlled, version-stable
 *   interface. It forwards all GT data, clock, reset, and control signals,
 *   exports reset/status indicators, and derives a unified per-channel
 *   PLL lock vector for diagnostics and AXI-visible status.
 *
 *   User clock activity flags are passed through as telemetry only; all
 *   user-clock generation is handled outside of this module.
 *
 * Notes:
 *   - Intended to minimize churn when regenerating the GT Wizard.
 *   - `default_nettype none` is enforced to prevent implicit nets.
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

module murosync_gtwizard_ports #(
    parameter int NCH = 4
)(
    // ---------------- GT serial I/O ----------------
    input  wire [NCH-1:0] gthrxn_in,
    input  wire [NCH-1:0] gthrxp_in,
    output wire [NCH-1:0] gthtxn_out,
    output wire [NCH-1:0] gthtxp_out,

    // ---------------- Reset controller ----------------
    input  wire           gtwiz_reset_clk_freerun_in,
    input  wire           gtwiz_reset_all_in,
    input  wire           gtwiz_reset_tx_pll_and_datapath_in,
    input  wire           gtwiz_reset_tx_datapath_in,
    input  wire           gtwiz_reset_rx_pll_and_datapath_in,
    input  wire           gtwiz_reset_rx_datapath_in,

    // ---------------- Userclk activity (from your userclk modules) ----------------
    input  wire           gtwiz_userclk_tx_active_in,
    input  wire           gtwiz_userclk_rx_active_in,

    // ---------------- Reset status outputs (from wizard) ----------------
    output wire           gtwiz_reset_rx_cdr_stable_out,
    output wire           gtwiz_reset_tx_done_out,
    output wire           gtwiz_reset_rx_done_out,

    // ---------------- Userdata ----------------
    input  wire [63:0]    gtwiz_userdata_tx_in,
    output wire [63:0]    gtwiz_userdata_rx_out,

    // ---------------- Reference clock / QPLL clocks ----------------
    input  wire           gtrefclk00_in,
    output wire           qpll0outclk_out,
    output wire           qpll0outrefclk_out,

    // ---------------- 8b/10b enables ----------------
    input  wire [NCH-1:0] rx8b10ben_in,
    input  wire [NCH-1:0] tx8b10ben_in,

    // ---------------- TX control ----------------
    input  wire [63:0]    txctrl0_in,
    input  wire [63:0]    txctrl1_in,
    input  wire [31:0]    txctrl2_in,

    // ---------------- User clocks into GT ----------------
    input  wire [NCH-1:0] rxusrclk_in,
    input  wire [NCH-1:0] rxusrclk2_in,
    input  wire [NCH-1:0] txusrclk_in,
    input  wire [NCH-1:0] txusrclk2_in,

    // ---------------- Core status outputs (from wizard) ----------------
    output wire [NCH-1:0] gtpowergood_out,
    output wire [NCH-1:0] rxcdrlock_out,
    output wire [NCH-1:0] cplllock_out,

    output wire           qpll0lock_out,
    output wire           qpll1lock_out,

    output wire [63:0]    rxctrl0_out,
    output wire [63:0]    rxctrl1_out,
    output wire [31:0]    rxctrl2_out,
    output wire [31:0]    rxctrl3_out,

    output wire [NCH-1:0] rxoutclk_out,
    output wire [NCH-1:0] txoutclk_out,

    output wire [NCH-1:0] rxpmaresetdone_out,
    output wire [NCH-1:0] txpmaresetdone_out,

    // ---------------- Optional stable interface ----------------
    // GT Wizard loopback is typically 3 bits per channel.
    // NOTE: your current gtwizard_ultrascale_0 top does NOT have loopback_in port enabled.
    input  wire [3*NCH-1:0] loopback_in,

    // ---------------- GT Debug Ports ----------------
    output wire [NCH-1:0]   rxcommadet_out,
    output wire [NCH-1:0]   rxbyteisaligned_out,
    output wire [NCH-1:0]   rxbyterealign_out,
    output wire [3*NCH-1:0] rxbufstatus_out,
    output wire [2*NCH-1:0] txbufstatus_out,
    output wire [NCH-1:0]   rxsyncdone_out,
    output wire [NCH-1:0]   rxphaligndone_out,
    output wire [NCH-1:0]   eyescandataerror_out,
    output wire [NCH-1:0]   rxresetdone_out,
    output wire [NCH-1:0]   txresetdone_out,

    // ---------------- Superset exports ----------------
    output wire           userclk_tx_active_out,
    output wire           userclk_rx_active_out,

    // ---------------- Unified effective lock per channel ----------------
    output wire [NCH-1:0] pll_lock_vec_out
);

    // Export activity flags as telemetry
    assign userclk_tx_active_out = gtwiz_userclk_tx_active_in;
    assign userclk_rx_active_out = gtwiz_userclk_rx_active_in;

    // Universal "effective" lock: OR of all lock sources that may be used
    assign pll_lock_vec_out = cplllock_out
                            | {NCH{qpll0lock_out}}
                            | {NCH{qpll1lock_out}};

    gtwizard_ultrascale_0 u_gt (
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

        .gtwiz_userclk_tx_active_in         (gtwiz_userclk_tx_active_in),
        .gtwiz_userclk_rx_active_in         (gtwiz_userclk_rx_active_in),

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

        // Comma detection and alignment controls
        .rxcommadeten_in                    ({NCH{1'b1}}),
        .rxmcommaalignen_in                 ({NCH{1'b1}}),
        .rxpcommaalignen_in                 ({NCH{1'b1}}),
        .rxslide_in                         ({NCH{1'b0}}),

        .rxusrclk_in                        (rxusrclk_in),
        .rxusrclk2_in                       (rxusrclk2_in),
        .txusrclk_in                        (txusrclk_in),
        .txusrclk2_in                       (txusrclk2_in),

        .gtpowergood_out                    (gtpowergood_out),
        .rxcdrlock_out                      (rxcdrlock_out),
        .cplllock_out                       (cplllock_out),
        .qpll0lock_out                      (qpll0lock_out),
        .qpll1lock_out                      (qpll1lock_out),

        .rxctrl0_out                        (rxctrl0_out),
        .rxctrl1_out                        (rxctrl1_out),
        .rxctrl2_out                        (rxctrl2_out),
        .rxctrl3_out                        (rxctrl3_out),

        .rxoutclk_out                       (rxoutclk_out),
        .txoutclk_out                       (txoutclk_out),

        .rxpmaresetdone_out                 (rxpmaresetdone_out),
        .txpmaresetdone_out                 (txpmaresetdone_out),

        .rxcommadet_out                     (rxcommadet_out),
        .rxbyteisaligned_out                (rxbyteisaligned_out),
        .rxbyterealign_out                  (rxbyterealign_out),
        .rxbufstatus_out                    (rxbufstatus_out),
        .txbufstatus_out                    (txbufstatus_out),
        .rxsyncdone_out                     (rxsyncdone_out),
        .rxphaligndone_out                  (rxphaligndone_out),
        .eyescandataerror_out               (eyescandataerror_out),
        .rxresetdone_out                    (rxresetdone_out),
        .txresetdone_out                    (txresetdone_out),

        .loopback_in                        (loopback_in)
    );

endmodule

`default_nettype wire
