// Copyright 2023 ETH Zurich and 
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 22.Mar.2023

//Testbench for Dynamic Scratchpad Memory

module dyn_mem_tb import dyn_mem_pkg::*;;

    `include "axi/assign.svh"
    `include "axi/typedef.svh"
    `include "register_interface/typedef.svh"
    `include "register_interface/assign.svh"


    ////////////////////////////////
    //  L2 Memory Basic Settings  //
    ////////////////////////////////

    localparam int unsigned                 L2_MEM_SIZE_IN_BYTE         = 2**20;
    localparam int unsigned                 NUM_BANK_GROUP              = 2;

    //////////////////////
    //  AXI Parameters  //
    //////////////////////

    localparam int unsigned                 NUM_PORT                    = 2;
    localparam int unsigned                 AXI_ADDR_WIDTH              = 48;
    localparam int unsigned                 AXI_DATA_WIDTH              = 64;
    localparam int unsigned                 AXI_STRB_WIDTH              = AXI_DATA_WIDTH / 8;
    localparam int unsigned                 AXI_ID_WIDTH                = 5;
    localparam int unsigned                 AXI_USER_WIDTH              = 5;

    typedef logic [AXI_ADDR_WIDTH-1:0]      axi_addr_t;
    typedef logic [AXI_DATA_WIDTH-1:0]      axi_data_t;
    typedef logic [AXI_STRB_WIDTH-1:0]      axi_strb_t;
    typedef logic [AXI_ID_WIDTH-1:0]        axi_id_t;
    typedef logic [AXI_USER_WIDTH-1:0]      axi_user_t;

    `AXI_TYPEDEF_ALL(axi, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)

    ///////////////////////
    //  ECC Mgr Reg Bus  //
    ///////////////////////

    `REG_BUS_TYPEDEF_ALL(l2_ecc_reg, logic[AXI_ADDR_WIDTH-1:0], logic[AXI_DATA_WIDTH-1:0], logic[(AXI_DATA_WIDTH/8)-1:0]);

    ///////////////////////
    //  Address Mapping  //
    ///////////////////////

    localparam int unsigned                 NUM_MAP_RULES               = 4;

    typedef struct packed {
        int unsigned                        idx;
        logic [AXI_ADDR_WIDTH-1:0]          start_addr;
        logic [AXI_ADDR_WIDTH-1:0]          end_addr;
    } map_rule_t;

    localparam logic [AXI_ADDR_WIDTH-1:0]   PORT1_INTERLEAVE_BASE       = 'hA000_0000_0000;
    localparam logic [AXI_ADDR_WIDTH-1:0]   PORT1_NONE_INTER_BASE       = 'hB000_0000_0000;
    localparam logic [AXI_ADDR_WIDTH-1:0]   PORT2_INTERLEAVE_BASE       = 'hC000_0000_0000;
    localparam logic [AXI_ADDR_WIDTH-1:0]   PORT2_NONE_INTER_BASE       = 'hD000_0000_0000;

    map_rule_t [NUM_MAP_RULES-1:0] mapping_rules = '{
        '{idx: dyn_mem_pkg::INTERLEAVE, start_addr: PORT1_INTERLEAVE_BASE, end_addr: PORT1_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE},
        '{idx: dyn_mem_pkg::INTERLEAVE, start_addr: PORT2_INTERLEAVE_BASE, end_addr: PORT2_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE},
        '{idx: dyn_mem_pkg::NONE_INTER, start_addr: PORT1_NONE_INTER_BASE, end_addr: PORT1_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE},
        '{idx: dyn_mem_pkg::NONE_INTER, start_addr: PORT2_NONE_INTER_BASE, end_addr: PORT2_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE}
    };

    //////////////////////////////////////
    //        Signal Definition         //
    //////////////////////////////////////

    localparam time ClkPeriod = 10ns;
    localparam time ApplTime =  2ns;
    localparam time TestTime =  8ns;

    logic  clk, rst_n;

    axi_req_t   [NUM_PORT-1:0]  axi_req;
    axi_resp_t  [NUM_PORT-1:0]  axi_resp;
    logic                       ecc_error;

    AXI_BUS_DV #(
        .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
        .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
        .AXI_ID_WIDTH   ( AXI_ID_WIDTH  ),
        .AXI_USER_WIDTH ( AXI_USER_WIDTH )
    ) axi_bus_dv [NUM_PORT-1:0](clk);

    for (genvar i = 0; i < NUM_PORT; i++) begin: gen_axi_dv
        `AXI_ASSIGN_TO_REQ(axi_req[i],axi_bus_dv[i])
        `AXI_ASSIGN_FROM_RESP(axi_bus_dv[i], axi_resp[i])
    end

    //////////////////////////////////////
    //        Clock Generation          //
    //////////////////////////////////////
    initial begin
        rst_n = 0;
        $display("start");
        repeat (3) begin
            #(ClkPeriod/2) clk = 0;
            #(ClkPeriod/2) clk = 1;
        end
        rst_n = 1;
        $display("rst up");
        forever begin
            #(ClkPeriod/2) clk = 0;
            #(ClkPeriod/2) clk = 1;
        end
    end

    //////////////////////
    //        DUT       //
    //////////////////////

    
    dyn_mem_top #(
        //AXI
        .NUM_PORT             (NUM_PORT),
        .AXI_DATA_WIDTH       (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH       (AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH       (AXI_USER_WIDTH),
        .AXI_ID_WIDTH         (AXI_ID_WIDTH),
        .axi_req_t            (axi_req_t),
        .axi_resp_t           (axi_resp_t),
        .l2_ecc_reg_req_t     (l2_ecc_reg_req_t),
        .l2_ecc_reg_rsp_t     (l2_ecc_reg_rsp_t),
        // Addr Mapping (interleave / non-interleave)
        .NUM_MAP_RULES        (NUM_MAP_RULES),
        .map_rule_t           (map_rule_t),
        // L2 Memory
        .L2_MEM_SIZE_IN_BYTE  (L2_MEM_SIZE_IN_BYTE),
        .NUM_BANK_GROUP       (NUM_BANK_GROUP)
    )i_dyn_mem_top (
        .clk_i                (clk       ),
        .rst_ni               (rst_n     ),
        .mapping_rules_i      (mapping_rules),
        .axi_req_i            (axi_req   ),
        .axi_resp_o           (axi_resp  ),
        .l2_ecc_reg_req_i     ('0),
        .l2_ecc_reg_rsp_o     (/*open*/),
        .ecc_error_o          (ecc_error )
    );

    ///////////////////////////////////////////////////
    //        Local Parameters for testbench         //
    ///////////////////////////////////////////////////

    localparam int unsigned                 BANK_DATA_WIDTH             = 32;
    localparam int unsigned                 BANK_ADDR_WIDTH             = 32;
    localparam int unsigned                 BANK_WORD                   = BANK_DATA_WIDTH/8;
    localparam int unsigned                 NUM_BANK_PER_BANK_GROUP     = AXI_DATA_WIDTH/BANK_DATA_WIDTH;
    localparam int unsigned                 BANK_SIZE_IN_WORD           = L2_MEM_SIZE_IN_BYTE / (NUM_BANK_GROUP * NUM_BANK_PER_BANK_GROUP * BANK_WORD);
    localparam int unsigned                 BANK_GROUP_ADDR_WIDTH       = BANK_ADDR_WIDTH;
    localparam int unsigned                 BANK_LEVEL_EFFECT_ADDR_WIDTH= $clog2(BANK_SIZE_IN_WORD);
    localparam int unsigned                 BANK_GROUP_DATA_WIDTH       = NUM_BANK_PER_BANK_GROUP * BANK_DATA_WIDTH;

    /*TCDM Parameters*/

    localparam int unsigned                 TCDM_ADDR_WIDTH             = AXI_ADDR_WIDTH;
    localparam int unsigned                 TCDM_DATA_WIDTH             = AXI_DATA_WIDTH;
    localparam int unsigned                 TCDM_STRB_WIDTH             = TCDM_DATA_WIDTH / 8;
    typedef logic [TCDM_ADDR_WIDTH-1:0]     tcdm_addr_t;
    typedef logic [TCDM_DATA_WIDTH-1:0]     tcdm_data_t;
    typedef logic [TCDM_STRB_WIDTH-1:0]     tcdm_strb_t;

    /*Bank Group TCDM Parameters*/

    localparam int unsigned                 BKGP_TCDM_ADDR_WIDTH        = BANK_GROUP_ADDR_WIDTH;
    localparam int unsigned                 BKGP_TCDM_DATA_WIDTH        = AXI_DATA_WIDTH;
    localparam int unsigned                 BKGP_TCDM_STRB_WIDTH        = BKGP_TCDM_DATA_WIDTH / 8;
    typedef logic [BKGP_TCDM_ADDR_WIDTH-1:0]    bkgp_tcdm_addr_t;
    typedef logic [BKGP_TCDM_DATA_WIDTH-1:0]    bkgp_tcdm_data_t;
    typedef logic [BKGP_TCDM_STRB_WIDTH-1:0]    bkgp_tcdm_strb_t;

    /*Bank TCDM Parameters*/

    localparam int unsigned                 BANK_TCDM_ADDR_WIDTH        = BANK_ADDR_WIDTH;
    localparam int unsigned                 BANK_TCDM_DATA_WIDTH        = BANK_DATA_WIDTH;
    localparam int unsigned                 BANK_TCDM_STRB_WIDTH        = BANK_TCDM_DATA_WIDTH / 8;
    typedef logic [BANK_TCDM_ADDR_WIDTH-1:0]    bank_tcdm_addr_t;
    typedef logic [BANK_TCDM_DATA_WIDTH-1:0]    bank_tcdm_data_t;
    typedef logic [BANK_TCDM_STRB_WIDTH-1:0]    bank_tcdm_strb_t;

    //////////////////////////////////////////////////
    //        Scoreborad of Mapping Functions       //
    //////////////////////////////////////////////////

    typedef struct packed {
        tcdm_data_t wdata;
        tcdm_addr_t addr;
        logic       we;
        tcdm_strb_t strb;
    } tcdm_req_t;

    typedef struct packed {
        bkgp_tcdm_data_t wdata;
        bkgp_tcdm_addr_t addr;
        logic            we;
        bkgp_tcdm_strb_t strb;
    } bkgp_tcdm_req_t;

    typedef struct packed {
        logic [$clog2(NUM_BANK_GROUP)-1:0]  bkgp_id;
        bkgp_tcdm_addr_t                    bkgp_addr;
    } bkgp_info_t;


    tcdm_req_t tcdm_queue[NUM_PORT][$];
    bkgp_tcdm_req_t bkgp_queue[NUM_BANK_GROUP][$];

    function int getMapType(input tcdm_addr_t tcdm_addr);
        automatic int map_type = INTERLEAVE;
        automatic int find_match_rule = 0;


        //check which mapping mode is used
        for (int i = 0; i < NUM_MAP_RULES; i++) begin
            if ( tcdm_addr>= mapping_rules[i].start_addr && tcdm_addr <= mapping_rules[i].end_addr) begin
                map_type = mapping_rules[i].idx;
                find_match_rule = 1;
                break;
            end
        end
        if (find_match_rule == 0) begin
            $fatal(1,"map2BankGroupSpace:  Can not analysis this tcdm addr %0h",tcdm_addr);
        end else begin
            return map_type;
        end
    endfunction


    function bkgp_info_t map2BankGroupSpace(input tcdm_addr_t tcdm_addr);
        automatic int map_type = INTERLEAVE;
        automatic int find_match_rule = 0;
        automatic bkgp_tcdm_addr_t port_efficetive_addr;
        automatic bkgp_tcdm_addr_t bkgp_addr;
        automatic logic [$clog2(NUM_BANK_GROUP)-1:0] bkgp_id;


        //check which mapping mode is used
        for (int i = 0; i < NUM_MAP_RULES; i++) begin
            if ( tcdm_addr>= mapping_rules[i].start_addr && tcdm_addr <= mapping_rules[i].end_addr) begin
                map_type = mapping_rules[i].idx;
                find_match_rule = 1;
                break;
            end
        end
        if (find_match_rule == 0) begin
            $fatal(1,"map2BankGroupSpace:  Can not analysis this tcdm addr %0h",tcdm_addr);
        end 

        //convert address into bank group space
        port_efficetive_addr = (tcdm_addr[$clog2(L2_MEM_SIZE_IN_BYTE)-1:0])>>($clog2(BANK_GROUP_DATA_WIDTH/8));
        if (map_type == INTERLEAVE) begin
            bkgp_id = port_efficetive_addr%NUM_BANK_GROUP;
            bkgp_addr = port_efficetive_addr/NUM_BANK_GROUP;
        end else begin
            bkgp_id = port_efficetive_addr/BANK_SIZE_IN_WORD;
            bkgp_addr = port_efficetive_addr%BANK_SIZE_IN_WORD;
        end

        return '{bkgp_id: bkgp_id, bkgp_addr: bkgp_addr};
        
    endfunction

    function tcdm_addr_t bankGroupSpace2TcdmAddr(input bkgp_info_t bkgp_info, int map_type, tcdm_addr_t tcdm_addr_temp);
        automatic tcdm_addr_t addr;
        addr = tcdm_addr_temp;
        if (map_type == INTERLEAVE) begin
            addr[$clog2(L2_MEM_SIZE_IN_BYTE)-1:0] = (bkgp_info.bkgp_addr*NUM_BANK_GROUP +bkgp_info.bkgp_id)*NUM_BANK_PER_BANK_GROUP*BANK_WORD; 
        end else begin
            addr[$clog2(L2_MEM_SIZE_IN_BYTE)-1:0] = (bkgp_info.bkgp_id*BANK_SIZE_IN_WORD +bkgp_info.bkgp_addr)*NUM_BANK_PER_BANK_GROUP*BANK_WORD;
        end
        return addr;
    endfunction

    task checkMapFunction();
        automatic logic [$clog2(NUM_BANK_GROUP)-1:0] bkgp_pointer = 0;
        automatic int unsigned no_match_cnt = 0;
        forever begin
            @(posedge clk);
            if (bkgp_queue[bkgp_pointer].size() !== 0) begin
                automatic bkgp_tcdm_req_t bkgp_tcdm_req;
                automatic tcdm_req_t tcdm_req;
                automatic bkgp_info_t bkgp_info;
                automatic int find_match;

                find_match = 0;
                bkgp_tcdm_req = bkgp_queue[bkgp_pointer][0];

                // $display("----------  Now chcking bank group %d  -----------",bkgp_pointer);

                for (int i = 0; i < NUM_PORT; i++) begin
                    if (tcdm_queue[i].size() !== 0) begin
                        tcdm_req = tcdm_queue[i][0];
                        bkgp_info = map2BankGroupSpace(tcdm_req.addr);
                        if ( 
                                bkgp_info.bkgp_id == bkgp_pointer &&
                                bkgp_info.bkgp_addr == bkgp_tcdm_req.addr &&
                                tcdm_req.strb == bkgp_tcdm_req.strb &&
                                tcdm_req.wdata == bkgp_tcdm_req.wdata &&
                                tcdm_req.we == bkgp_tcdm_req.we
                            ) begin
                            // $displayh("We find match port %d: %p to bank group %d: %p",i,tcdm_req,bkgp_pointer,bkgp_tcdm_req);
                            find_match = 1;
                            tcdm_queue[i].pop_front();
                            bkgp_queue[bkgp_pointer].pop_front();
                            break;
                        end else begin
                            // $displayh("No match for port %d: %p to bank group %d: %p",i,tcdm_req,bkgp_pointer,bkgp_tcdm_req);
                        end
                    end
                end
                
                if (find_match) begin
                    no_match_cnt = 0;
                end else begin
                    no_match_cnt = no_match_cnt + 1;
                    if (no_match_cnt > (2* NUM_BANK_GROUP * NUM_PORT)) begin
                        $fatal(1,"checkMapFunction: no match in %d tries, something wrong happens, pleae check !!!", 2* NUM_BANK_GROUP * NUM_PORT);
                    end
                end
            end
            bkgp_pointer = bkgp_pointer + 1;
        end
    endtask

    //push to tcdm queues
    for (genvar i = 0; i < NUM_PORT; i++) begin
        initial begin
            @(posedge rst_n);
            forever begin
                @(posedge clk);
                if (dyn_mem_tb.i_dyn_mem_top.tcdm_req[i] & dyn_mem_tb.i_dyn_mem_top.tcdm_gnt[i]) begin
                    automatic tcdm_req_t tcdm_req_payload;
                    tcdm_req_payload.addr = dyn_mem_tb.i_dyn_mem_top.tcdm_addr[i];
                    tcdm_req_payload.strb = dyn_mem_tb.i_dyn_mem_top.tcdm_strb[i];
                    tcdm_req_payload.we = dyn_mem_tb.i_dyn_mem_top.tcdm_we[i];
                    tcdm_req_payload.wdata = dyn_mem_tb.i_dyn_mem_top.tcdm_wdata[i];
                    tcdm_queue[i].push_back(tcdm_req_payload);
                end
            end
        end
    end

    //push to bank group queues
    for (genvar i = 0; i < NUM_BANK_GROUP; i++) begin
        initial begin
            @(posedge rst_n);
            forever begin
                @(posedge clk);
                if (dyn_mem_tb.i_dyn_mem_top.bkgp_tcdm_req[i] & dyn_mem_tb.i_dyn_mem_top.bkgp_tcdm_gnt[i]) begin
                    automatic bkgp_tcdm_req_t bkgp_tcdm_req_payload;
                    bkgp_tcdm_req_payload.addr = dyn_mem_tb.i_dyn_mem_top.bkgp_tcdm_addr[i];
                    bkgp_tcdm_req_payload.strb = dyn_mem_tb.i_dyn_mem_top.bkgp_tcdm_strb[i];
                    bkgp_tcdm_req_payload.we = dyn_mem_tb.i_dyn_mem_top.bkgp_tcdm_we[i];
                    bkgp_tcdm_req_payload.wdata = dyn_mem_tb.i_dyn_mem_top.bkgp_tcdm_wdata[i];
                    bkgp_queue[i].push_back(bkgp_tcdm_req_payload);
                end
            end
        end
    end

    initial begin
        @(posedge rst_n);
        checkMapFunction();
    end

    //////////////////////////
    //        Driver        //
    //////////////////////////

    typedef axi_test::axi_rand_master #(
        // AXI interface parameters
        .AW ( AXI_ADDR_WIDTH ),
        .DW ( AXI_DATA_WIDTH ),
        .IW ( AXI_ID_WIDTH ),
        .UW ( AXI_USER_WIDTH ),
        .AX_MAX_WAIT_CYCLES(20),
        .AXI_BURST_FIXED(0),
        // Stimuli application and test time
        .TA ( ApplTime ),
        .TT ( TestTime )
    ) axi_master_t;

    axi_master_t axi_master [NUM_PORT];

    for (genvar i = 0; i < NUM_PORT; i++) begin: gen_axi_master
        initial begin
            axi_master[i] = new (axi_bus_dv[i]);
            axi_master[i].reset();
        end
    end

    /// simulation tasks
    task init_axi_master();
        axi_master[0].reset();
        axi_master[1].reset();
        axi_master[0].add_memory_region(PORT1_INTERLEAVE_BASE, PORT1_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[0].add_memory_region(PORT1_NONE_INTER_BASE, PORT1_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_INTERLEAVE_BASE, PORT2_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_NONE_INTER_BASE, PORT2_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
    endtask : init_axi_master


    task clear_all_master_mem_regions();
        for (int i = 0; i < NUM_PORT; i++) begin
            while(axi_master[i].mem_map.size()) begin
                axi_master[i].mem_map.pop_front();
            end
        end
    endtask : clear_all_master_mem_regions


    task random_master_simulation();
        $displayh("Start random axi transaction insertion");
        init_axi_master();
        fork
            axi_master[0].run(100,100);
            axi_master[1].run(100,100);
        join
    endtask

    task initL2();
        typedef logic[7:0] my_byte_t;
        automatic axi_master_t::ax_beat_t aw = new ;
        automatic axi_master_t::ax_beat_t ar = new ;
        automatic axi_master_t::w_beat_t w = new ;
        automatic axi_master_t::b_beat_t b = new ;
        automatic axi_master_t::r_beat_t r = new ;

        aw = axi_master[0].new_rand_burst(0);
        aw.ax_len = 0;
        aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
        aw.ax_atop = axi_pkg::ATOP_NONE;
        aw.ax_addr = PORT1_INTERLEAVE_BASE;

        for (int i = 0; i < (L2_MEM_SIZE_IN_BYTE/(BANK_WORD*NUM_BANK_PER_BANK_GROUP)); i++) begin
            aw.ax_addr = PORT1_INTERLEAVE_BASE + i*(BANK_WORD*NUM_BANK_PER_BANK_GROUP);

            std::randomize(w);
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                w.w_strb[j] = 1;
            end
            w.w_last = 1;

            //write one beat 
            fork
                axi_master[0].drv.send_aw(aw);
                axi_master[0].drv.send_w(w);
            join

            //receive write response
            axi_master[0].drv.recv_b(b);

            if (i%1024 == 0) begin
                $displayh("initL2 %d, addr %h",i,aw.ax_addr);
            end

        end
    endtask : initL2


    task single_port_one_beat_axi_write_read_test(int num_test);
        typedef logic[7:0] my_byte_t;
        automatic axi_master_t::ax_beat_t aw = new ;
        automatic axi_master_t::ax_beat_t ar = new ;
        automatic axi_master_t::w_beat_t w = new ;
        automatic axi_master_t::b_beat_t b = new ;
        automatic axi_master_t::r_beat_t r = new ;
        automatic my_byte_t [AXI_DATA_WIDTH/8-1:0] write_one_beat, read_one_beat; 

        clear_all_master_mem_regions();
        init_axi_master();
        
        for (int i = 0; i < num_test; i++) begin
            aw = axi_master[0].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            $displayh("One beat test on PortA %d, addr %h",i,aw.ax_addr);
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                w.w_strb[j] = 1;
            end
            //write one beat 
            fork
                axi_master[0].drv.send_aw(aw);
                axi_master[0].drv.send_w(w);
            join
            //receive write response
            axi_master[0].drv.recv_b(b);
            //read the same beat
            ar = aw;
            axi_master[0].drv.send_ar(ar);
            axi_master[0].drv.recv_r(r);
            read_one_beat = r.r_data;
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end

        for (int i = 0; i < num_test; i++) begin
            aw = axi_master[1].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            $displayh("One beat test on PortB %d, addr %h",i,aw.ax_addr);
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[1].drv.send_aw(aw);
                axi_master[1].drv.send_w(w);
            join
            //receive write response
            axi_master[1].drv.recv_b(b);
            //read the same beat
            ar = aw;
            axi_master[1].drv.send_ar(ar);
            axi_master[1].drv.recv_r(r);
            read_one_beat = r.r_data;
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end

        $display("single_port_one_beat_axi_write_read_test perfectly done!");
    endtask : single_port_one_beat_axi_write_read_test


    task double_port_one_beat_axi_write_read_test(int num_test);
        typedef logic[7:0] my_byte_t;
        automatic axi_master_t::ax_beat_t aw = new ;
        automatic axi_master_t::ax_beat_t ar = new ;
        automatic axi_master_t::w_beat_t w = new ;
        automatic axi_master_t::b_beat_t b = new ;
        automatic axi_master_t::r_beat_t r = new ;
        automatic my_byte_t [AXI_DATA_WIDTH/8-1:0] write_one_beat, read_one_beat; 
        automatic bkgp_info_t bkgp_info;
        automatic tcdm_addr_t tmp_addr, aw_addr;
        automatic int map_type_w, map_type_r;

        /// PortA interleaved/non-interleaved write, PortA non-interleaved/interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[0].add_memory_region(PORT1_INTERLEAVE_BASE, PORT1_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[0].add_memory_region(PORT1_NONE_INTER_BASE, PORT1_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortA interleaved write---//
            aw = axi_master[0].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            map_type_w = getMapType(aw.ax_addr);
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[0].drv.send_aw(aw);
                axi_master[0].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[0].drv.recv_b(b);

            //---PortA non-interleaved read---//
            //addr transfer
            ar = axi_master[0].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            map_type_r = getMapType(ar.ax_addr);
            bkgp_info = map2BankGroupSpace(aw.ax_addr);
            ar = aw;
            if (map_type_w == map_type_r) begin
                if (map_type_w == INTERLEAVE) begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, INTERLEAVE, tmp_addr);
                end else begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, NONE_INTER, tmp_addr);
                end
            end else begin
                if (map_type_w == INTERLEAVE) begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, NONE_INTER, tmp_addr);
                end else begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, INTERLEAVE, tmp_addr);
                end
            end
                
            // $displayh("%p",ar);
            axi_master[0].drv.send_ar(ar);
            axi_master[0].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortA interleaved/non-interleaved write, PortA non-interleaved/interleaved read %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end


        /// PortB interleaved/non-interleaved write, PortB non-interleaved/interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[1].add_memory_region(PORT2_INTERLEAVE_BASE, PORT2_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_NONE_INTER_BASE, PORT2_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortA interleaved write---//
            aw = axi_master[1].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            map_type_w = getMapType(aw.ax_addr);
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[1].drv.send_aw(aw);
                axi_master[1].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[1].drv.recv_b(b);

            //---PortA non-interleaved read---//
            //addr transfer
            ar = axi_master[1].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            map_type_r = getMapType(ar.ax_addr);
            bkgp_info = map2BankGroupSpace(aw.ax_addr);
            ar = aw;
            if (map_type_w == map_type_r) begin
                if (map_type_w == INTERLEAVE) begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, INTERLEAVE, tmp_addr);
                end else begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, NONE_INTER, tmp_addr);
                end
            end else begin
                if (map_type_w == INTERLEAVE) begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, NONE_INTER, tmp_addr);
                end else begin
                    ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, INTERLEAVE, tmp_addr);
                end
            end
                
            // $displayh("%p",ar);
            axi_master[1].drv.send_ar(ar);
            axi_master[1].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortB interleaved/non-interleaved write, PortB non-interleaved/interleaved read  %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end


        /// PortA interleaved write, PortB interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[0].add_memory_region(PORT1_INTERLEAVE_BASE, PORT1_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_INTERLEAVE_BASE, PORT2_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortA interleaved write---//
            aw = axi_master[0].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[0].drv.send_aw(aw);
                axi_master[0].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[0].drv.recv_b(b);

            //---PortB interleaved read---//
            //addr transfer
            ar = axi_master[1].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            tmp_addr[$clog2(L2_MEM_SIZE_IN_BYTE)-1:0] = aw_addr[$clog2(L2_MEM_SIZE_IN_BYTE)-1:0];
            ar = aw;
            ar.ax_addr = tmp_addr;
            axi_master[1].drv.send_ar(ar);
            axi_master[1].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortA interleaved write, PortB interleaved read %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end

        /// PortA non-interleaved write, PortB non-interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[0].add_memory_region(PORT1_NONE_INTER_BASE, PORT1_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_NONE_INTER_BASE, PORT2_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortA interleaved write---//
            aw = axi_master[0].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[0].drv.send_aw(aw);
                axi_master[0].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[0].drv.recv_b(b);

            //---PortB interleaved read---//
            //addr transfer
            ar = axi_master[1].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            tmp_addr[$clog2(L2_MEM_SIZE_IN_BYTE)-1:0] = aw_addr[$clog2(L2_MEM_SIZE_IN_BYTE)-1:0];
            ar = aw;
            ar.ax_addr = tmp_addr;
            axi_master[1].drv.send_ar(ar);
            axi_master[1].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortA non-interleaved write, PortB non-interleaved read %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end


        /// PortA interleaved write, PortB non-interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[0].add_memory_region(PORT1_INTERLEAVE_BASE, PORT1_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_NONE_INTER_BASE, PORT2_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortA interleaved write---//
            aw = axi_master[0].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[0].drv.send_aw(aw);
                axi_master[0].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[0].drv.recv_b(b);

            //---PortB non-interleaved read---//
            //addr transfer
            ar = axi_master[1].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            bkgp_info = map2BankGroupSpace(aw.ax_addr);
            ar = aw;
            ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, NONE_INTER, tmp_addr);
            // $displayh("%p",ar);
            axi_master[1].drv.send_ar(ar);
            axi_master[1].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortA interleaved write, PortB non-interleaved read %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end


        /// PortA non-interleaved write, PortB interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[0].add_memory_region(PORT1_NONE_INTER_BASE, PORT1_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_INTERLEAVE_BASE, PORT2_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortA non-interleaved write---//
            aw = axi_master[0].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[0].drv.send_aw(aw);
                axi_master[0].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[0].drv.recv_b(b);

            //---PortB interleaved read---//
            //addr transfer
            ar = axi_master[1].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            bkgp_info = map2BankGroupSpace(aw.ax_addr);
            ar = aw;
            ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, INTERLEAVE, tmp_addr);
            // $displayh("%p",ar);
            axi_master[1].drv.send_ar(ar);
            axi_master[1].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortA non-interleaved write, PortB interleaved read %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end


        /// PortB interleaved write, PortA non-interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[0].add_memory_region(PORT1_NONE_INTER_BASE, PORT1_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_INTERLEAVE_BASE, PORT2_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortB interleaved write---//
            aw = axi_master[1].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[1].drv.send_aw(aw);
                axi_master[1].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[1].drv.recv_b(b);

            //---PortA non-interleaved read---//
            //addr transfer
            ar = axi_master[0].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            bkgp_info = map2BankGroupSpace(aw.ax_addr);
            ar = aw;
            ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, NONE_INTER, tmp_addr);
            // $displayh("%p",ar);
            axi_master[0].drv.send_ar(ar);
            axi_master[0].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortB interleaved write, PortA non-interleaved read %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end


        /// PortB non-interleaved write, PortA interleaved read 
        init_axi_master();
        clear_all_master_mem_regions();
        axi_master[0].add_memory_region(PORT1_INTERLEAVE_BASE, PORT1_INTERLEAVE_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);
        axi_master[1].add_memory_region(PORT2_NONE_INTER_BASE, PORT2_NONE_INTER_BASE + L2_MEM_SIZE_IN_BYTE, axi_pkg::DEVICE_NONBUFFERABLE);

        for (int i = 0; i < num_test; i++) begin
            //---PortB non-interleaved write---//
            aw = axi_master[1].new_rand_burst(0);
            aw.ax_len = 0;
            aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
            aw.ax_atop = axi_pkg::ATOP_NONE;
            aw.ax_addr = (aw.ax_addr>>$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD))<<$clog2(NUM_BANK_PER_BANK_GROUP*BANK_WORD);
            aw_addr = aw.ax_addr;
            std::randomize(w);
            write_one_beat = w.w_data;
            w.w_last = 1;
            //write one beat 
            fork
                axi_master[1].drv.send_aw(aw);
                axi_master[1].drv.send_w(w);
            join
            // $displayh("%p",aw);
            //receive write response
            axi_master[1].drv.recv_b(b);

            //---PortA interleaved read---//
            //addr transfer
            ar = axi_master[0].new_rand_burst(1);
            tmp_addr = ar.ax_addr;
            bkgp_info = map2BankGroupSpace(aw.ax_addr);
            ar = aw;
            ar.ax_addr = bankGroupSpace2TcdmAddr(bkgp_info, INTERLEAVE, tmp_addr);
            // $displayh("%p",ar);
            axi_master[0].drv.send_ar(ar);
            axi_master[0].drv.recv_r(r);
            read_one_beat = r.r_data;
            $displayh("One beat test: PortB non-interleaved write, PortA interleaved read %d, %h -> %h",i, aw_addr, ar.ax_addr);
            //check results
            for (int j = 0; j < (AXI_DATA_WIDTH/8); j++) begin
                if (w.w_strb[j]) begin
                    if (write_one_beat[j] !== read_one_beat[j]) begin
                        $fatal(1,"Error on %0d byte, expect %h but get %h",j, write_one_beat[j], read_one_beat[j]);
                    end
                end
            end
        end
    endtask : double_port_one_beat_axi_write_read_test

    //behaviours
    initial begin
        @(posedge rst_n);
        // random_master_simulation();
        initL2();
        single_port_one_beat_axi_write_read_test(100);
        double_port_one_beat_axi_write_read_test(100);
        $display("**********------------**********---------**********----------**********");
        $display("ALL addr are mapped correctly!");
        $display("ALL data read/write correctly!");
        $display("Good job Dude!");
        
        $finish;
    end




endmodule
