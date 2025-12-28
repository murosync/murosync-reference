module murosync_gt_wrapper #(
  parameter int NCH = 4,
  parameter int TX_MASTER_CH = 0,
  parameter int RX_MASTER_CH = 0,

  // userclk ratios (match Xilinx helper behavior)
  // TXUSRCLK  = srcclk / P_TX_FREQ_RATIO_SOURCE_TO_USRCLK
  // TXUSRCLK2 = TXUSRCLK / P_TX_FREQ_RATIO_USRCLK_TO_USRCLK2
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
  output wire [63:0]    rxctrl0_out,
  output wire [63:0]    rxctrl1_out,
  output wire [31:0]    rxctrl2_out,
  output wire [31:0]    rxctrl3_out,

  output wire [NCH-1:0] rxpmaresetdone_out,
  output wire [NCH-1:0] txpmaresetdone_out,

  // optional status from userclk helpers
  output wire           gtwiz_userclk_tx_active_out,
  output wire           gtwiz_userclk_rx_active_out
);

  // ------------------------------------------------------------
  // Clocks from GT core
  // ------------------------------------------------------------
  wire [NCH-1:0] txoutclk_int;
  wire [NCH-1:0] rxoutclk_int;

  // ------------------------------------------------------------
  // User clock helper blocks (source = master channel outclk)
  // ------------------------------------------------------------
  wire gtwiz_userclk_tx_usrclk;
  wire gtwiz_userclk_tx_usrclk2;

  wire gtwiz_userclk_rx_usrclk;
  wire gtwiz_userclk_rx_usrclk2;

  // Hold helper blocks in reset until the GT says PMA reset done
  wire gtwiz_userclk_tx_reset = ~(&txpmaresetdone_out);
  wire gtwiz_userclk_rx_reset = ~(&rxpmaresetdone_out);

  // ------------------ UPDATED: use murosync_gt_userclk_* ------------------
  murosync_gt_userclk_tx #(
    .P_FREQ_RATIO_SOURCE_TO_USRCLK  (P_TX_FREQ_RATIO_SOURCE_TO_USRCLK),
    .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (P_TX_FREQ_RATIO_USRCLK_TO_USRCLK2)
  ) u_userclk_tx (
    .gtwiz_userclk_tx_srcclk_in   (txoutclk_int[TX_MASTER_CH]),
    .gtwiz_userclk_tx_reset_in    (gtwiz_userclk_tx_reset),
    .gtwiz_userclk_tx_usrclk_out  (gtwiz_userclk_tx_usrclk),
    .gtwiz_userclk_tx_usrclk2_out (gtwiz_userclk_tx_usrclk2),
    .gtwiz_userclk_tx_active_out  (gtwiz_userclk_tx_active_out)
  );

  murosync_gt_userclk_rx #(
    .P_FREQ_RATIO_SOURCE_TO_USRCLK  (P_RX_FREQ_RATIO_SOURCE_TO_USRCLK),
    .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (P_RX_FREQ_RATIO_USRCLK_TO_USRCLK2)
  ) u_userclk_rx (
    .gtwiz_userclk_rx_srcclk_in   (rxoutclk_int[RX_MASTER_CH]),
    .gtwiz_userclk_rx_reset_in    (gtwiz_userclk_rx_reset),
    .gtwiz_userclk_rx_usrclk_out  (gtwiz_userclk_rx_usrclk),
    .gtwiz_userclk_rx_usrclk2_out (gtwiz_userclk_rx_usrclk2),
    .gtwiz_userclk_rx_active_out  (gtwiz_userclk_rx_active_out)
  );
  // -----------------------------------------------------------------------

  // replicate to all channels
  wire [NCH-1:0] txusrclk_int  = {NCH{gtwiz_userclk_tx_usrclk}};
  wire [NCH-1:0] txusrclk2_int = {NCH{gtwiz_userclk_tx_usrclk2}};

  wire [NCH-1:0] rxusrclk_int  = {NCH{gtwiz_userclk_rx_usrclk}};
  wire [NCH-1:0] rxusrclk2_int = {NCH{gtwiz_userclk_rx_usrclk2}};

  // ------------------------------------------------------------
  // GT core
  // ------------------------------------------------------------
  gtwizard_ultrascale_0 u_gt (
    .gthrxn_in                          (gthrxn_in),
    .gthrxp_in                          (gthrxp_in),
    .gthtxn_out                         (gthtxn_out),
    .gthtxp_out                         (gthtxp_out),

    .gtwiz_userclk_tx_active_in         (gtwiz_userclk_tx_active_out),
    .gtwiz_userclk_rx_active_in         (gtwiz_userclk_rx_active_out),

    .gtwiz_reset_clk_freerun_in         (gtwiz_reset_clk_freerun_in),
    .gtwiz_reset_all_in                 (gtwiz_reset_all_in),
    .gtwiz_reset_tx_pll_and_datapath_in (gtwiz_reset_tx_pll_and_datapath_in),
    .gtwiz_reset_tx_datapath_in         (gtwiz_reset_tx_datapath_in),
    .gtwiz_reset_rx_pll_and_datapath_in (gtwiz_reset_rx_pll_and_datapath_in),
    .gtwiz_reset_rx_datapath_in         (gtwiz_reset_rx_datapath_in),

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
    .rxctrl0_out                        (rxctrl0_out),
    .rxctrl1_out                        (rxctrl1_out),
    .rxctrl2_out                        (rxctrl2_out),
    .rxctrl3_out                        (rxctrl3_out),

    .rxoutclk_out                       (rxoutclk_int),
    .txoutclk_out                       (txoutclk_int),

    .rxpmaresetdone_out                 (rxpmaresetdone_out),
    .txpmaresetdone_out                 (txpmaresetdone_out)
  );

endmodule
