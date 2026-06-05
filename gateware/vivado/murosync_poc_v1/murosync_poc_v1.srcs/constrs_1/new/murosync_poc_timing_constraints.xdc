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
# create_clock -period 5.000 -waveform {0.000 2.500} [get_ports sys_clk_p]

# MGT_REFCLK: 156.25 MHz => 6.400 ns period
# create_clock -name gth_refclk -period 6.400 -waveform {0.000 3.200} [get_ports GTH_REF_P]

# Primary clocks (sys_clk_p, clk_mgtrefclk0_x0y1_p, clk_freerun) are created by
# BD interface parameters and IP-XACT XDC (GT Wizard). Do NOT redefine them here
# - duplicate create_clock causes TIMING-4 "Invalid primary clock redefinition".

# Mark physically asynchronous clock domains.
set_clock_groups -name async_sys_vs_mgtref -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk_p] \
    -group [get_clocks -include_generated_clocks clk_mgtrefclk0_x0y1_p]

set_clock_groups -name async_freerun_vs_mgtref -asynchronous \
    -group [get_clocks -include_generated_clocks clk_freerun] \
    -group [get_clocks -include_generated_clocks clk_mgtrefclk0_x0y1_p]