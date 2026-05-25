# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "MODE" -parent ${Page_0} -widget comboBox


}

proc update_PARAM_VALUE.ADDR_WIDTH_NEEDED { PARAM_VALUE.ADDR_WIDTH_NEEDED } {
	# Procedure called to update ADDR_WIDTH_NEEDED when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ADDR_WIDTH_NEEDED { PARAM_VALUE.ADDR_WIDTH_NEEDED } {
	# Procedure called to validate ADDR_WIDTH_NEEDED
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to update C_S00_AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to validate C_S00_AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_NUM_REGS { PARAM_VALUE.C_S00_AXI_NUM_REGS } {
	# Procedure called to update C_S00_AXI_NUM_REGS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_NUM_REGS { PARAM_VALUE.C_S00_AXI_NUM_REGS } {
	# Procedure called to validate C_S00_AXI_NUM_REGS
	return true
}

proc update_PARAM_VALUE.MODE { PARAM_VALUE.MODE } {
	# Procedure called to update MODE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MODE { PARAM_VALUE.MODE } {
	# Procedure called to validate MODE
	return true
}

proc update_PARAM_VALUE.OPT_MEM_ADDR_BITS { PARAM_VALUE.OPT_MEM_ADDR_BITS } {
	# Procedure called to update OPT_MEM_ADDR_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.OPT_MEM_ADDR_BITS { PARAM_VALUE.OPT_MEM_ADDR_BITS } {
	# Procedure called to validate OPT_MEM_ADDR_BITS
	return true
}


proc update_MODELPARAM_VALUE.MODE { MODELPARAM_VALUE.MODE PARAM_VALUE.MODE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MODE}] ${MODELPARAM_VALUE.MODE}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_NUM_REGS { MODELPARAM_VALUE.C_S00_AXI_NUM_REGS PARAM_VALUE.C_S00_AXI_NUM_REGS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_NUM_REGS}] ${MODELPARAM_VALUE.C_S00_AXI_NUM_REGS}
}

proc update_MODELPARAM_VALUE.OPT_MEM_ADDR_BITS { MODELPARAM_VALUE.OPT_MEM_ADDR_BITS PARAM_VALUE.OPT_MEM_ADDR_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.OPT_MEM_ADDR_BITS}] ${MODELPARAM_VALUE.OPT_MEM_ADDR_BITS}
}

proc update_MODELPARAM_VALUE.ADDR_WIDTH_NEEDED { MODELPARAM_VALUE.ADDR_WIDTH_NEEDED PARAM_VALUE.ADDR_WIDTH_NEEDED } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ADDR_WIDTH_NEEDED}] ${MODELPARAM_VALUE.ADDR_WIDTH_NEEDED}
}

