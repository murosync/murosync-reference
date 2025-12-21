##################################################################################
# Company:        Murosync
# Engineer:       Mikhail Vasilev
#
# Project:        murosync_poc
# File:           murosync_poc_timing_constraints.xdc
#
# Purpose:        Timing constraints for Murosync PoC:
#                 - Primary clock definitions (create_clock)
#                 - Generated clocks (create_generated_clock)
#                 - Clock-domain relationships (set_clock_groups)
#                 - Timing exceptions (false paths, multicycle paths)
#                 - Constraint policy for timing closure
#
# Scope:
#   - This file contains timing constraints ONLY.
#   - No PACKAGE_PIN / IOSTANDARD assignments (those belong to
#     murosync_poc_phys_constraints.xdc).
#   - Timing exceptions must be justified and kept minimal.
#
# Target Hardware:
#   - FPGA:         XCAU15P-FFVB676-2-I (Artix UltraScale+, Industrial)
#   - Board:        ALINX AXAU15 + ACAU15 (rev: [Fill])
#
# Toolchain:
#   - Vivado:       2022.2
#
# Clocking (board-provided):
#   - SYS_CLK:      200 MHz differential oscillator -> fabric clock input
#   - MGT_REFCLK:   156.25 MHz differential oscillator -> GTH reference clock
#
# Intellectual Property Notice:
#   This source code and related design materials are the proprietary intellectual
#   property of Murosync.
#
#   Unauthorized copying, modification, distribution, or use of this file, in whole
#   or in part, without explicit written permission from Murosync is strictly prohibited.
#
#   This file is provided for internal development, evaluation, and demonstration
#   purposes only and must not be disclosed to third parties without prior authorization.
#
# Revision History:
#   0.01  2025-12-14  Initial file created
#
##################################################################################

# ------------------------------------------------------------------------------
# Primary clocks
# ------------------------------------------------------------------------------

# SYS_CLK: 200 MHz => 5.000 ns period
# Note: Apply create_clock to the top-level port (sys_clk_p).
#       Vivado will propagate through IBUFDS/BUFG as appropriate.
create_clock -name sys_clk -period 5.000 -waveform {0.000 2.500} [get_ports sys_clk_p]

# ------------------------------------------------------------------------------
# (Optional placeholder) Generated clocks
#   Add later when you introduce MMCM/PLL outputs, e.g.:
#   create_generated_clock -name clk_100m -source [get_clocks sys_clk] ...
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# (Optional placeholder) Clock domain relationships
#   Add later when you have multiple unrelated clocks (e.g. sys_clk vs gt_refclk)
#   Example:
#   set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks gt_refclk]
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# (Optional placeholder) Timing exceptions policy
#   Keep exceptions minimal and documented, e.g.:
#   set_false_path -from ... -to ...
#   set_multicycle_path ...
# ------------------------------------------------------------------------------