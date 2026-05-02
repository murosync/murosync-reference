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
    parameter integer C_S00_AXI_NUM_REGS   = 12,

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
    output wire [1:0]                          link_test_cnfg,
    output wire [31:0]                         link_test_patt,
    input  wire [31:0]                         link_test_err_cnt,
    input  wire [31:0]                         link_test_wrd_cnt
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
    localparam int SERDES_LNK_TEST_CNFG  = 'h8;  // RW Offset 0x20: [1:0]-Test Mode select
    localparam int SERDES_LNK_TEST_PATT  = 'h9;  // RW Offset 0x24: Fixed Test Pattern
    localparam int SERDES_LNK_RX_ERR_CNT = 'hA;  // RO Offset 0x28: RX Error Counter
    localparam int SERDES_LNK_RX_WRD_CNT = 'hB;  // RO Offset 0x2C: RX Word Counter (Received)

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
    wire [1:0] link_test_cnfg_axi     = slv_reg[SERDES_LNK_TEST_CNFG];
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

    (* ASYNC_REG="TRUE" *) logic [1:0] lb0_link_test_cnfg_sync, lb1_link_test_cnfg_sync;
    always @(posedge core_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            lb0_link_test_cnfg_sync <= 2'b00;
            lb1_link_test_cnfg_sync <= 2'b00;

        end 
        else 
        begin
            lb0_link_test_cnfg_sync <= {lb0_link_test_cnfg_sync[0], link_test_cnfg_axi[0]};
            lb1_link_test_cnfg_sync <= {lb1_link_test_cnfg_sync[0], link_test_cnfg_axi[1]};
        end
    end
    assign link_test_cnfg = {lb1_link_test_cnfg_sync[1], lb0_link_test_cnfg_sync[1]};


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


endmodule
`default_nettype wire
