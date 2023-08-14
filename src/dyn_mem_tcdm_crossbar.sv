// Copyright 2023 ETH Zurich and 
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 21.Mar.2023

// TCDM Crossbar for Dynamic Scratchpad Memory

module dyn_mem_tcdm_crossbar#(
  parameter int unsigned           NUM_PORT                       = 2,
  parameter int unsigned           NUM_BANK_GROUP                 = 2,
  parameter int unsigned           BANK_GROUP_DATA_WIDTH          = 64,
  parameter int unsigned           BANK_LEVEL_EFFECT_ADDR_WIDTH   = 64,
  parameter type                   bkgp_tcdm_data_t               = logic,
  parameter type                   bkgp_tcdm_addr_t               = logic,
  parameter type                   bkgp_tcdm_strb_t               = logic
  )(
  /// Clock, positive edge triggered.
  input  logic                                  clk_i,
  /// Reset, active low.
  input  logic                                  rst_ni,
  /// Upstream bank group tcdm interface
  input  bkgp_tcdm_data_t [NUM_PORT-1:0]        inp_bkgp_tcdm_wdata_i,
  input  bkgp_tcdm_addr_t [NUM_PORT-1:0]        inp_bkgp_tcdm_addr_i,
  input  logic            [NUM_PORT-1:0]        inp_bkgp_tcdm_we_i,
  input  bkgp_tcdm_strb_t [NUM_PORT-1:0]        inp_bkgp_tcdm_strb_i,
  input  logic            [NUM_PORT-1:0]        inp_bkgp_tcdm_req_i,
  output bkgp_tcdm_data_t [NUM_PORT-1:0]        inp_bkgp_tcdm_rdata_o,
  output logic            [NUM_PORT-1:0]        inp_bkgp_tcdm_gnt_o,
  output logic            [NUM_PORT-1:0]        inp_bkgp_tcdm_rvalid_o,
  /// Downstream bank group tcdm interface
  output bkgp_tcdm_data_t [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_wdata_o,
  output bkgp_tcdm_addr_t [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_addr_o,
  output logic            [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_we_o,
  output bkgp_tcdm_strb_t [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_strb_o,
  output logic            [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_req_o,
  input  bkgp_tcdm_data_t [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_rdata_i,
  input  logic            [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_gnt_i,
  input  logic            [NUM_BANK_GROUP-1:0]  out_bkgp_tcdm_rvalid_i
);

  localparam int unsigned ByteOffset = $clog2(BANK_GROUP_DATA_WIDTH/8);
  localparam int unsigned StrbWidth = BANK_GROUP_DATA_WIDTH/8;

  // Width of the bank select signal.
  localparam int unsigned SelWidth = cf_math_pkg::idx_width(NUM_BANK_GROUP);
  typedef logic [SelWidth-1:0] select_t;
  select_t [NUM_PORT-1:0] bank_select;

  typedef struct packed {
    // Which bank was selected.
    select_t bank_select;
    // The response is valid.
    logic valid;
  } rsp_t;

  typedef struct packed {
    bkgp_tcdm_data_t wdata;
    bkgp_tcdm_addr_t addr;
    logic            we;
    bkgp_tcdm_strb_t strb;
  } tcdm_req_t;

  // Generate the `bank_select` signal based on the address.
  // This generates a bank interleaved addressing scheme, where consecutive
  // addresses are routed to individual banks.
  for (genvar i = 0; i < NUM_PORT; i++) begin : gen_bank_select
    assign bank_select[i] = inp_bkgp_tcdm_addr_i[i][ByteOffset+:SelWidth];
  end

  tcdm_req_t [NUM_PORT-1:0] in_req;
  tcdm_req_t [NUM_BANK_GROUP-1:0] out_req;

  // The usual struct packing unpacking.
  for (genvar i = 0; i < NUM_PORT; i++) begin : gen_inp_req
    assign in_req[i] = '{
      addr:   inp_bkgp_tcdm_addr_i[i][ByteOffset+SelWidth+:BANK_LEVEL_EFFECT_ADDR_WIDTH],
      we:     inp_bkgp_tcdm_we_i[i],
      wdata:  inp_bkgp_tcdm_wdata_i[i],
      strb:   inp_bkgp_tcdm_strb_i[i]
    };

  end

  for (genvar i = 0; i < NUM_BANK_GROUP; i++) begin : gen_out_req
    assign out_bkgp_tcdm_wdata_o[i] = out_req[i].wdata;
    assign out_bkgp_tcdm_we_o[i] = out_req[i].we;
    assign out_bkgp_tcdm_addr_o[i] = out_req[i].addr;
    assign out_bkgp_tcdm_strb_o[i] = out_req[i].strb;
  end

  // ------------
  // Request Side
  // ------------
    stream_xbar #(
      .NumInp      ( NUM_PORT    ),
      .NumOut      ( NUM_BANK_GROUP    ),
      .payload_t   ( tcdm_req_t ),
      .OutSpillReg ( 1'b0      ),
      .ExtPrio     ( 1'b0      ),
      .AxiVldRdy   ( 1'b1      ),
      .LockIn      ( 1'b1      )
    ) i_stream_xbar (
      .clk_i,
      .rst_ni,
      .flush_i ( 1'b0 ),
      .rr_i    ( '0 ),
      .data_i  ( in_req ),
      .sel_i   ( bank_select ),
      .valid_i ( inp_bkgp_tcdm_req_i ),
      .ready_o ( inp_bkgp_tcdm_gnt_o ),
      .data_o  ( out_req ),
      .idx_o   ( ),
      .valid_o ( out_bkgp_tcdm_req_o ),
      .ready_i ( out_bkgp_tcdm_gnt_i )
    );

  // -------------
  // Response Side
  // -------------
  // A simple multiplexer is sufficient here.
  for (genvar i = 0; i < NUM_PORT; i++) begin : gen_rsp_mux
    rsp_t out_rsp_mux, in_rsp_mux;
    assign in_rsp_mux = '{
      bank_select: bank_select[i],
      valid: inp_bkgp_tcdm_req_i[i] & inp_bkgp_tcdm_gnt_o[i]
    };
    // A this is a fixed latency interconnect a simple shift register is
    // sufficient to track the arbitration decisions.
    shift_reg #(
      .dtype ( rsp_t ),
      .Depth ( 1 )
    ) i_shift_reg (
      .clk_i,
      .rst_ni,
      .d_i ( in_rsp_mux ),
      .d_o ( out_rsp_mux )
    );
    assign inp_bkgp_tcdm_rdata_o[i] = out_bkgp_tcdm_rdata_i[out_rsp_mux.bank_select];
    assign inp_bkgp_tcdm_rvalid_o[i] = out_rsp_mux.valid;
  end


endmodule
