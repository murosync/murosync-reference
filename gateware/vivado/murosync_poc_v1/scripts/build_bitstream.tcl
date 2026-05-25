###############################################################################
# Project    : MuroSync
# File       : build_bitstream.tcl
# Created    : 2026-05-24
# Author     : Mikhail Vasilev
#
# Description:
#   Vivado bitstream build automation for the murosync_poc_v1 project.
#
#   Switches the murosync_serdes_array IP between MASTER and SLAVE mode
#   via the CONFIG.MODE parameter, reconnects external SFP-cage ports to
#   the correct IP pins (because the IP exposes different port sets per
#   mode through enablement_dependency in IP packaging), runs synthesis
#   and implementation, and exports the resulting .bit + .xsa files to
#   the bitstreams directory.
#
#   Channel mapping (no cross-swap):
#       CH0 -> master_0  / slave
#       CH1 -> master_1  / aux_0
#       CH2 -> master_2  / aux_1
#       CH3 -> master_3  / aux_2
#
# Usage:
#   vivado -mode batch -source build_bitstream.tcl -tclargs MASTER
#   vivado -mode batch -source build_bitstream.tcl -tclargs SLAVE
#
# Output:
#   C:/_vivado/murosync_poc_v1/bitstreams/murosync_<MODE>.bit
#   C:/_vivado/murosync_poc_v1/bitstreams/murosync_<MODE>.xsa
#
# Notes:
#   - Must be run with Vivado closed (script opens the project itself).
#   - When MODE changes, Vivado disables the old port set and removes the
#     associated nets; this script reconnects external BD ports to the new
#     pin names of the now-enabled port set.
#
# Copyright (c) 2026 Mikhail Vasilev / MuroSync
#
# License:
# This file is currently released under a restricted research license.
# Licensing terms may change in future revisions of the project.
#
# Commercial use, redistribution, or integration into commercial products
# requires an explicit license agreement.
#
# For licensing inquiries, please contact:
#     info@murosync.com
#
###############################################################################

# ============================================================================
# Configuration
# ============================================================================
set PROJECT_FILE   "C:/_vivado/murosync_poc_v1/murosync_poc_v1.xpr"
set BD_NAME        "bd_murosync_poc"
set IP_CELL_NAME   "murosync_serdes_array_0"
set OUTPUT_DIR     "C:/_vivado/murosync_poc_v1/bitstreams"
set OUTPUT_PREFIX  "murosync"

# ============================================================================
# Parse arguments
# ============================================================================
if {[llength $argv] != 1} {
    puts "ERROR: Expected 1 argument (MASTER or SLAVE), got [llength $argv]"
    puts "Usage: vivado -mode batch -source build_bitstream.tcl -tclargs <MODE>"
    exit 1
}

set MODE [string toupper [lindex $argv 0]]

if {$MODE ne "MASTER" && $MODE ne "SLAVE"} {
    puts "ERROR: Invalid MODE '$MODE'. Must be MASTER or SLAVE."
    exit 1
}

puts "============================================================"
puts "  MuroSync bitstream build"
puts "  MODE = $MODE"
puts "  [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts "============================================================"

# ============================================================================
# Helper: reconnect external BD ports to IP pins for given MODE
# ============================================================================
# This is needed because the IP exposes DIFFERENT port names when MODE changes
# (via enablement_dependency in IP packaging). After set_property CONFIG.MODE,
# Vivado disables old ports and silently deletes their nets. We then connect
# the still-existing external BD ports (GTH_IN_CHx_RX_*, GTH_OUT_CHx_TX_*) to
# the new pin names of the now-enabled port set.

proc reconnect_external_ports {mode ip_cell} {
    puts ""
    puts "Reconnecting external BD ports for MODE=$mode..."

    # Channel-to-pin mapping for both modes.
    # Format: { CH_NUM RX_PIN_BASE TX_PIN_BASE }
    if {$mode eq "MASTER"} {
        set channel_map {
            {0 muro_gth_master_0 muro_gth_master_0}
            {1 muro_gth_master_1 muro_gth_master_1}
            {2 muro_gth_master_2 muro_gth_master_2}
            {3 muro_gth_master_3 muro_gth_master_3}
        }
    } else {
        # SLAVE mode: CH0 is the sync link, CH1-3 are aux channels
        set channel_map {
            {0 muro_gth_slave   muro_gth_slave}
            {1 muro_gth_aux_0   muro_gth_aux_0}
            {2 muro_gth_aux_1   muro_gth_aux_1}
            {3 muro_gth_aux_2   muro_gth_aux_2}
        }
    }

    # Helper: ensure a port is connected to a target pin.
    # If the port already has a net, check whether it goes to the right pin.
    # If yes, skip. If no, disconnect and reconnect.
    # If port has no net, just connect.
    proc ensure_connection {port_obj pin_obj} {
        set existing_nets [get_bd_nets -quiet -of_objects $port_obj]

        if {[llength $existing_nets] > 0} {
            set existing_net [lindex $existing_nets 0]
            set net_pins [get_bd_pins -quiet -of_objects $existing_net]

            # Check if our target pin is already on this net
            set already_connected 0
            foreach p $net_pins {
                if {[get_property NAME $p] eq [get_property NAME $pin_obj]} {
                    if {[get_property PATH $p] eq [get_property PATH $pin_obj]} {
                        set already_connected 1
                        break
                    }
                }
            }

            if {$already_connected} {
                return "skip (already connected)"
            }

            # Different connection — remove old net, create new
            delete_bd_objs $existing_net
        }

        connect_bd_net $port_obj $pin_obj
        return "connected"
    }

    foreach entry $channel_map {
        set ch       [lindex $entry 0]
        set rx_base  [lindex $entry 1]
        set tx_base  [lindex $entry 2]

        set rx_n_status [ensure_connection [get_bd_ports GTH_IN_CH${ch}_RX_N]  [get_bd_pins ${ip_cell}/${rx_base}_rxn_in]]
        set rx_p_status [ensure_connection [get_bd_ports GTH_IN_CH${ch}_RX_P]  [get_bd_pins ${ip_cell}/${rx_base}_rxp_in]]
        set tx_n_status [ensure_connection [get_bd_ports GTH_OUT_CH${ch}_TX_N] [get_bd_pins ${ip_cell}/${tx_base}_txn_out]]
        set tx_p_status [ensure_connection [get_bd_ports GTH_OUT_CH${ch}_TX_P] [get_bd_pins ${ip_cell}/${tx_base}_txp_out]]

        puts "  CH${ch}: RX_N=$rx_n_status, RX_P=$rx_p_status, TX_N=$tx_n_status, TX_P=$tx_p_status"
    }

    puts "All 16 connections verified for MODE=$mode."
}

# ============================================================================
# Step 1: Open project
# ============================================================================
puts ""
puts ">>> Step 1: Opening project..."
open_project $PROJECT_FILE

# ============================================================================
# Step 2: Open BD and switch MODE
# ============================================================================
puts ""
puts ">>> Step 2: Opening Block Design and switching MODE to $MODE..."

# Find the BD file path from project
set bd_file [get_files "${BD_NAME}.bd"]
if {$bd_file eq ""} {
    puts "ERROR: Block Design '${BD_NAME}.bd' not found in project."
    exit 1
}

open_bd_design $bd_file

# Switch MODE — this triggers automatic disable of old ports
# and deletion of their nets (Vivado emits BD 41-1684 warnings, expected).
set_property CONFIG.MODE $MODE [get_bd_cells $IP_CELL_NAME]

# ============================================================================
# Step 3: Reconnect external ports to new pin names
# ============================================================================
puts ""
puts ">>> Step 3: Reconnecting external ports for new MODE..."
reconnect_external_ports $MODE $IP_CELL_NAME

# ============================================================================
# Step 4: Validate and save BD
# ============================================================================
puts ""
puts ">>> Step 4: Validating and saving Block Design..."
validate_bd_design
save_bd_design

# ============================================================================
# Step 5: Regenerate BD output products (wrapper, hwdef, etc.)
# ============================================================================
puts ""
puts ">>> Step 5: Regenerating BD output products..."
generate_target all $bd_file

# ============================================================================
# Step 6: Reset and re-run synthesis
# ============================================================================
puts ""
puts ">>> Step 6: Resetting and launching synthesis..."
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "ERROR: Synthesis did not complete successfully."
    exit 1
}

# ============================================================================
# Step 7: Implementation + write bitstream
# ============================================================================
puts ""
puts ">>> Step 7: Launching implementation + bitstream generation..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "ERROR: Implementation did not complete successfully."
    exit 1
}

# ============================================================================
# Step 8: Copy bitstream to output directory
# ============================================================================
puts ""
puts ">>> Step 8: Copying bitstream and generating XSA..."

# Ensure output directory exists
file mkdir $OUTPUT_DIR

# Locate the bitstream — top module name from project
set top_module [get_property top [current_fileset]]
set impl_dir   [get_property DIRECTORY [get_runs impl_1]]
set src_bit    "${impl_dir}/${top_module}.bit"
set dst_bit    "${OUTPUT_DIR}/${OUTPUT_PREFIX}_${MODE}.bit"

if {![file exists $src_bit]} {
    puts "ERROR: Bitstream not found at $src_bit"
    exit 1
}

file copy -force $src_bit $dst_bit
puts "  Copied: $dst_bit"

# ============================================================================
# Step 9: Generate XSA (hardware platform for Vitis)
# ============================================================================
set dst_xsa "${OUTPUT_DIR}/${OUTPUT_PREFIX}_${MODE}.xsa"

# write_hw_platform — exports Vitis-compatible hardware platform
# -fixed         : static (non-extensible) platform — simpler, for embedded
# -include_bit   : embed the bitstream in the XSA
# -force         : overwrite existing file
write_hw_platform -fixed -include_bit -force $dst_xsa
puts "  Generated: $dst_xsa"

# ============================================================================
# Step 10: Close project
# ============================================================================
puts ""
puts ">>> Step 10: Closing project..."
close_project

puts ""
puts "============================================================"
puts "  BUILD COMPLETE for MODE=$MODE"
puts "  Bitstream: $dst_bit"
puts "  XSA:       $dst_xsa"
puts "  [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts "============================================================"
