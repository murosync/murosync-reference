`timescale 1ps/1ps

module murosync_serdes_array (

  // Differential reference clock inputs
  input  wire mgtrefclk0_x0y1_p,
  input  wire mgtrefclk0_x0y1_n,

  // Serial data ports for transceiver channel 0
  input  wire ch0_gthrxn_in,
  input  wire ch0_gthrxp_in,
  output wire ch0_gthtxn_out,
  output wire ch0_gthtxp_out,

  // Serial data ports for transceiver channel 1
  input  wire ch1_gthrxn_in,
  input  wire ch1_gthrxp_in,
  output wire ch1_gthtxn_out,
  output wire ch1_gthtxp_out,

  // Serial data ports for transceiver channel 2
  input  wire ch2_gthrxn_in,
  input  wire ch2_gthrxp_in,
  output wire ch2_gthtxn_out,
  output wire ch2_gthtxp_out,

  // Serial data ports for transceiver channel 3
  input  wire ch3_gthrxn_in,
  input  wire ch3_gthrxp_in,
  output wire ch3_gthtxn_out,
  output wire ch3_gthtxp_out,

  // User-provided ports for reset helper block(s)
  input  wire hb_gtwiz_reset_clk_freerun_in,
  input  wire hb_gtwiz_reset_all_in,

  // Link status ports
  input  wire link_down_latched_reset_in,
  output wire link_status_out,
  output reg  link_down_latched_out = 1'b1,

  // Debug outputs for ILA (connect these to ILA probes in top project)
  output wire [63:0] dbg,
  output wire        refclk_out     // optional, convenient probe
);

  // ============================================================
  // PER-CHANNEL SIGNAL ASSIGNMENTS
  // ============================================================

  wire [3:0] gthrxn_int;
  assign gthrxn_int[0] = ch0_gthrxn_in;
  assign gthrxn_int[1] = ch1_gthrxn_in;
  assign gthrxn_int[2] = ch2_gthrxn_in;
  assign gthrxn_int[3] = ch3_gthrxn_in;

  wire [3:0] gthrxp_int;
  assign gthrxp_int[0] = ch0_gthrxp_in;
  assign gthrxp_int[1] = ch1_gthrxp_in;
  assign gthrxp_int[2] = ch2_gthrxp_in;
  assign gthrxp_int[3] = ch3_gthrxp_in;

  wire [3:0] gthtxn_int;
  assign ch0_gthtxn_out = gthtxn_int[0];
  assign ch1_gthtxn_out = gthtxn_int[1];
  assign ch2_gthtxn_out = gthtxn_int[2];
  assign ch3_gthtxn_out = gthtxn_int[3];

  wire [3:0] gthtxp_int;
  assign ch0_gthtxp_out = gthtxp_int[0];
  assign ch1_gthtxp_out = gthtxp_int[1];
  assign ch2_gthtxp_out = gthtxp_int[2];
  assign ch3_gthtxp_out = gthtxp_int[3];

  // ============================================================
  // BUFFERS
  // ============================================================

  wire hb_gtwiz_reset_all_buf_int;
  IBUF u_ibuf_reset_all (
    .I (hb_gtwiz_reset_all_in),
    .O (hb_gtwiz_reset_all_buf_int)
  );

  // Free-running clock
  wire hb_gtwiz_reset_clk_freerun_buf_int;
  BUFG u_bufg_freerun (
    .I (hb_gtwiz_reset_clk_freerun_in),
    .O (hb_gtwiz_reset_clk_freerun_buf_int)
  );

  // Refclk
  wire mgtrefclk0_x0y1_int;
  IBUFDS_GTE4 #(
    .REFCLK_EN_TX_PATH  (1'b0),
    .REFCLK_HROW_CK_SEL (2'b00),
    .REFCLK_ICNTL_RX    (2'b00)
  ) u_ibufds_gte4_refclk (
    .I     (mgtrefclk0_x0y1_p),
    .IB    (mgtrefclk0_x0y1_n),
    .CEB   (1'b0),
    .O     (mgtrefclk0_x0y1_int),
    .ODIV2 ()
  );

  assign refclk_out = mgtrefclk0_x0y1_int;

  wire [0:0] gtrefclk00_int;
  assign gtrefclk00_int[0] = mgtrefclk0_x0y1_int;

  // Reset used by this wrapper (simple)
  wire hb_gtwiz_reset_all_int = hb_gtwiz_reset_all_buf_int;

  // ============================================================
  // GTWIZ signals (minimal set)
  // ============================================================

  // userclk helper i/f
  wire [0:0] gtwiz_userclk_tx_reset_int;
  wire [0:0] gtwiz_userclk_tx_srcclk_int;
  wire [0:0] gtwiz_userclk_tx_usrclk_int;
  wire [0:0] gtwiz_userclk_tx_usrclk2_int;
  wire [0:0] gtwiz_userclk_tx_active_int;

  wire [0:0] gtwiz_userclk_rx_reset_int;
  wire [0:0] gtwiz_userclk_rx_srcclk_int;
  wire [0:0] gtwiz_userclk_rx_usrclk_int;
  wire [0:0] gtwiz_userclk_rx_usrclk2_int;
  wire [0:0] gtwiz_userclk_rx_active_int;

  // reset i/f
  wire [0:0] gtwiz_reset_tx_pll_and_datapath_int;
  wire [0:0] gtwiz_reset_tx_datapath_int;
  wire [0:0] gtwiz_reset_rx_pll_and_datapath_int;
  wire [0:0] gtwiz_reset_rx_datapath_int;

  // status
  wire [0:0] gtwiz_reset_tx_done_int;
  wire [0:0] gtwiz_reset_rx_done_int;
  wire [0:0] gtwiz_reset_rx_cdr_stable_int;

  // clocks from common
  wire [0:0] qpll0outclk_int;
  wire [0:0] qpll0outrefclk_int;

  // per-channel status
  wire [3:0] gtpowergood_int;
  wire [3:0] rxpmaresetdone_int;
  wire [3:0] txpmaresetdone_int;

  // 8b10b enable
  wire [3:0] rx8b10ben_int = 4'b1111;
  wire [3:0] tx8b10ben_int = 4'b1111;

  // data/control (drive zeros for bring-up)
  wire [63:0] gtwiz_userdata_tx_int = 64'h0;
  wire [63:0] gtwiz_userdata_rx_int;

  wire [63:0] txctrl0_int = 64'h0;
  wire [63:0] txctrl1_int = 64'h0;
  wire [31:0] txctrl2_int = 32'h0;

  wire [63:0] rxctrl0_int;
  wire [63:0] rxctrl1_int;
  wire [31:0] rxctrl2_int;
  wire [31:0] rxctrl3_int;

  // USER CLOCKING RESETS (simple: hold userclk helper in reset until all channels report resetdone)
  assign gtwiz_userclk_tx_reset_int[0] = ~(&txpmaresetdone_int);
  assign gtwiz_userclk_rx_reset_int[0] = ~(&rxpmaresetdone_int);

  // reset requests to GT wizard (simple: tie to global reset)
  assign gtwiz_reset_tx_pll_and_datapath_int[0] = hb_gtwiz_reset_all_int;
  assign gtwiz_reset_tx_datapath_int[0]         = hb_gtwiz_reset_all_int;
  assign gtwiz_reset_rx_pll_and_datapath_int[0] = hb_gtwiz_reset_all_int;
  assign gtwiz_reset_rx_datapath_int[0]         = hb_gtwiz_reset_all_int;

  // ============================================================
  // LINK STATUS (bring-up definition: "GT is alive")
  // ============================================================

  wire link_up_raw =
      (&gtpowergood_int) &
      (&txpmaresetdone_int) &
      (&rxpmaresetdone_int) &
      gtwiz_reset_tx_done_int[0] &
      gtwiz_reset_rx_done_int[0] &
      gtwiz_userclk_tx_active_int[0] &
      gtwiz_userclk_rx_active_int[0];

  assign link_status_out = link_up_raw;

  always @(posedge hb_gtwiz_reset_clk_freerun_buf_int) begin
    if (hb_gtwiz_reset_all_int) begin
      link_down_latched_out <= 1'b1;
    end else if (link_down_latched_reset_in) begin
      link_down_latched_out <= 1'b0;
    end else if (!link_up_raw) begin
      link_down_latched_out <= 1'b1;
    end
  end

  // ============================================================
  // DEBUG BUS (connect to ILA probes)
  // ============================================================
  // dbg[ 0]    = reset_all (internal)
  // dbg[ 1]    = link_up_raw
  // dbg[ 2]    = link_down_latched_out
  // dbg[ 3]    = link_down_latched_reset_in
  // dbg[ 7:4]  = gtpowergood[3:0]
  // dbg[11:8]  = txpmaresetdone[3:0]
  // dbg[15:12] = rxpmaresetdone[3:0]
  // dbg[16]    = gtwiz_reset_tx_done
  // dbg[17]    = gtwiz_reset_rx_done
  // dbg[18]    = gtwiz_reset_rx_cdr_stable
  // dbg[19]    = gtwiz_userclk_tx_active
  // dbg[20]    = gtwiz_userclk_rx_active
  // dbg[21]    = gtwiz_userclk_tx_reset (into helper)
  // dbg[22]    = gtwiz_userclk_rx_reset (into helper)
  // dbg[23]    = hb_gtwiz_reset_clk_freerun_in (raw, before BUFG)
  // dbg[24]    = hb_gtwiz_reset_clk_freerun_buf_int (after BUFG)
  // dbg[25]    = refclk_out (after IBUFDS_GTE4)
  // dbg[63:26] = reserved

  assign dbg[0]    = hb_gtwiz_reset_all_int;
  assign dbg[1]    = link_up_raw;
  assign dbg[2]    = link_down_latched_out;
  assign dbg[3]    = link_down_latched_reset_in;

  assign dbg[7:4]  = gtpowergood_int;
  assign dbg[11:8] = txpmaresetdone_int;
  assign dbg[15:12]= rxpmaresetdone_int;

  assign dbg[16]   = gtwiz_reset_tx_done_int[0];
  assign dbg[17]   = gtwiz_reset_rx_done_int[0];
  assign dbg[18]   = gtwiz_reset_rx_cdr_stable_int[0];

  assign dbg[19]   = gtwiz_userclk_tx_active_int[0];
  assign dbg[20]   = gtwiz_userclk_rx_active_int[0];

  assign dbg[21]   = gtwiz_userclk_tx_reset_int[0];
  assign dbg[22]   = gtwiz_userclk_rx_reset_int[0];

  assign dbg[23]   = hb_gtwiz_reset_clk_freerun_in;
  assign dbg[24]   = hb_gtwiz_reset_clk_freerun_buf_int;
  assign dbg[25]   = refclk_out;

  assign dbg[63:26]= '0;

  // ============================================================
  // Xilinx wrapper instance (unchanged)
  // ============================================================

  gtwizard_ultrascale_0_example_wrapper example_wrapper_inst (
    .gthrxn_in                               (gthrxn_int)
   ,.gthrxp_in                               (gthrxp_int)
   ,.gthtxn_out                              (gthtxn_int)
   ,.gthtxp_out                              (gthtxp_int)

   ,.gtwiz_userclk_tx_reset_in               (gtwiz_userclk_tx_reset_int)
   ,.gtwiz_userclk_tx_srcclk_out             (gtwiz_userclk_tx_srcclk_int)
   ,.gtwiz_userclk_tx_usrclk_out             (gtwiz_userclk_tx_usrclk_int)
   ,.gtwiz_userclk_tx_usrclk2_out            (gtwiz_userclk_tx_usrclk2_int)
   ,.gtwiz_userclk_tx_active_out             (gtwiz_userclk_tx_active_int)

   ,.gtwiz_userclk_rx_reset_in               (gtwiz_userclk_rx_reset_int)
   ,.gtwiz_userclk_rx_srcclk_out             (gtwiz_userclk_rx_srcclk_int)
   ,.gtwiz_userclk_rx_usrclk_out             (gtwiz_userclk_rx_usrclk_int)
   ,.gtwiz_userclk_rx_usrclk2_out            (gtwiz_userclk_rx_usrclk2_int)
   ,.gtwiz_userclk_rx_active_out             (gtwiz_userclk_rx_active_int)

   ,.gtwiz_reset_clk_freerun_in              ({1{hb_gtwiz_reset_clk_freerun_buf_int}})
   ,.gtwiz_reset_all_in                      ({1{hb_gtwiz_reset_all_int}})

   ,.gtwiz_reset_tx_pll_and_datapath_in      (gtwiz_reset_tx_pll_and_datapath_int)
   ,.gtwiz_reset_tx_datapath_in              (gtwiz_reset_tx_datapath_int)
   ,.gtwiz_reset_rx_pll_and_datapath_in      (gtwiz_reset_rx_pll_and_datapath_int)
   ,.gtwiz_reset_rx_datapath_in              (gtwiz_reset_rx_datapath_int)

   ,.gtwiz_reset_rx_cdr_stable_out           (gtwiz_reset_rx_cdr_stable_int)
   ,.gtwiz_reset_tx_done_out                 (gtwiz_reset_tx_done_int)
   ,.gtwiz_reset_rx_done_out                 (gtwiz_reset_rx_done_int)

   ,.gtwiz_userdata_tx_in                    (gtwiz_userdata_tx_int)
   ,.gtwiz_userdata_rx_out                   (gtwiz_userdata_rx_int)

   ,.gtrefclk00_in                           (gtrefclk00_int)
   ,.qpll0outclk_out                         (qpll0outclk_int)
   ,.qpll0outrefclk_out                      (qpll0outrefclk_int)

   ,.rx8b10ben_in                            (rx8b10ben_int)
   ,.tx8b10ben_in                            (tx8b10ben_int)

   ,.txctrl0_in                              (txctrl0_int)
   ,.txctrl1_in                              (txctrl1_int)
   ,.txctrl2_in                              (txctrl2_int)

   ,.gtpowergood_out                         (gtpowergood_int)

   ,.rxctrl0_out                             (rxctrl0_int)
   ,.rxctrl1_out                             (rxctrl1_int)
   ,.rxctrl2_out                             (rxctrl2_int)
   ,.rxctrl3_out                             (rxctrl3_int)

   ,.rxpmaresetdone_out                      (rxpmaresetdone_int)
   ,.txpmaresetdone_out                      (txpmaresetdone_int)
  );

endmodule
