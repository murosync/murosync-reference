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

# 0. Configure MODE parameter as a drop-down list
set mode_param [ipx::get_user_parameters MODE -of_objects $core]
if {$mode_param != ""} {
    set_property display_name "Mode" $mode_param
    set_property value_format string $mode_param
    set_property value_validation_type pairs $mode_param
    set_property value_validation_pairs {MASTER MASTER SLAVE SLAVE} $mode_param
    puts "  Configured MODE parameter as a Drop List."
}

# 0b. Hide all parameters except MODE from the Customization GUI
puts "  Hiding internal parameters from GUI..."
foreach param [ipx::get_user_parameters -of_objects $core] {
    set param_name [get_property name $param]
    if {$param_name != "MODE"} {
        catch {
            set guiparam [ipgui::get_guiparamspec -name $param_name -component $core]
            ipgui::remove_param -component $core $guiparam
            puts "    Hidden: $param_name"
        }
    }
}

# 1. Dependencies for SLAVE ports (muro_gth_slave_* and slave_recclk_*)
set slave_ports [ipx::get_ports -filter {name =~ *slave*} -of_objects $core]
foreach p $slave_ports {
    set_property enablement_dependency {$MODE == "SLAVE"} $p
    if {[string tolower [get_property direction $p]] == "in"} {
        set_property driver_value 0 $p
    }
    puts "  Set: [get_property name $p] -> \$MODE == \"SLAVE\""
}

# 1b. If muro_gth_aux_* are also related to the slave interface:
set aux_ports [ipx::get_ports -filter {name =~ *aux*} -of_objects $core]
foreach p $aux_ports {
    set_property enablement_dependency {$MODE == "SLAVE"} $p
    if {[string tolower [get_property direction $p]] == "in"} {
        set_property driver_value 0 $p
    }
    puts "  Set: [get_property name $p] -> \$MODE == \"SLAVE\""
}

# 2. Dependencies for MASTER ports (muro_gth_master_*)
set master_ports [ipx::get_ports -filter {name =~ *master*} -of_objects $core]
foreach p $master_ports {
    set_property enablement_dependency {$MODE == "MASTER"} $p
    if {[string tolower [get_property direction $p]] == "in"} {
        set_property driver_value 0 $p
    }
    puts "  Set: [get_property name $p] -> \$MODE == \"MASTER\""
}

# 3. Save the core
ipx::save_core $core
puts ">>> Success! All ports configured. Please proceed to the 'Review and Package' tab and click Re-Package IP."
