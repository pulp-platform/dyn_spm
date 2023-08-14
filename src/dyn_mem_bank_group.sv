// Copyright 2023 ETH Zurich and 
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 21.Mar.2023

// Bank Group of Dynamic Scratchpad Memory

`include "common_cells/registers.svh"
module dyn_mem_bank_group #(
    parameter int unsigned                      NUM_BANK_PER_BANK_GROUP = 2,
    parameter int unsigned                      BANK_SIZE_IN_WORD       = 2**16,
    parameter type                              bank_tcdm_data_t        = logic,
    parameter type                              bank_tcdm_addr_t        = logic,
    parameter type                              bank_tcdm_strb_t        = logic,
    parameter type                              bkgp_tcdm_data_t        = logic,
    parameter type                              bkgp_tcdm_addr_t        = logic,
    parameter type                              bkgp_tcdm_strb_t        = logic
    )(
    /// Clock, positive edge triggered.
    input  logic                                clk_i,
    /// Reset, active low.
    input  logic                                rst_ni,
    /// Upstream bank group tcdm interface
    input  bkgp_tcdm_data_t                     bkgp_tcdm_wdata_i,
    input  bkgp_tcdm_addr_t                     bkgp_tcdm_addr_i,
    input  logic                                bkgp_tcdm_we_i,
    input  bkgp_tcdm_strb_t                     bkgp_tcdm_strb_i,
    input  logic                                bkgp_tcdm_req_i,
    output bkgp_tcdm_data_t                     bkgp_tcdm_rdata_o,
    output logic                                bkgp_tcdm_gnt_o,
    output logic                                bkgp_tcdm_rvalid_o,
    /// ECC signals
    output logic [NUM_BANK_PER_BANK_GROUP-1:0]  ecc_bank_faults_o,
    output logic [NUM_BANK_PER_BANK_GROUP-1:0]  ecc_scrubber_fixes_o,
    output logic [NUM_BANK_PER_BANK_GROUP-1:0]  ecc_scrub_uncorrectables_o,
    input  logic [NUM_BANK_PER_BANK_GROUP-1:0]  ecc_scrub_triggers_i,
    output logic                                ecc_error_o
);

    bank_tcdm_data_t                            [NUM_BANK_PER_BANK_GROUP-1:0] bank_tcdm_wdata;
    bank_tcdm_addr_t                            [NUM_BANK_PER_BANK_GROUP-1:0] bank_tcdm_addr;
    logic                                       [NUM_BANK_PER_BANK_GROUP-1:0] bank_tcdm_we;
    bank_tcdm_strb_t                            [NUM_BANK_PER_BANK_GROUP-1:0] bank_tcdm_strb;
    logic                                       [NUM_BANK_PER_BANK_GROUP-1:0] bank_tcdm_req;
    bank_tcdm_data_t                            [NUM_BANK_PER_BANK_GROUP-1:0] bank_tcdm_rdata;
    logic                                       [NUM_BANK_PER_BANK_GROUP-1:0] bank_tcdm_gnt;
    logic                                       [NUM_BANK_PER_BANK_GROUP-1:0] bank_error;

    for (genvar i = 0; i < NUM_BANK_PER_BANK_GROUP; i++) begin
        

        ecc_sram_wrap #(
            .BankSize        (BANK_SIZE_IN_WORD),
            .InputECC        (0),
            .EnableTestMask  (0)
        ) i_ecc_sram_wrap (
            .clk_i,
            .rst_ni,
            .test_enable_i        ('0),
            .scrub_trigger_i      (ecc_scrub_triggers_i[i]),
            .scrubber_fix_o       (ecc_scrubber_fixes_o[i]),
            .scrub_uncorrectable_o(ecc_scrub_uncorrectables_o[i]),
            .tcdm_wdata_i         (bank_tcdm_wdata[i]   ),
            .tcdm_add_i           (bank_tcdm_addr[i]    ),
            .tcdm_req_i           (bank_tcdm_req[i]     ),
            .tcdm_wen_i           (~bank_tcdm_we[i]      ),
            .tcdm_be_i            (bank_tcdm_strb[i]    ),
            .tcdm_rdata_o         (bank_tcdm_rdata[i]   ),
            .tcdm_gnt_o           (bank_tcdm_gnt[i]     ),
            .single_error_o       (ecc_bank_faults_o[i]),
            .multi_error_o        (bank_error[i]),
            .test_write_mask_ni   ('0)
        );

    end

    ////////////////////
    //  Control path  //
    ////////////////////

    /*
        we send the requests to banks when:
            1. there is a valid request to this bank group
            2. two banks are all ready to accept new requests 
    */
    logic handshack;
    assign handshack =  bkgp_tcdm_req_i & (&bank_tcdm_gnt);

    for (genvar i = 0; i < NUM_BANK_PER_BANK_GROUP; i++) begin
        assign bank_tcdm_req[i] = handshack;
    end

    assign bkgp_tcdm_gnt_o = handshack;

    /*
        the response valid is one cycle shift of the handshake signal
    */
    `FF(bkgp_tcdm_rvalid_o, handshack, 1'b0);

    /*
        we report bank group error when either of banks raises ecc error
    */
    assign ecc_error_o = |bank_error;

    /////////////////
    //  Data path  //
    /////////////////

    //width change signals
    assign bank_tcdm_wdata = bkgp_tcdm_wdata_i;
    assign bkgp_tcdm_rdata_o = bank_tcdm_rdata;
    assign bank_tcdm_strb = bkgp_tcdm_strb_i;

    //duplicate signals
    for (genvar i = 0; i < NUM_BANK_PER_BANK_GROUP; i++) begin
        assign bank_tcdm_addr[i] = bkgp_tcdm_addr_i << 2;
        assign bank_tcdm_we[i] = bkgp_tcdm_we_i;
    end

endmodule : dyn_mem_bank_group