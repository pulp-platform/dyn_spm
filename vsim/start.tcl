# Copyright 2022 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Chi Zhang <chizhang@iis.ee.ethz.ch>

# if {![info exists TESTBENCH]} {
    set TESTBENCH dyn_mem_tb
    echo "Defaulting on TESTBENCH=${TESTBENCH}"
# }

vsim ${TESTBENCH} -t 1ps -voptargs=+acc

set StdArithNoWarnings 1
set NumericStdNoWarnings 1
log -r /*
