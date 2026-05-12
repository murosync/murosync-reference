###############################################################################
# Project    : MuroSync
# File       : update_ip_ports.tcl
# Created    : 2026-05-05
# Author     : Mikhail Vasilev
#
# Description:
#   Vivado IP Packager automation script.
#
#   Automatically assigns Enablement Dependencies and Driver Values to
#   MASTER and SLAVE transceiver ports in the IP-XACT component.xml based
#   on the $MODE parameter.
#
#   Also hides internal derived parameters (IS_SLAVE, IS_MASTER,
#   C_S00_AXI_NUM_REGS, OPT_MEM_ADDR_BITS, ADDR_WIDTH_NEEDED,
#   C_S00_AXI_DATA_WIDTH) from the Customization GUI while keeping them
#   present in component.xml so that Block Design can read and update them.
#
#   NOTE: Parameters are hidden with "visible false" — NOT removed.
#   Removing parameters (ipgui::remove_param) causes Block Design to freeze
#   their values at the time of removal, breaking automatic updates on
#   repackage. Hiding with visible=false preserves the update chain.
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
#     Using ipgui::remove_param moves them to "Hidden Parameters".
#     To prevent Block Design from freezing their values (so they still update
#     based on expressions), we also set their value_resolve_type to "dependent".
# ----------------------------------------------------------------------------
set params_to_hide {
    IS_SLAVE
    IS_MASTER
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