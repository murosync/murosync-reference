# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "P_FREERUN_FREQUENCY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "P_RX_TIMER_DURATION_US" -parent ${Page_0}
  ipgui::add_param $IPINST -name "P_TX_TIMER_DURATION_US" -parent ${Page_0}


}

proc update_PARAM_VALUE.P_FREERUN_FREQUENCY { PARAM_VALUE.P_FREERUN_FREQUENCY } {
	# Procedure called to update P_FREERUN_FREQUENCY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.P_FREERUN_FREQUENCY { PARAM_VALUE.P_FREERUN_FREQUENCY } {
	# Procedure called to validate P_FREERUN_FREQUENCY
	return true
}

proc update_PARAM_VALUE.P_RX_TIMER_DURATION_US { PARAM_VALUE.P_RX_TIMER_DURATION_US } {
	# Procedure called to update P_RX_TIMER_DURATION_US when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.P_RX_TIMER_DURATION_US { PARAM_VALUE.P_RX_TIMER_DURATION_US } {
	# Procedure called to validate P_RX_TIMER_DURATION_US
	return true
}

proc update_PARAM_VALUE.P_TX_TIMER_DURATION_US { PARAM_VALUE.P_TX_TIMER_DURATION_US } {
	# Procedure called to update P_TX_TIMER_DURATION_US when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.P_TX_TIMER_DURATION_US { PARAM_VALUE.P_TX_TIMER_DURATION_US } {
	# Procedure called to validate P_TX_TIMER_DURATION_US
	return true
}


proc update_MODELPARAM_VALUE.P_FREERUN_FREQUENCY { MODELPARAM_VALUE.P_FREERUN_FREQUENCY PARAM_VALUE.P_FREERUN_FREQUENCY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.P_FREERUN_FREQUENCY}] ${MODELPARAM_VALUE.P_FREERUN_FREQUENCY}
}

proc update_MODELPARAM_VALUE.P_TX_TIMER_DURATION_US { MODELPARAM_VALUE.P_TX_TIMER_DURATION_US PARAM_VALUE.P_TX_TIMER_DURATION_US } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.P_TX_TIMER_DURATION_US}] ${MODELPARAM_VALUE.P_TX_TIMER_DURATION_US}
}

proc update_MODELPARAM_VALUE.P_RX_TIMER_DURATION_US { MODELPARAM_VALUE.P_RX_TIMER_DURATION_US PARAM_VALUE.P_RX_TIMER_DURATION_US } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.P_RX_TIMER_DURATION_US}] ${MODELPARAM_VALUE.P_RX_TIMER_DURATION_US}
}

