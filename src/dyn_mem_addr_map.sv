// Copyright 2023 ETH Zurich and 
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 21.Mar.2023

module dyn_mem_addr_map #(
    parameter int unsigned           NUM_MAP_RULES                  = 4,
    parameter int unsigned           NUM_BANK_GROUP                 = 2,
    parameter int unsigned           BANK_GROUP_DATA_WIDTH          = 64,
    parameter int unsigned           BANK_LEVEL_EFFECT_ADDR_WIDTH   = 64,
    parameter type                   map_rule_t                     = logic,
    parameter type                   tcdm_data_t                    = logic,
    parameter type                   tcdm_addr_t                    = logic,
    parameter type                   tcdm_strb_t                    = logic,
    parameter type                   bkgp_tcdm_data_t               = logic,
    parameter type                   bkgp_tcdm_addr_t               = logic,
    parameter type                   bkgp_tcdm_strb_t               = logic
    )(
    /// Clock, positive edge triggered.
    input  logic                                        clk_i,
    /// Reset, active low.
    input  logic                                        rst_ni,
    /// mapping rules
    input map_rule_t [NUM_MAP_RULES-1:0]                mapping_rules_i,
    /// Upstream tcdm interface
    input  tcdm_data_t                                  tcdm_wdata_i,
    input  tcdm_addr_t                                  tcdm_addr_i,
    input  logic                                        tcdm_we_i,
    input  tcdm_strb_t                                  tcdm_strb_i,
    input  logic                                        tcdm_req_i,
    output tcdm_data_t                                  tcdm_rdata_o,
    output logic                                        tcdm_ecc_err_o,
    output logic                                        tcdm_gnt_o,
    output logic                                        tcdm_rvalid_o,
    /// Downstream bank group tcdm interface
    output bkgp_tcdm_data_t                             bkgp_tcdm_wdata_o,
    output bkgp_tcdm_addr_t                             bkgp_tcdm_addr_o,
    output logic                                        bkgp_tcdm_we_o,
    output bkgp_tcdm_strb_t                             bkgp_tcdm_strb_o,
    output logic                                        bkgp_tcdm_req_o,
    input  bkgp_tcdm_data_t                             bkgp_tcdm_rdata_i,
    input  logic                                        bkgp_tcdm_ecc_err_i,
    input  logic                                        bkgp_tcdm_gnt_i,
    input  logic                                        bkgp_tcdm_rvalid_i
);

    ///////////////////////
    //  address decoder  //
    ///////////////////////

    dyn_mem_pkg::map_type_idx_t idx;

    logic dec_valid, dec_error;

    addr_decode #(
        .NoIndices(dyn_mem_pkg::NUM_MAP_TYPES), 
        .NoRules(NUM_MAP_RULES), 
        .addr_t(tcdm_addr_t), 
        .rule_t(map_rule_t)
    ) i_addr_decode (
        .addr_i          (tcdm_addr_i),
        .addr_map_i      (mapping_rules_i),
        .idx_o           (idx),
        .dec_valid_o     (dec_valid),
        .dec_error_o     (dec_error),
        .en_default_idx_i('0),
        .default_idx_i   ('0)
    );

    /////////////////////////
    //  address remapping  //
    /////////////////////////
    localparam int unsigned ByteOffset = $clog2(BANK_GROUP_DATA_WIDTH/8);
    // Width of the bank select signal.
    localparam int unsigned SelWidth = cf_math_pkg::idx_width(NUM_BANK_GROUP);

    logic [ByteOffset-1:0]  byte_region;
    logic [SelWidth-1:0]    bkgp_sel_region;
    logic [BANK_LEVEL_EFFECT_ADDR_WIDTH-1:0] bkgp_addr_region;

    assign {bkgp_sel_region, bkgp_addr_region, byte_region} = tcdm_addr_i;

    always_comb begin
        bkgp_tcdm_addr_o = tcdm_addr_i[BANK_LEVEL_EFFECT_ADDR_WIDTH + ByteOffset + SelWidth -1:0];
        if (idx == dyn_mem_pkg::NONE_INTER) begin
            bkgp_tcdm_addr_o = {bkgp_addr_region, bkgp_sel_region, byte_region};
        end
    end

    ////////////////////
    //  Control Path  //
    ////////////////////

    assign bkgp_tcdm_req_o = dec_valid & ~dec_error & tcdm_req_i;

    assign tcdm_gnt_o = bkgp_tcdm_gnt_i & bkgp_tcdm_req_o;

    //////////////
    //  Bypass  //
    //////////////

    assign bkgp_tcdm_wdata_o = tcdm_wdata_i;
    assign bkgp_tcdm_we_o = tcdm_we_i;
    assign bkgp_tcdm_strb_o = tcdm_strb_i;
    assign tcdm_rdata_o = bkgp_tcdm_rdata_i;
    assign tcdm_ecc_err_o = bkgp_tcdm_ecc_err_i;
    assign tcdm_rvalid_o = bkgp_tcdm_rvalid_i;

    //////////////////
    //  Assertions  //
    //////////////////
    `ifndef VERILATOR
        assert property (@(posedge clk_i) (tcdm_req_i |-> ~dec_error)) 
            else $fatal(1,"the request address %0h is not within the address spaces, PLEASE check your master or mapping rules",tcdm_addr_i);
    `endif
endmodule : dyn_mem_addr_map
