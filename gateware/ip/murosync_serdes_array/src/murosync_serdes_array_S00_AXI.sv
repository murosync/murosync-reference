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

module murosync_serdes_array_S00_AXI #(

    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer C_S_AXI_NUM_REGS   = 17,

    /*localparam*/ integer ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1,
    /*localparam*/ integer OPT_MEM_ADDR_BITS = $clog2(C_S_AXI_NUM_REGS) - 1

)(
    // Global Clock Signal
    input  wire                           S_AXI_ACLK,
    // Global Reset Signal. This Signal is Active LOW
    input  wire                           S_AXI_ARESETN,

    // Write address (issued by master, accepted by Slave)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]  S_AXI_AWADDR,
    input  wire [2:0]                     S_AXI_AWPROT,
    input  wire                           S_AXI_AWVALID,
    output wire                           S_AXI_AWREADY,

    // Write data (issued by master, accepted by Slave)
    input  wire [C_S_AXI_DATA_WIDTH-1:0]  S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                           S_AXI_WVALID,
    output wire                           S_AXI_WREADY,

    // Write response
    output wire [1:0]                     S_AXI_BRESP,
    output wire                           S_AXI_BVALID,
    input  wire                           S_AXI_BREADY,

    // Read address (issued by master, accepted by Slave)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]  S_AXI_ARADDR,
    input  wire [2:0]                     S_AXI_ARPROT,
    input  wire                           S_AXI_ARVALID,
    output wire                           S_AXI_ARREADY,

    // Read data (issued by slave)
    output wire [C_S_AXI_DATA_WIDTH-1:0]  S_AXI_RDATA,
    output wire [1:0]                     S_AXI_RRESP,
    output wire                           S_AXI_RVALID,
    input  wire                           S_AXI_RREADY,

    // register arrays
    output logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg    [0:C_S_AXI_NUM_REGS-1],
    input  logic [C_S_AXI_DATA_WIDTH-1:0] axi_reg_rd [0:C_S_AXI_NUM_REGS-1]
);

    // AXI4LITE signals
    reg  [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                           axi_awready;
    reg                           axi_wready;
    reg  [1:0]                    axi_bresp;
    reg                           axi_bvalid;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                           axi_arready;
    reg  [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg  [1:0]                    axi_rresp;
    reg                           axi_rvalid;

    wire                          slv_reg_rden;
    wire                          slv_reg_wren;
    reg  [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    integer                       byte_index;
    integer                       i;
    reg                           aw_en;

    // I/O Connections assignments
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // ------------------------------------------------------------
    // AWREADY
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0) 
        begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
        end 
        else 
        begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) 
            begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end 
            else if (S_AXI_BREADY && axi_bvalid) 
            begin
                aw_en       <= 1'b1;
                axi_awready <= 1'b0;
            end 
            else 
            begin
                axi_awready <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // AWADDR latch
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0)                                       axi_awaddr <= '0;
        else if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) axi_awaddr <= S_AXI_AWADDR;
    end

    // ------------------------------------------------------------
    // WREADY
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0) axi_wready <= 1'b0;
        else 
        begin
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en) axi_wready <= 1'b1;
            else                                                       axi_wready <= 1'b0;
        end
    end

    // ------------------------------------------------------------
    // WRITE into slv_reg[]
    // ------------------------------------------------------------
    localparam int CTRL_IDX = 0; // self-clearing W1P lives here

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0) 

            for (i = 0; i < C_S_AXI_NUM_REGS; i = i + 1)
                slv_reg[i] <= 32'h00000000;

        else if (slv_reg_wren) 

            for (i = 0; i < C_S_AXI_NUM_REGS; i = i + 1) 
                if (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == i[OPT_MEM_ADDR_BITS:0]) 
                    for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index + 1)
                        if (S_AXI_WSTRB[byte_index]) slv_reg[i][(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
        else 
            slv_reg[CTRL_IDX] <= 32'h00000000;
    end

    // ------------------------------------------------------------
    // BRESP/BVALID
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0) 
        begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end 
        else begin
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) 
            begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00; // OKAY
            end else if (S_AXI_BREADY && axi_bvalid) 
            begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // ARREADY + ARADDR latch
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0) 
        begin
            axi_arready <= 1'b0;
            axi_araddr  <= '0;
        end 
        else 
        begin
            if (~axi_arready && S_AXI_ARVALID) 
            begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end 
            else 
            begin
                axi_arready <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // RVALID/RRESP
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0) 
        begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end 
        else 
        begin
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) 
            begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00; // OKAY
            end 
            else if (axi_rvalid && S_AXI_RREADY) 
            begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Read mux from axi_reg_rd[]
    // ------------------------------------------------------------
    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

    always @(*) 
    begin
        reg_data_out = 32'h00000000;

        for (int j = 0; j < C_S_AXI_NUM_REGS; j = j + 1) 
            if (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == j)
                reg_data_out = axi_reg_rd[j];
    end

    // ------------------------------------------------------------
    // RDATA register
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) 
    begin
        if (S_AXI_ARESETN == 1'b0) axi_rdata <= 32'h00000000;
        else if (slv_reg_rden)     axi_rdata <= reg_data_out;
    end

endmodule
