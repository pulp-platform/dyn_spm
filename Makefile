# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Chi Zhang <chizhang@iis.ee.ethz.ch>

BENDER ?= bender
VLOG_ARGS = -svinputport=compat -override_timescale 1ns/1ps -suppress 2583 -suppress 13314

vsim: vsim/compile.tcl
	cd vsim && questa vsim -c -do run_all.tcl

vsim/compile.tcl: Bender.yml Makefile $(shell find src -type f) $(shell find test -type f) 
	$(BENDER) script vsim -t test -t rtl --vlog-arg="$(VLOG_ARGS)" > $@

clean:
	cd vsim && rm -rf work/ vsim.wlf  transcript  modelsim.ini compile.tcl