/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_serdes_array_mode.sv
 * Created    : 2026-01-27
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   Mode-aware top wrapper for murosync_serdes_array.
 *
 *   Single reusable IP for Block Design instantiation (x3 for XCAU15P):
 *     - MODE="MASTER": all 4 channels are considered functional
 *     - MODE="SLAVE" : CH0 is the sync link, CH1..CH3 are optional AUX
 *
 *   Channel enable mask affects link/status qualification so disabled lanes
 *   do not block LINK_UP and do not pollute diagnostics.
 *
 * Notes:
 *   - Physical ports stay identical (ch0..ch3). MODE only changes semantics
 *     and status qualification (and optionally GUI-visible ports via IP packager).
 *
 * Copyright (c) 2026 Mikhail Vasilev / MuroSync
 * License: Restricted research license. Commercial use requires agreement.
 ******************************************************************************/

`default_nettype none

module murosync_serdes_array_mode #(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_NUM_REGS   = 7,

    // GUI-friendly mode selector (for IP customization)
    parameter string  MODE                = "MASTER", // "MASTER" / "SLAVE"

    // Enabled channels mask (bit0=CH0 ... bit3=CH3)
    // - MASTER default: all enabled
    // - SLAVE default : only CH0 enabled (AUX can be enabled explicitly)
    parameter logic [3:0] CH_EN            = (MODE == "SLAVE") ? 4'b0001 : 4'b1111,

    // Keep same addr-width convention as before
    parameter integer OPT_MEM_ADDR_BITS    = $clog2(C_S00_AXI_NUM_REGS),
    parameter integer ADDR_WIDTH_NEEDED    = OPT_MEM_ADDR_BITS + 3
)(
    // Differential reference clock inputs
    input  wire mgtrefclk0_x0y1_p,
    input  wire mgtrefclk0_x0y1_n,

    // Serial data ports for transceiver channel 0..3
    input  wire ch0_gthrxn_in,
    input  wire ch0_gthrxp_in,
    output wire ch0_gthtxn_out,
    output wire ch0_gthtxp_out,

    input  wire ch1_gthrxn_in,
    input  wire ch1_gthrxp_in,
    output wire ch1_gthtxn_out,
    output wire ch1_gthtxp_out,

    input  wire ch2_gthrxn_in,
    input  wire ch2_gthrxp_in,
    output wire ch2_gthtxn_out,
    output wire ch2_gthtxp_out,

    input  wire ch3_gthrxn_in,
    input  wire ch3_gthrxp_in,
    output wire ch3_gthtxn_out,
    output wire ch3_gthtxp_out,

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

    // AXI4-Lite slave interface (INTEGRATED)
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

    // ------------------------------------------------------------
    // Internals: reuse your existing murosync_serdes_array “core”
    // but override LINK_UP qualification using CH_EN mask.
    // ------------------------------------------------------------

    // Channel buses
    wire [3:0] gthrxn_int = {ch3_gthrxn_in, ch2_gthrxn_in, ch1_gthrxn_in, ch0_gthrxn_in};
    wire [3:0] gthrxp_int = {ch3_gthrxp_in, ch2_gthrxp_in, ch1_gthrxp_in, ch0_gthrxp_in};
    wire [3:0] gthtxn_int, gthtxp_int;

    assign {ch3_gthtxn_out, ch2_gthtxn_out, ch1_gthtxn_out, ch0_gthtxn_out} = gthtxn_int;
    assign {ch3_gthtxp_out, ch2_gthtxp_out, ch1_gthtxp_out, ch0_gthtxp_out} = gthtxp_int;

    // Buffers / refclk (copy-paste из твоего murosync_serdes_array.sv)
    wire hb_gtwiz_reset_all_buf_int;
    IBUF u_ibuf_reset_all (.I(hb_gtwiz_reset_all_in), .O(hb_gtwiz_reset_all_buf_int));

    wire hb_gtwiz_reset_clk_freerun_buf_int;
    BUFG u_bufg_freerun (.I(hb_gtwiz_reset_clk_freerun_in), .O(hb_gtwiz_reset_clk_freerun_buf_int));

    wire mgtrefclk0_x0y1_int, mgtrefclk0_x0y1_odiv2_int;
    IBUFDS_GTE4 #(
        .REFCLK_EN_TX_PATH  (1'b0),
        .REFCLK_HROW_CK_SEL (2'b00),
        .REFCLK_ICNTL_RX    (2'b00)
    ) u_ibufds_gte4_refclk (
        .I     (mgtrefclk0_x0y1_p),
        .IB    (mgtrefclk0_x0y1_n),
        .CEB   (1'b0),
        .O     (mgtrefclk0_x0y1_int),
        .ODIV2 (mgtrefclk0_x0y1_odiv2_int)
    );

    wire mgtrefclk0_x0y1_div2_bufg;
    BUFG_GT u_bufg_gt_refclk_div2 (
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

    // GT status
    wire [3:0] gtpowergood_int;
    wire [3:0] rxpmaresetdone_int;
    wire [3:0] txpmaresetdone_int;
    wire       gtwiz_reset_tx_done_int;
    wire       gtwiz_reset_rx_done_int;
    wire       gtwiz_userclk_tx_active_int;
    wire       gtwiz_userclk_rx_active_int;
    wire [3:0] pll_lock_int;

    // AXI control (from axi_ctrl)
    wire [2:0] loopback_ctrl;
    wire       link_latch_reset_axi;
    wire       gt_reset_all_pulse_axi;

    // -------------------------
    // Masking for “enabled lanes”
    // -------------------------
    // If lane disabled => treat as “already OK” for link qualification,
    // and also optionally blank it in status vectors.
    wire [3:0] en = CH_EN;

    wire [3:0] gtp_ok  = (gtpowergood_int     | ~en);
    wire [3:0] tx_ok   = (txpmaresetdone_int  | ~en);
    wire [3:0] rx_ok   = (rxpmaresetdone_int  | ~en);

    wire link_up_raw = (&gtp_ok) &
                       (&tx_ok) &
                       (&rx_ok) &
                       gtwiz_reset_tx_done_int &
                       gtwiz_reset_rx_done_int &
                       gtwiz_userclk_tx_active_int &
                       gtwiz_userclk_rx_active_int;

    assign link_status_out = link_up_raw;
    assign pll_lock_out    = pll_lock_int;

    // Link latch (как у тебя)
    wire link_latch_reset_comb = link_down_latched_reset_in | link_latch_reset_axi;

    always @(posedge hb_gtwiz_reset_clk_freerun_buf_int) begin
        if (hb_gtwiz_reset_all_int)      link_down_latched_out <= 1'b1;
        else if (link_latch_reset_comb)  link_down_latched_out <= 1'b0;
        else if (!link_up_raw)           link_down_latched_out <= 1'b1;
    end

    // Debug bus (оставил совместимым)
    assign dbg[0]     = hb_gtwiz_reset_all_int;
    assign dbg[1]     = link_up_raw;
    assign dbg[2]     = link_down_latched_out;
    assign dbg[3]     = link_latch_reset_comb;

    assign dbg[7:4]   = gtpowergood_int;
    assign dbg[11:8]  = txpmaresetdone_int;
    assign dbg[15:12] = rxpmaresetdone_int;

    assign dbg[16]    = gtwiz_reset_tx_done_int;
    assign dbg[17]    = gtwiz_reset_rx_done_int;
    assign dbg[19]    = gtwiz_userclk_tx_active_int;
    assign dbg[20]    = gtwiz_userclk_rx_active_int;

    assign dbg[25]    = refclk_out;
    assign dbg[29:26] = pll_lock_out;
    assign dbg[63:30] = '0;

    // AXI CTRL (как у тебя, но можно передавать “сырые” векторы как есть)
    murosync_serdes_array_axi_ctrl #(
        .C_S00_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH),
        .C_S00_AXI_NUM_REGS   (C_S00_AXI_NUM_REGS)
    ) u_axi_ctrl (
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

        .core_clk          (hb_gtwiz_reset_clk_freerun_buf_int),
        .core_reset_all_in (hb_gtwiz_reset_all_int),

        .loopback_ctrl                (loopback_ctrl),
        .link_down_latched_reset_pulse (link_latch_reset_axi),
        .gt_reset_all_pulse            (gt_reset_all_pulse_axi),

        .link_up           (link_status_out),
        .link_down_latched (link_down_latched_out),
        .pll_lock_in       (pll_lock_int),

        .gtpowergood_in    (gtpowergood_int),
        .txpmaresetdone_in (txpmaresetdone_int),
        .rxpmaresetdone_in (rxpmaresetdone_int),

        .dbg_in            (dbg)
    );

    // GT wrapper (твой)
    murosync_gt_wrapper #(
        .NCH          (4),
        .TX_MASTER_CH (0),
        .RX_MASTER_CH (0)
    ) u_gtw (
        .gthrxn_in  (gthrxn_int),
        .gthrxp_in  (gthrxp_int),
        .gthtxn_out (gthtxn_int),
        .gthtxp_out (gthtxp_int),

        .gtwiz_reset_clk_freerun_in (hb_gtwiz_reset_clk_freerun_buf_int),

        // rollback-safe: external reset only (можно включить OR с pulse позже)
        .gtwiz_reset_all_in (hb_gtwiz_reset_all_int),

        .gtwiz_reset_tx_pll_and_datapath_in (1'b0),
        .gtwiz_reset_tx_datapath_in         (1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in (1'b0),
        .gtwiz_reset_rx_datapath_in         (1'b0),

        .gtwiz_userdata_tx_in (64'h0),
        .gtwiz_userdata_rx_out(),

        .gtrefclk00_in      (mgtrefclk0_x0y1_int),
        .qpll0outclk_out    (),
        .qpll0outrefclk_out (),

        .rx8b10ben_in ({4{1'b0}}),
        .tx8b10ben_in ({4{1'b0}}),
        .txctrl0_in   (64'h0),
        .txctrl1_in   (64'h0),
        .txctrl2_in   (32'h0),

        .gtpowergood_out            (gtpowergood_int),
        .rxcdrlock_out              (),
        .rxctrl0_out                (),
        .rxctrl1_out                (),
        .rxctrl2_out                (),
        .rxctrl3_out                (),

        .rxpmaresetdone_out         (rxpmaresetdone_int),
        .txpmaresetdone_out         (txpmaresetdone_int),

        .gtwiz_reset_rx_cdr_stable_out (),
        .gtwiz_reset_tx_done_out       (gtwiz_reset_tx_done_int),
        .gtwiz_reset_rx_done_out       (gtwiz_reset_rx_done_int),

        .gtwiz_userclk_tx_active_out   (gtwiz_userclk_tx_active_int),
        .gtwiz_userclk_rx_active_out   (gtwiz_userclk_rx_active_int),

        // loopback: можешь оставить forced 000 или дать управление
        .loopback_in ({4{3'b000}}),

        .cplllock_out  (),
        .qpll0lock_out (),
        .qpll1lock_out (),

        .pll_lock_out (pll_lock_int)
    );

endmodule

`default_nettype wire
