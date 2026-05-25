###############################################################################
# Project    : MuroSync
# File       : update_ip_ports.tcl
# Created    : 2026-05-05
# Author     : Mikhail Vasilev
#
# Description:
#   Vivado IP Packager automation script.
#
#   Responsibilities:
#     1. Auto-increment IP_VERSION_MINOR in RTL (source of truth) and sync
#        the resulting MAJOR.MINOR string to IP-XACT <spirit:version>. Also
#        bump Vivado's internal core_revision so the IP cache invalidates.
#     2. Assign Enablement Dependencies and Driver Values to MASTER/SLAVE
#        transceiver ports in component.xml based on the $MODE parameter.
#     3. Hide internal derived parameters (C_S00_AXI_NUM_REGS, OPT_MEM_ADDR_BITS,
#        ADDR_WIDTH_NEEDED, C_S00_AXI_DATA_WIDTH, IP_VERSION_MAJOR,
#        IP_VERSION_MINOR) from the Customization GUI while keeping them
#        present in component.xml so Block Design can read and update them.
#
#   NOTE on IS_SLAVE / IS_MASTER (history):
#     Earlier versions of this script also hid IS_SLAVE and IS_MASTER from
#     the GUI. ipgui::remove_param froze their values in component.xml as
#     compile-time constants (IS_SLAVE=false, IS_MASTER=true), so changing
#     CONFIG.MODE in BD no longer re-evaluated them — the IP always ran as
#     MASTER regardless of the selected MODE.
#
#     Fix: IS_SLAVE and IS_MASTER are now declared as `localparam` inside
#     the RTL body of murosync_serdes_array.sv (not as module parameters).
#     IP Packager does not see them at all, they are re-evaluated by the
#     synthesizer at elaboration based on the current MODE value.
#
#     Consequence: this script must NOT try to hide them — they are not
#     user parameters anymore.
#
#   NOTE on hiding strategy: parameters are hidden with "visible false"
#   semantics (via ipgui::remove_param + value_resolve_type=dependent).
#   The original comment claimed parameters were NOT removed; in fact
#   ipgui::remove_param IS called, but the value_resolve_type=dependent
#   prevents BD freezing for parameters that don't depend on MODE.
#
# Notes:
#   - Source this script in the Vivado Tcl Console while the "Package IP"
#     tab is active and after merging changes from the file system.
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
 
set core [ipx::current_core]
if {$core == ""} {
    puts "ERROR: IP Packager is not open! Please open the Package IP tab first."
    return -code error
}
 
puts ">>> Starting automated port configuration..."

# ----------------------------------------------------------------------------
# 0a. Sync IP version: read MAJOR/MINOR from RTL, increment MINOR, write back.
#
#     Source of truth: parameters in murosync_serdes_array.sv top IP file.
#     This script:
#       - Reads current MAJOR and MINOR from RTL
#       - Increments MINOR by 1
#       - Writes new MINOR back to the same RTL file (regsub)
#       - Applies "MAJOR.MINOR" to IP-XACT <spirit:version> on the core
#       - Bumps core_revision (Vivado-internal counter for cache invalidation)
#
#     MAJOR bump: change manually in RTL. Reset MINOR to 0 in the same edit.
#                 Next script run will increment 0 -> 1.
# ----------------------------------------------------------------------------
set rtl_top "[file dirname [info script]]/src/murosync_serdes_array.sv"

if {![file exists $rtl_top]} {
    puts "ERROR: RTL top file not found at $rtl_top"
    return -code error
}

set fp [open $rtl_top r]
set rtl_content [read $fp]
close $fp

# Parse MAJOR
if {![regexp {parameter\s+integer\s+IP_VERSION_MAJOR\s*=\s*(\d+)} $rtl_content -> cur_major]} {
    puts "ERROR: Cannot find 'parameter integer IP_VERSION_MAJOR = N' in $rtl_top"
    return -code error
}

# Parse MINOR
if {![regexp {parameter\s+integer\s+IP_VERSION_MINOR\s*=\s*(\d+)} $rtl_content -> cur_minor]} {
    puts "ERROR: Cannot find 'parameter integer IP_VERSION_MINOR = N' in $rtl_top"
    return -code error
}

set new_minor [expr {$cur_minor + 1}]
set new_version "${cur_major}.${new_minor}"

puts "  Current IP version in RTL: ${cur_major}.${cur_minor}"
puts "  Auto-incrementing MINOR:   ${cur_major}.${new_minor}"

# Write new MINOR back to RTL (specific regex to avoid accidental matches)
set rtl_new $rtl_content
regsub {(parameter\s+integer\s+IP_VERSION_MINOR\s*=\s*)\d+} $rtl_new "\\1$new_minor" rtl_new

if {$rtl_new eq $rtl_content} {
    puts "ERROR: MINOR substitution did not change RTL content"
    return -code error
}

set fp [open $rtl_top w]
puts -nonewline $fp $rtl_new
close $fp
puts "  Updated RTL: $rtl_top"

# Sync to IP-XACT
set_property version $new_version $core
set old_rev [get_property core_revision $core]
set new_rev [expr {$old_rev + 1}]
set_property core_revision $new_rev $core
puts "  Synced to IP-XACT: version=$new_version, core_revision=${old_rev}->${new_rev}"

# ----------------------------------------------------------------------------
# 0. Configure MODE parameter as a drop-down list
# ----------------------------------------------------------------------------
set mode_param [ipx::get_user_parameters MODE -of_objects $core]
if {$mode_param != ""} {
    set_property display_name "Mode" $mode_param
    set_property value_format string $mode_param
    set_property value_validation_type pairs $mode_param
    set_property value_validation_pairs {MASTER MASTER SLAVE SLAVE} $mode_param
    puts "  Configured MODE parameter as a Drop List."
}
 
# ----------------------------------------------------------------------------
# 0b. Hide internal/derived parameters from Customization GUI.
#
#     IS_SLAVE / IS_MASTER are NOT in this list — they are localparam in
#     RTL now (see header comment). IP Packager does not see them.
# ----------------------------------------------------------------------------
set params_to_hide {
    IP_VERSION_MAJOR
    IP_VERSION_MINOR
    C_S00_AXI_DATA_WIDTH
    C_S00_AXI_NUM_REGS
    OPT_MEM_ADDR_BITS
    ADDR_WIDTH_NEEDED
}
 
puts "  Hiding internal parameters from GUI..."
foreach param_name $params_to_hide {
    # 1. Catch is required because get_guiparamspec throws a fatal error if already removed
    if {[catch {
        set guiparam [ipgui::get_guiparamspec -name $param_name -component $core]
        ipgui::remove_param -component $core $guiparam
        puts "    Hidden (removed from GUI): $param_name"
    } err]} {
        puts "    Skipped (already hidden or not found): $param_name"
    }

    # 2. Prevent freezing by allowing it to evaluate dynamically
    catch {
        set param [ipx::get_user_parameters $param_name -of_objects $core]
        if {$param != ""} {
            set_property value_resolve_type dependent $param
        }
    }
}
 
# Regenerate XGUI files to ensure the GUI layout changes are committed
ipx::create_xgui_files $core
 
# ----------------------------------------------------------------------------
# 1. Dependencies for SLAVE ports (muro_gth_slave_* and slave_recclk_*)
# ----------------------------------------------------------------------------
set slave_ports [ipx::get_ports -filter {name =~ *slave*} -of_objects $core]
foreach p $slave_ports {
    set_property enablement_dependency {$MODE == "SLAVE"} $p
    if {[string tolower [get_property direction $p]] == "in"} {
        set_property driver_value 0 $p
    }
    puts "  Set: [get_property name $p] -> \$MODE == \"SLAVE\""
}
 
# ----------------------------------------------------------------------------
# 1b. muro_gth_aux_* ports — slave interface auxiliary channels
# ----------------------------------------------------------------------------
set aux_ports [ipx::get_ports -filter {name =~ *aux*} -of_objects $core]
foreach p $aux_ports {
    set_property enablement_dependency {$MODE == "SLAVE"} $p
    if {[string tolower [get_property direction $p]] == "in"} {
        set_property driver_value 0 $p
    }
    puts "  Set: [get_property name $p] -> \$MODE == \"SLAVE\""
}
 
# ----------------------------------------------------------------------------
# 2. Dependencies for MASTER ports (muro_gth_master_*)
# ----------------------------------------------------------------------------
set master_ports [ipx::get_ports -filter {name =~ *master*} -of_objects $core]
foreach p $master_ports {
    set_property enablement_dependency {$MODE == "MASTER"} $p
    if {[string tolower [get_property direction $p]] == "in"} {
        set_property driver_value 0 $p
    }
    puts "  Set: [get_property name $p] -> \$MODE == \"MASTER\""
}
 
# ----------------------------------------------------------------------------
# 3. Save the core
# ----------------------------------------------------------------------------
ipx::save_core $core
puts ">>> Success! All ports configured and parameters hidden (not removed)."
puts ">>> Please proceed to the 'Review and Package' tab and click Re-Package IP."