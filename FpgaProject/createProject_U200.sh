#!/bin/bash
export LC_NUMERIC=en_US.utf8

export XILINXD_LICENSE_FILE=2100@0.0.0.0 #TODO add your license server IP here
export VIVADO_PATH="/tools/Xilinx/Vivado/2020.1" #TODO

source $VIVADO_PATH/settings64.sh
$VIVADO_PATH/bin/vivado -nolog -nojournal -source tcl/U200.tcl
