##################################################################################
# Company:        Murosync
# Engineer:       Mikhail Vasilev
#
# Project:        murosync_poc
# File:           murosync_poc_phys_constraints.xdc
# Purpose:        Board-level physical constraints for Murosync PoC:
#                 - Package pin assignments (PACKAGE_PIN)
#                 - I/O standards (IOSTANDARD)
#                 - Clock definitions (create_clock / set_clock_groups)
#                 - GT reference clock pinning (MGTREFCLK)
#                 - Resets, LEDs, buttons, UART, Ethernet PHY, etc.
#
# Scope:
#   - This file contains ONLY physical / board-specific constraints.
#   - No timing exceptions unless strictly required for board bring-up.
#   - Functional timing constraints for IP blocks should live elsewhere.
#
# Target Hardware:
#   - FPGA:         XCAU15P-FFVB676-2-I (Artix UltraScale+, Industrial)
#   - Board:        ALINX AXAU15 + ACAU15 (rev: [Fill])
#
# Toolchain:
#   - Vivado:       2022.2
#
# Clocking (board-provided):
#   - SYS_CLK:      200 MHz LVDS (SiTime)  -> Fabric clock input
#   - MGT_REFCLK:   156.25 MHz LVDS        -> GTH reference clock
#
# Intellectual Property Notice:
#   This source code and related design materials are the
#   proprietary intellectual property of Murosync.
#
#   Unauthorized copying, modification, distribution, or use
#   of this file, in whole or in part, without explicit written
#   permission from Murosync is strictly prohibited.
#
#   This code is provided for internal development, evaluation,
#   and demonstration purposes only and must not be disclosed
#   to third parties without prior authorization.
#
# Revision History:
#   0.01  2025-12-14  Initial file created
#
##################################################################################

# SYS_CLK 200 MHz differential
set_property PACKAGE_PIN T7 [get_ports gth_ref_p]
set_property PACKAGE_PIN T6 [get_ports gth_ref_n]

set_property PACKAGE_PIN T24 [get_ports sys_clk_p]
set_property PACKAGE_PIN U24 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {sys_clk_p sys_clk_n}]

# Reset button KEY1 (active low)
set_property PACKAGE_PIN N26 [get_ports rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports rst_n]
set_property PULLUP true [get_ports rst_n]

# LEDs
set_property PACKAGE_PIN W21  [get_ports {led[0]}]
set_property PACKAGE_PIN AC16 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[0] led[1]}]
set_property SLEW FAST [get_ports {led[0] led[1]}]
set_property DRIVE 8   [get_ports {led[0] led[1]}]

# UART
set_property PACKAGE_PIN A12     [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property PACKAGE_PIN A13     [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# GTH pins
set_property PACKAGE_PIN Y2  [get_ports sfp0_rx_p]
set_property PACKAGE_PIN Y1  [get_ports sfp0_rx_n]
set_property PACKAGE_PIN AA5 [get_ports sfp0_tx_p]
set_property PACKAGE_PIN AA4 [get_ports sfp0_tx_n]

set_property PACKAGE_PIN V2  [get_ports sfp1_rx_p]
set_property PACKAGE_PIN V1  [get_ports sfp1_rx_n]
set_property PACKAGE_PIN W5  [get_ports sfp1_tx_p]
set_property PACKAGE_PIN W4  [get_ports sfp1_tx_n]

set_property PACKAGE_PIN T2  [get_ports sfp2_rx_p]
set_property PACKAGE_PIN T1  [get_ports sfp2_rx_n]
set_property PACKAGE_PIN U5  [get_ports sfp2_tx_p]
set_property PACKAGE_PIN U4  [get_ports sfp2_tx_n]

set_property PACKAGE_PIN P2  [get_ports sfp3_rx_p]
set_property PACKAGE_PIN P1  [get_ports sfp3_rx_n]
set_property PACKAGE_PIN R5  [get_ports sfp3_tx_p]
set_property PACKAGE_PIN R4  [get_ports sfp3_tx_n]
