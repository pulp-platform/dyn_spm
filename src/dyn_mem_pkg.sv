// Copyright 2023 ETH Zurich and 
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 21.Mar.2023

// Package of Dynamic Scratchpad Memory

package dyn_mem_pkg;

    ///////////////////////
    //  Address Mapping  //
    ///////////////////////

    localparam int unsigned                     NUM_MAP_TYPES               = 2;

    typedef logic [$clog2(NUM_MAP_TYPES)-1:0]   map_type_idx_t;

    typedef enum int unsigned {
        INTERLEAVE = 0,
        NONE_INTER = 1
    } map_type_e;    

    
endpackage : dyn_mem_pkg