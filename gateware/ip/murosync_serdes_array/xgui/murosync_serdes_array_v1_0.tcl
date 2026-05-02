# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "MODE" -parent ${Page_0} -widget comboBox


}

proc update_PARAM_VALUE.MODE { PARAM_VALUE.MODE } {
	# Procedure called to update MODE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MODE { PARAM_VALUE.MODE } {
	# Procedure called to validate MODE
	return true
}


proc update_MODELPARAM_VALUE.MODE { MODELPARAM_VALUE.MODE PARAM_VALUE.MODE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MODE}] ${MODELPARAM_VALUE.MODE}
}

proc update_MODELPARAM_VALUE.IS_SLAVE { MODELPARAM_VALUE.IS_SLAVE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "IS_SLAVE". Setting updated value from the model parameter.
set_property value false ${MODELPARAM_VALUE.IS_SLAVE}
}

proc update_MODELPARAM_VALUE.IS_MASTER { MODELPARAM_VALUE.IS_MASTER } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "IS_MASTER". Setting updated value from the model parameter.
set_property value true ${MODELPARAM_VALUE.IS_MASTER}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "C_S00_AXI_DATA_WIDTH". Setting updated value from the model parameter.
set_property value 32 ${MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_NUM_REGS { MODELPARAM_VALUE.C_S00_AXI_NUM_REGS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "C_S00_AXI_NUM_REGS". Setting updated value from the model parameter.
set_property value 12 ${MODELPARAM_VALUE.C_S00_AXI_NUM_REGS}
}

proc update_MODELPARAM_VALUE.OPT_MEM_ADDR_BITS { MODELPARAM_VALUE.OPT_MEM_ADDR_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "OPT_MEM_ADDR_BITS". Setting updated value from the model parameter.
set_property value 4 ${MODELPARAM_VALUE.OPT_MEM_ADDR_BITS}
}

proc update_MODELPARAM_VALUE.ADDR_WIDTH_NEEDED { MODELPARAM_VALUE.ADDR_WIDTH_NEEDED } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "ADDR_WIDTH_NEEDED". Setting updated value from the model parameter.
set_property value 7 ${MODELPARAM_VALUE.ADDR_WIDTH_NEEDED}
}

