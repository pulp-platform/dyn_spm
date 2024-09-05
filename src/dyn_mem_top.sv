// Copyright 2023 ETH Zurich and
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 22.Mar.2023

//Top level for Dynamic Scratchpad Memory

`include "axi/assign.svh"

module dyn_mem_top #(
    /// AXI Ports settings
    parameter int unsigned                  NUM_PORT                    = 2,
    parameter int unsigned                  AXI_ADDR_WIDTH              = 48,
    parameter int unsigned                  AXI_DATA_WIDTH              = 64,
    parameter int unsigned                  AXI_ID_WIDTH                = 5,
    parameter int unsigned                  AXI_USER_WIDTH              = 1,
    parameter type                          axi_req_t                   = logic,
    parameter type                          axi_resp_t                  = logic,
    /// Reg Bus for ECC Manager
    parameter bit                           AXI_USER_ECC_ERR            = 1'b1,
    parameter int unsigned                  AXI_USER_ECC_ERR_BIT        = 0,
    parameter type                          l2_ecc_reg_req_t            = logic,
    parameter type                          l2_ecc_reg_rsp_t            = logic,
    /// RISCV Atomic setting
    parameter int unsigned                  ATM_MAX_READ_TXN            = 8,
    parameter int unsigned                  ATM_MAX_WRIT_TXN            = 8,
    parameter int unsigned                  ATM_USER_AS_ID              = 1,
    parameter int unsigned                  ATM_USER_ID_MSB             = 1,
    parameter int unsigned                  ATM_USER_ID_LSB             = 0,
    parameter int unsigned                  ATM_RISCV_WORD              = 64,
    parameter int unsigned                  ATM_NUM_CUTS                = 1,
    parameter int unsigned                  CUT_OUT_POP_INP_GNT         = 1,
    /// Mapping rules
    parameter int unsigned                  NUM_MAP_RULES               = dyn_mem_pkg::NUM_MAP_TYPES * NUM_PORT,
    parameter type                          map_rule_t                  = struct packed {int unsigned idx; logic [AXI_ADDR_WIDTH-1:0] start_addr; logic [AXI_ADDR_WIDTH-1:0] end_addr;},
    /// L2 Memory settings
    parameter int unsigned                  L2_MEM_SIZE_IN_BYTE         = 2**20,
    parameter int unsigned                  NUM_BANK_GROUP              = 2,
    /// Non-changable parameters
    localparam int unsigned                 AXI_STRB_WIDTH              = AXI_DATA_WIDTH / 8,
    localparam int unsigned                 BANK_DATA_WIDTH             = 32,
    localparam int unsigned                 BANK_ADDR_WIDTH             = 32
    )(
    /// Clock, positive edge triggered.
    input  logic                                        clk_i,
    /// Reset, active low.
    input  logic                                        rst_ni,
    /// Mapping rules
    input map_rule_t [NUM_MAP_RULES-1:0]                mapping_rules_i,
    /// AXI ports
    input axi_req_t     [NUM_PORT-1:0]                  axi_req_i,
    output axi_resp_t   [NUM_PORT-1:0]                  axi_resp_o,
    /// ECC Reg Bus
    input l2_ecc_reg_req_t                              l2_ecc_reg_req_i,
    output l2_ecc_reg_rsp_t                             l2_ecc_reg_rsp_o
);
    //////////////////////////////////////////////
    //        Local Parameters and Types        //
    //////////////////////////////////////////////

    /*Basic settings*/
    localparam int unsigned                 BANK_WORD                   = BANK_DATA_WIDTH/8;
    localparam int unsigned                 NUM_BANK_PER_BANK_GROUP     = AXI_DATA_WIDTH/BANK_DATA_WIDTH;
    localparam int unsigned                 BANK_SIZE_IN_WORD           = L2_MEM_SIZE_IN_BYTE / (NUM_BANK_GROUP * NUM_BANK_PER_BANK_GROUP * BANK_WORD);
    localparam int unsigned                 BANK_GROUP_ADDR_WIDTH       = BANK_ADDR_WIDTH;
    localparam int unsigned                 BANK_LEVEL_EFFECT_ADDR_WIDTH= $clog2(BANK_SIZE_IN_WORD);
    localparam int unsigned                 BANK_GROUP_DATA_WIDTH       = NUM_BANK_PER_BANK_GROUP * BANK_DATA_WIDTH;

    /*TCDM*/
    localparam int unsigned                 TCDM_ADDR_WIDTH             = AXI_ADDR_WIDTH;
    localparam int unsigned                 TCDM_DATA_WIDTH             = AXI_DATA_WIDTH;
    localparam int unsigned                 TCDM_STRB_WIDTH             = TCDM_DATA_WIDTH / 8;
    typedef logic [TCDM_ADDR_WIDTH-1:0]     tcdm_addr_t;
    typedef logic [TCDM_DATA_WIDTH-1:0]     tcdm_data_t;
    typedef logic [TCDM_STRB_WIDTH-1:0]     tcdm_strb_t;

    /*Bank Group TCDM*/
    localparam int unsigned                 BKGP_TCDM_ADDR_WIDTH        = BANK_GROUP_ADDR_WIDTH;
    localparam int unsigned                 BKGP_TCDM_DATA_WIDTH        = AXI_DATA_WIDTH;
    localparam int unsigned                 BKGP_TCDM_STRB_WIDTH        = BKGP_TCDM_DATA_WIDTH / 8;
    typedef logic [BKGP_TCDM_ADDR_WIDTH-1:0]    bkgp_tcdm_addr_t;
    typedef logic [BKGP_TCDM_DATA_WIDTH-1:0]    bkgp_tcdm_data_t;
    typedef logic [BKGP_TCDM_STRB_WIDTH-1:0]    bkgp_tcdm_strb_t;
    typedef logic [NUM_BANK_PER_BANK_GROUP-1:0] bkgp_ecc_signal_t;


    /*Bank TCDM*/
    localparam int unsigned                 BANK_TCDM_ADDR_WIDTH        = BANK_ADDR_WIDTH;
    localparam int unsigned                 BANK_TCDM_DATA_WIDTH        = BANK_DATA_WIDTH;
    localparam int unsigned                 BANK_TCDM_STRB_WIDTH        = BANK_TCDM_DATA_WIDTH / 8;
    typedef logic [BANK_TCDM_ADDR_WIDTH-1:0]    bank_tcdm_addr_t;
    typedef logic [BANK_TCDM_DATA_WIDTH-1:0]    bank_tcdm_data_t;
    typedef logic [BANK_TCDM_STRB_WIDTH-1:0]    bank_tcdm_strb_t;

    /*AXI Types*/
    `include "axi/typedef.svh"
    `AXI_TYPEDEF_AW_CHAN_T(axi_aw_chan_t, logic[AXI_ADDR_WIDTH-1:0], logic[AXI_ID_WIDTH-1:0], logic[AXI_USER_WIDTH-1:0])
    `AXI_TYPEDEF_W_CHAN_T(axi_w_chan_t, logic[AXI_DATA_WIDTH-1:0], logic[AXI_DATA_WIDTH/8-1:0], logic[AXI_USER_WIDTH-1:0])
    `AXI_TYPEDEF_B_CHAN_T(axi_b_chan_t, logic[AXI_ID_WIDTH-1:0], logic[AXI_USER_WIDTH-1:0])
    `AXI_TYPEDEF_AR_CHAN_T(axi_ar_chan_t, logic[AXI_ADDR_WIDTH-1:0], logic[AXI_ID_WIDTH-1:0], logic[AXI_USER_WIDTH-1:0])
    `AXI_TYPEDEF_R_CHAN_T(axi_r_chan_t, logic[AXI_DATA_WIDTH-1:0], logic[AXI_ID_WIDTH-1:0], logic[AXI_USER_WIDTH-1:0])



    //////////////////////////////////////
    //        Signal Definition         //
    //////////////////////////////////////

    //tcdm signals after axi_to_mem modules
    tcdm_data_t         [NUM_PORT-1:0]                  tcdm_wdata;
    tcdm_addr_t         [NUM_PORT-1:0]                  tcdm_addr;
    logic               [NUM_PORT-1:0]                  tcdm_we;
    tcdm_strb_t         [NUM_PORT-1:0]                  tcdm_strb;
    logic               [NUM_PORT-1:0]                  tcdm_req;
    tcdm_data_t         [NUM_PORT-1:0]                  tcdm_rdata;
    logic               [NUM_PORT-1:0]                  tcdm_gnt;
    logic               [NUM_PORT-1:0]                  tcdm_rvalid;
    logic               [NUM_PORT-1:0]                  tcdm_errors;

    //bank group tcdm signals after crossbar
    bkgp_tcdm_data_t    [NUM_PORT-1:0]                  mapped_bkgp_tcdm_wdata;
    bkgp_tcdm_addr_t    [NUM_PORT-1:0]                  mapped_bkgp_tcdm_addr;
    logic               [NUM_PORT-1:0]                  mapped_bkgp_tcdm_we;
    bkgp_tcdm_strb_t    [NUM_PORT-1:0]                  mapped_bkgp_tcdm_strb;
    logic               [NUM_PORT-1:0]                  mapped_bkgp_tcdm_req;
    bkgp_tcdm_data_t    [NUM_PORT-1:0]                  mapped_bkgp_tcdm_rdata;
    logic               [NUM_PORT-1:0]                  mapped_bkgp_tcdm_gnt;
    logic               [NUM_PORT-1:0]                  mapped_bkgp_tcdm_rvalid;
    logic               [NUM_PORT-1:0]                  mapped_bkgp_errors;

    //bank group tcdm signals after crossbar
    bkgp_tcdm_data_t    [NUM_BANK_GROUP-1:0]            bkgp_tcdm_wdata;
    bkgp_tcdm_addr_t    [NUM_BANK_GROUP-1:0]            bkgp_tcdm_addr;
    logic               [NUM_BANK_GROUP-1:0]            bkgp_tcdm_we;
    bkgp_tcdm_strb_t    [NUM_BANK_GROUP-1:0]            bkgp_tcdm_strb;
    logic               [NUM_BANK_GROUP-1:0]            bkgp_tcdm_req;
    bkgp_tcdm_data_t    [NUM_BANK_GROUP-1:0]            bkgp_tcdm_rdata;
    logic               [NUM_BANK_GROUP-1:0]            bkgp_tcdm_gnt;
    logic               [NUM_BANK_GROUP-1:0]            bkgp_tcdm_rvalid;

    //bank group ecc signales
    logic               [NUM_BANK_GROUP-1:0]            bkgp_errors;
    bkgp_ecc_signal_t   [NUM_BANK_GROUP-1:0]            bank_faults;
    bkgp_ecc_signal_t   [NUM_BANK_GROUP-1:0]            scrub_fixes;
    bkgp_ecc_signal_t   [NUM_BANK_GROUP-1:0]            scrub_uncorrectables;
    bkgp_ecc_signal_t   [NUM_BANK_GROUP-1:0]            scrub_triggers;


    //////////////////////////////////
    //        Instance Modules      //
    //////////////////////////////////

    for (genvar i = 0; i < NUM_PORT; i++) begin: gen_axi_to_mem

        axi_req_t   axi_req_wo_atop;
        axi_resp_t  axi_resp_wo_atop;
        axi_req_t   axi_req_wo_atop_cut;
        axi_resp_t  axi_resp_wo_atop_cut;
        axi_resp_t  axi_resp_wo_atop_false_error_cut;

        axi_riscv_atomics_structs #(
            .AxiAddrWidth     ( AXI_ADDR_WIDTH    ),
            .AxiDataWidth     ( AXI_DATA_WIDTH ),
            .AxiIdWidth       ( AXI_ID_WIDTH    ),
            .AxiUserWidth     ( AXI_USER_WIDTH ),
            .AxiMaxReadTxns   ( ATM_MAX_READ_TXN  ),
            .AxiMaxWriteTxns  ( ATM_MAX_WRIT_TXN ),
            .AxiUserAsId      ( ATM_USER_AS_ID ),
            .AxiUserIdMsb     ( ATM_USER_ID_MSB ),
            .AxiUserIdLsb     ( ATM_USER_ID_LSB ),
            .RiscvWordWidth   ( ATM_RISCV_WORD ),
            .NAxiCuts         ( ATM_NUM_CUTS ),
            .CutOupPopInpGnt  ( CUT_OUT_POP_INP_GNT ),
            .axi_req_t        ( axi_req_t ),
            .axi_rsp_t        ( axi_resp_t )
        ) i_l2_atomics (
            .clk_i,
            .rst_ni,
            .axi_slv_req_i ( axi_req_i[i]     ),
            .axi_slv_rsp_o ( axi_resp_o[i]    ),
            .axi_mst_req_o ( axi_req_wo_atop  ),
            .axi_mst_rsp_i ( axi_resp_wo_atop )
        );

        axi_multicut #(
            .NoCuts     ( ATM_NUM_CUTS      ),
            .aw_chan_t  ( axi_aw_chan_t ),
            .w_chan_t   ( axi_w_chan_t  ),
            .b_chan_t   ( axi_b_chan_t  ),
            .ar_chan_t  ( axi_ar_chan_t ),
            .r_chan_t   ( axi_r_chan_t  ),
            .axi_req_t  ( axi_req_t     ),
            .axi_resp_t ( axi_resp_t    )
        ) i_axi_cut_after_atomics (
            .clk_i,
            .rst_ni,
            .slv_req_i  ( axi_req_wo_atop     ),
            .slv_resp_o ( axi_resp_wo_atop     ),
            .mst_req_o  ( axi_req_wo_atop_cut ),
            .mst_resp_i ( axi_resp_wo_atop_cut )
        );

        always_comb begin
            `AXI_SET_RESP_STRUCT(axi_resp_wo_atop_cut, axi_resp_wo_atop_false_error_cut)

            if (AXI_USER_ECC_ERR) begin
                axi_resp_wo_atop_cut.r.user[AXI_USER_ECC_ERR_BIT] = axi_resp_wo_atop_false_error_cut.r.resp == axi_pkg::RESP_SLVERR;
                axi_resp_wo_atop_cut.b.user[AXI_USER_ECC_ERR_BIT] = axi_resp_wo_atop_false_error_cut.b.resp == axi_pkg::RESP_SLVERR;
            end
            axi_resp_wo_atop_cut.r.resp = axi_pkg::RESP_OKAY;
            axi_resp_wo_atop_cut.b.resp = axi_pkg::RESP_OKAY;
        end


        axi_to_detailed_mem #(
            .axi_req_t   (axi_req_t     ),
            .axi_resp_t  (axi_resp_t    ),
            .AddrWidth   (AXI_ADDR_WIDTH),
            .DataWidth   (AXI_DATA_WIDTH),
            .IdWidth     (AXI_ID_WIDTH  ),
            .UserWidth   (AXI_USER_WIDTH),
            .NumBanks    (1             )
        ) i_axi_to_mem (
            .clk_i,
            .rst_ni,
            .busy_o      (/*open*/),
            .axi_req_i   (axi_req_wo_atop_cut),
            .axi_resp_o  (axi_resp_wo_atop_false_error_cut),
            .mem_req_o   (tcdm_req[i]   ),
            .mem_gnt_i   (tcdm_gnt[i]   ),
            .mem_addr_o  (tcdm_addr[i]  ),
            .mem_wdata_o (tcdm_wdata[i] ),
            .mem_strb_o  (tcdm_strb[i]  ),
            .mem_atop_o  (/*open*/),
            .mem_lock_o  (/*open*/),
            .mem_we_o    (tcdm_we[i]    ),
            .mem_id_o    (/*open*/),
            .mem_prot_o  (/*open*/),
            .mem_cache_o (/*open*/),
            .mem_qos_o   (/*open*/),
            .mem_region_o(/*open*/),
            .mem_user_o  (/*open*/),
            .mem_rvalid_i(tcdm_rvalid[i]),
            .mem_rdata_i (tcdm_rdata[i] ),
            .mem_err_i   (tcdm_errors[i]), // We temporarily use the AXI error signal for ECC errors.
            .mem_exokay_i('0)
        );

    end

    for (genvar i = 0; i < NUM_PORT; i++) begin: gen_addr_map

        dyn_mem_addr_map#(
            .NUM_BANK_GROUP              (NUM_BANK_GROUP),
            .NUM_MAP_RULES               (NUM_MAP_RULES),
            .BANK_GROUP_DATA_WIDTH       (BANK_GROUP_DATA_WIDTH),
            .BANK_LEVEL_EFFECT_ADDR_WIDTH(BANK_LEVEL_EFFECT_ADDR_WIDTH),
            .map_rule_t                  (map_rule_t),
            .bkgp_tcdm_data_t            (bkgp_tcdm_data_t),
            .bkgp_tcdm_strb_t            (bkgp_tcdm_strb_t),
            .bkgp_tcdm_addr_t            (bkgp_tcdm_addr_t),
            .tcdm_data_t                 (tcdm_data_t),
            .tcdm_strb_t                 (tcdm_strb_t),
            .tcdm_addr_t                 (tcdm_addr_t)
            )i_dyn_mem_addr_map (
            .clk_i,
            .rst_ni,
            .mapping_rules_i   (mapping_rules_i             ),
            .tcdm_wdata_i      (tcdm_wdata[i]               ),
            .tcdm_addr_i       (tcdm_addr[i]                ),
            .tcdm_we_i         (tcdm_we[i]                  ),
            .tcdm_strb_i       (tcdm_strb[i]                ),
            .tcdm_req_i        (tcdm_req[i]                 ),
            .tcdm_rdata_o      (tcdm_rdata[i]               ),
            .tcdm_ecc_err_o    (tcdm_errors[i]),
            .tcdm_gnt_o        (tcdm_gnt[i]                 ),
            .tcdm_rvalid_o     (tcdm_rvalid[i]              ),
            .bkgp_tcdm_wdata_o (mapped_bkgp_tcdm_wdata[i]   ),
            .bkgp_tcdm_addr_o  (mapped_bkgp_tcdm_addr[i]    ),
            .bkgp_tcdm_we_o    (mapped_bkgp_tcdm_we[i]      ),
            .bkgp_tcdm_strb_o  (mapped_bkgp_tcdm_strb[i]    ),
            .bkgp_tcdm_req_o   (mapped_bkgp_tcdm_req[i]     ),
            .bkgp_tcdm_rdata_i (mapped_bkgp_tcdm_rdata[i]   ),
            .bkgp_tcdm_ecc_err_i(mapped_bkgp_errors[i]),
            .bkgp_tcdm_gnt_i   (mapped_bkgp_tcdm_gnt[i]     ),
            .bkgp_tcdm_rvalid_i(mapped_bkgp_tcdm_rvalid[i]  )
        );

    end



    dyn_mem_tcdm_crossbar#(
        .NUM_PORT                    (NUM_PORT),
        .NUM_BANK_GROUP              (NUM_BANK_GROUP),
        .BANK_LEVEL_EFFECT_ADDR_WIDTH(BANK_LEVEL_EFFECT_ADDR_WIDTH),
        .BANK_GROUP_DATA_WIDTH       (BANK_GROUP_DATA_WIDTH),
        .bkgp_tcdm_data_t            (bkgp_tcdm_data_t),
        .bkgp_tcdm_strb_t            (bkgp_tcdm_strb_t),
        .bkgp_tcdm_addr_t            (bkgp_tcdm_addr_t)
        )i_dyn_mem_tcdm_crossbar (
        .clk_i,
        .rst_ni,
        .inp_bkgp_tcdm_wdata_i (mapped_bkgp_tcdm_wdata  ),
        .inp_bkgp_tcdm_addr_i  (mapped_bkgp_tcdm_addr   ),
        .inp_bkgp_tcdm_we_i    (mapped_bkgp_tcdm_we     ),
        .inp_bkgp_tcdm_strb_i  (mapped_bkgp_tcdm_strb   ),
        .inp_bkgp_tcdm_req_i   (mapped_bkgp_tcdm_req    ),
        .inp_bkgp_tcdm_rdata_o (mapped_bkgp_tcdm_rdata  ),
        .inp_bkgp_tcdm_ecc_err_o(mapped_bkgp_errors),
        .inp_bkgp_tcdm_gnt_o   (mapped_bkgp_tcdm_gnt    ),
        .inp_bkgp_tcdm_rvalid_o(mapped_bkgp_tcdm_rvalid ),
        .out_bkgp_tcdm_wdata_o (bkgp_tcdm_wdata         ),
        .out_bkgp_tcdm_addr_o  (bkgp_tcdm_addr          ),
        .out_bkgp_tcdm_we_o    (bkgp_tcdm_we            ),
        .out_bkgp_tcdm_strb_o  (bkgp_tcdm_strb          ),
        .out_bkgp_tcdm_req_o   (bkgp_tcdm_req           ),
        .out_bkgp_tcdm_rdata_i (bkgp_tcdm_rdata         ),
        .out_bkgp_tcdm_ecc_err_i(bkgp_errors),
        .out_bkgp_tcdm_gnt_i   (bkgp_tcdm_gnt           ),
        .out_bkgp_tcdm_rvalid_i(bkgp_tcdm_rvalid        )
    );



    for (genvar i = 0; i < NUM_BANK_GROUP; i++) begin: gen_bank_group


        dyn_mem_bank_group#(
            .BANK_SIZE_IN_WORD      (BANK_SIZE_IN_WORD),
            .NUM_BANK_PER_BANK_GROUP(NUM_BANK_PER_BANK_GROUP),
            .bkgp_tcdm_data_t       (bkgp_tcdm_data_t),
            .bkgp_tcdm_strb_t       (bkgp_tcdm_strb_t),
            .bkgp_tcdm_addr_t       (bkgp_tcdm_addr_t),
            .bank_tcdm_data_t       (bank_tcdm_data_t),
            .bank_tcdm_strb_t       (bank_tcdm_strb_t),
            .bank_tcdm_addr_t       (bank_tcdm_addr_t)
            )i_dyn_mem_bank_group (
            .clk_i,
            .rst_ni,
            .bkgp_tcdm_wdata_i          (bkgp_tcdm_wdata[i]     ),
            .bkgp_tcdm_addr_i           (bkgp_tcdm_addr[i]      ),
            .bkgp_tcdm_we_i             (bkgp_tcdm_we[i]        ),
            .bkgp_tcdm_strb_i           (bkgp_tcdm_strb[i]      ),
            .bkgp_tcdm_req_i            (bkgp_tcdm_req[i]       ),
            .bkgp_tcdm_rdata_o          (bkgp_tcdm_rdata[i]     ),
            .bkgp_tcdm_gnt_o            (bkgp_tcdm_gnt[i]       ),
            .bkgp_tcdm_rvalid_o         (bkgp_tcdm_rvalid[i]    ),
            .ecc_bank_faults_o          (bank_faults[i]         ),
            .ecc_scrubber_fixes_o       (scrub_fixes[i]         ),
            .ecc_scrub_uncorrectables_o (scrub_uncorrectables[i]),
            .ecc_scrub_triggers_i       (scrub_triggers[i]      ),
            .ecc_error_o                (bkgp_errors[i]         )
        );

    end

    ecc_manager #(
        .NumBanks      ( NUM_BANK_GROUP * NUM_BANK_PER_BANK_GROUP ),
        .ecc_mgr_req_t ( l2_ecc_reg_req_t ),
        .ecc_mgr_rsp_t ( l2_ecc_reg_rsp_t )
    ) i_ecc_manager (
        .clk_i,
        .rst_ni,
        .ecc_mgr_req_i        ( l2_ecc_reg_req_i    ),
        .ecc_mgr_rsp_o        ( l2_ecc_reg_rsp_o    ),
        .bank_faults_i        ( bank_faults         ),
        .scrub_fix_i          ( scrub_fixes         ),
        .scrub_uncorrectable_i( scrub_uncorrectables),
        .scrub_trigger_o      ( scrub_triggers      ),
        .test_write_mask_no   ( /*open*/)
    );

    assign ecc_error_o = |bkgp_errors;

endmodule : dyn_mem_top
