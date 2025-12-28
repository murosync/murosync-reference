`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        Murosync
// Engineer:       Mikhail Vasilev
//
// Project:        murosync_poc
// File:           murosync_poc_top.sv
// Module:         murosync_poc_top
//
// Purpose:        Proof-of-Concept timing synchronization node.
//                 Unified gateware for both MASTER and SLAVE roles.
//
// Role Selection:
//   ROLE = 1  -> MASTER
//   ROLE = 0  -> SLAVE
//   Default behavior:
//     - If SFP link is active        -> SLAVE
//     - If no active SFP link found -> MASTER
//
// Key Features:
//   - Deterministic time synchronization over high-speed links
//   - Phase measurement using DDMTD
//   - Delay and phase compensation
//   - Configurable trigger generation at absolute time
//   - Trigger time-difference measurement between nodes
//   - Target timing accuracy: < 100 ps
//
// Target Hardware:
//   - FPGA:         XCAU15P-FFVB676-2-I (Artix UltraScale+, Industrial)
//   - Board:        [Fill: board name / revision]
//   - Transceivers: GTH (up to 16.3 Gb/s)
//   - SFP:          [Fill: port / refclk details]
//
// Toolchain:
//   - Vivado / Vitis: 2022.2
//
// Clocking:
//   - Fabric clock:  [e.g. 100 MHz]
//   - GT reference:  [e.g. 125 MHz / 156.25 MHz]
//
// Intellectual Property Notice:
//   This source code and related design materials are the
//   proprietary intellectual property of Murosync.
//
//   Unauthorized copying, modification, distribution, or use
//   of this file, in whole or in part, without explicit written
//   permission from Murosync is strictly prohibited.
//
//   This code is provided for internal development, evaluation,
//   and demonstration purposes only and must not be disclosed
//   to third parties without prior authorization.
//
// Revision History:
//   0.01  2025-12-14  Initial file created
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module murosync_poc_top(
    input  wire        sys_clk_p,
    input  wire        sys_clk_n,
    input  wire        rst_n,
    output reg  [1:0]  led,

    input  wire        gth_ref_p,
    input  wire        gth_ref_n,

    input  wire        sfp0_rx_p,
    input  wire        sfp0_rx_n,

    input  wire        sfp1_rx_p,
    input  wire        sfp1_rx_n,

    input  wire        sfp2_rx_p,
    input  wire        sfp2_rx_n,

    input  wire        sfp3_rx_p,
    input  wire        sfp3_rx_n,

    output wire        sfp0_tx_p,
    output wire        sfp0_tx_n,

    output wire        sfp1_tx_p,
    output wire        sfp1_tx_n,

    output wire        sfp2_tx_p,
    output wire        sfp2_tx_n,

    output wire        sfp3_tx_p,
    output wire        sfp3_tx_n,
    
    output wire        uart_tx,
    input  wire        uart_rx
);

    wire axi_rst_tst;
    wire locked_tst;
        
    bd_murosync_poc
        bd_murosync_poc(

        /*[i] */    .GTH_REF_P(gth_ref_p),
        /*[i] */    .GTH_REF_N(gth_ref_n),

        /*[i] */    .GTH_IN_CH0_RX_P(sfp0_rx_p),
        /*[i] */    .GTH_IN_CH0_RX_N(sfp0_rx_n),
        /*[o] */    .GTH_OUT_CH0_TX_P(sfp0_tx_p),
        /*[o] */    .GTH_OUT_CH0_TX_N(sfp0_tx_n),

        /*[i] */    .GTH_IN_CH1_RX_P(sfp1_rx_p),
        /*[i] */    .GTH_IN_CH1_RX_N(sfp1_rx_n),
        /*[o] */    .GTH_OUT_CH1_TX_P(sfp1_tx_p),
        /*[o] */    .GTH_OUT_CH1_TX_N(sfp1_tx_n),

        /*[i] */    .GTH_IN_CH2_RX_P(sfp2_rx_p),
        /*[i] */    .GTH_IN_CH2_RX_N(sfp2_rx_n),
        /*[o] */    .GTH_OUT_CH2_TX_P(sfp2_tx_p),
        /*[o] */    .GTH_OUT_CH2_TX_N(sfp2_tx_n),

        /*[i] */    .GTH_IN_CH3_RX_P(sfp3_rx_p),
        /*[i] */    .GTH_IN_CH3_RX_N(sfp3_rx_n),
        /*[o] */    .GTH_OUT_CH3_TX_P(sfp3_tx_p),
        /*[o] */    .GTH_OUT_CH3_TX_N(sfp3_tx_n),
        
        /*[i] */    .diff_clock_rtl_0_clk_p(sys_clk_p),
        /*[i] */    .diff_clock_rtl_0_clk_n(sys_clk_n),
        
        /*[i] */    .reset_rtl_0(rst_n),
        
        /*[o] */    .axi_rst_tst(axi_rst_tst),
        /*[o] */    .locked_tst(locked_tst),
        
        /*[o] */    .uart_rtl_0_txd(uart_tx),
        /*[i] */    .uart_rtl_0_rxd(uart_rx)
        
    );
    
    assign led[0] = !axi_rst_tst;
    assign led[1] = locked_tst;

endmodule

