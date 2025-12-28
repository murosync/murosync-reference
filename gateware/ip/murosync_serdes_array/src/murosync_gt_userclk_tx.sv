// Murosync: GT TX user clock helper (replacement for gtwizard_*_example_gtwiz_userclk_tx)
module murosync_gt_userclk_tx #(
  parameter int P_FREQ_RATIO_SOURCE_TO_USRCLK  = 1, // 1 => DIV=0
  parameter int P_FREQ_RATIO_USRCLK_TO_USRCLK2 = 1  // 1 => usrclk2=usrclk
)(
  input  wire gtwiz_userclk_tx_srcclk_in,
  input  wire gtwiz_userclk_tx_reset_in,     // active-high
  output wire gtwiz_userclk_tx_usrclk_out,
  output wire gtwiz_userclk_tx_usrclk2_out,
  output wire gtwiz_userclk_tx_active_out
);

  // BUFG_GT DIV is 3-bit value of (divide_by - 1)
  localparam int  P_USRCLK_INT_DIV  = (P_FREQ_RATIO_SOURCE_TO_USRCLK  < 1) ? 1 : P_FREQ_RATIO_SOURCE_TO_USRCLK;
  localparam int  P_USRCLK2_INT_DIV = (P_FREQ_RATIO_USRCLK_TO_USRCLK2 < 1) ? 1 : P_FREQ_RATIO_USRCLK_TO_USRCLK2;

  localparam int  USRCLK_DIV_M1  = P_USRCLK_INT_DIV - 1;
  localparam int  USRCLK2_DIV_M1 = (P_USRCLK_INT_DIV * P_USRCLK2_INT_DIV) - 1;

  localparam logic [2:0] P_USRCLK_DIV  = logic'(USRCLK_DIV_M1[2:0]);
  localparam logic [2:0] P_USRCLK2_DIV = logic'(USRCLK2_DIV_M1[2:0]);

  // TXUSRCLK
  BUFG_GT u_bufg_gt_txusrclk (
    .CE      (1'b1),
    .CEMASK  (1'b0),
    .CLR     (gtwiz_userclk_tx_reset_in),
    .CLRMASK (1'b0),
    .DIV     (P_USRCLK_DIV),
    .I       (gtwiz_userclk_tx_srcclk_in),
    .O       (gtwiz_userclk_tx_usrclk_out)
  );

  // TXUSRCLK2
  generate
    if (P_FREQ_RATIO_USRCLK_TO_USRCLK2 == 1) 
    begin : gen_same
      assign gtwiz_userclk_tx_usrclk2_out = gtwiz_userclk_tx_usrclk_out;
    end 
    else 
    begin : gen_div2
      BUFG_GT u_bufg_gt_txusrclk2 (
        .CE      (1'b1),
        .CEMASK  (1'b0),
        .CLR     (gtwiz_userclk_tx_reset_in),
        .CLRMASK (1'b0),
        .DIV     (P_USRCLK2_DIV),
        .I       (gtwiz_userclk_tx_srcclk_in),
        .O       (gtwiz_userclk_tx_usrclk2_out)
      );
    end
  endgenerate

  // ACTIVE flag: asserted once usrclk2 is running and reset is deasserted
  (* ASYNC_REG = "TRUE" *) reg active_meta = 1'b0;
  (* ASYNC_REG = "TRUE" *) reg active_sync = 1'b0;

  always_ff @(posedge gtwiz_userclk_tx_usrclk2_out or posedge gtwiz_userclk_tx_reset_in) 
  begin
    if (gtwiz_userclk_tx_reset_in) 
    begin
      active_meta <= 1'b0;
      active_sync <= 1'b0;
    end 
    else 
    begin
      active_meta <= 1'b1;
      active_sync <= active_meta;
    end
  end

  assign gtwiz_userclk_tx_active_out = active_sync;

endmodule
