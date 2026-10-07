// SPDX-License-Identifier: GPL-2.0-only
// Experimental demultiplexed core / level-controller BIU yield simulation.
// Both trace-comparison cores use macro ON; the reference ties yield inputs low.
// Macro OFF is checked by independent regression and port/config controls.
// Modeled transactions are not hardware or native NEC pin timing evidence.
module tb_biu_yield;
    logic clk = 0, reset = 1, bkd_load = 0;
    logic [223:0] bkd_regs = 0;
    logic pin_int = 0, pin_nmi = 0;
    logic [1:0] request=0;
    wire [1:0] external_grant=grant;
    wire [1:0] yield_ready;
    logic hold_ready = 0, owned_seen = 0, resumed = 0;
    int owned_edges = 0, acquisition_queue = 0, post_reads = 0, post_stores = 0;
    int owned_pops=0, owned_posts=0, owned_deliveries=0, owned_flushes=0;
    int split_read_first=0, split_read_second=0;
    int announced_bs=7, announced_addr=0, announced_completions=0;
    logic announced_watch=0;
    logic [19:0] posted_address, posted_address2;
    logic [2:0] posted_bs;
    logic posted_split;
    logic [223:0] stalled_regs;
    logic [36:0] stalled_eu;
    int stalled_pops, stalled_slot, stalled_rq;
    logic stalled_row_blocked;
    wire [1:0] grant;
    wire core_ce, core_half, bus_enable;
    wire [1:0] quiet, exclude, rd, ube, buslock;
    wire [19:0] addr [2];
    wire [15:0] data_o [2];
    logic [15:0] data_i [2];
    wire [3:0] status_o [2];
    wire [2:0] bs [2];
    wire [1:0] qs [2];
    wire [223:0] regs [2];
    wire [2:0] actual_phase [2];
    wire [2:0] actual_page [2];
    wire [5:0] actual_eu_state [2];
    logic [7:0] mem [2][65536];
    logic ready [2];
    int phase [2], waits_left [2], cycle_kind [2], cycle_addr [2];
    logic cycle_ube [2];
    int writes [2], intas [2], completions [2];
    logic [15:0] irq_saved_ip;
    logic irq_boundary_seen = 0;
    int wait_mode = 0, case_id = 0;
    wire [1:0] enables = 2'b11;
    v30_bus_ownership arb (
        .CLK(clk), .RESET(reset), .CE(1'b1), .CE_HALF(1'b0),
        .REQUEST(request), .CORE_QUIET(yield_ready[0]), .EXCLUDE(exclude[0]),
        .GRANT(grant), .CORE_CE(core_ce), .CORE_CE_HALF(core_half),
        .CORE_BUS_ENABLE(bus_enable)
    );
    for (genvar g = 0; g < 2; g++) begin : cores
        v30_core cpu (
            .CLK(clk), .CE(enables[g]), .RESET(reset), .READY(ready[g]),
            .INT(pin_int), .NMI(pin_nmi), .POLL_N(1'b1),
            .DATA_I(data_i[g]), .ADDR_O(addr[g]), .DATA_O(data_o[g]),
            .STATUS_O(status_o[g]), .QS(qs[g]), .BS(bs[g]),
            .RD_N(rd[g]), .UBE_N(ube[g]), .BUSLOCK_N(buslock[g]),
            .BUS_EXCLUDE(exclude[g]),
            .YIELD_PENDING(g==0 && |request), .BUS_OWNED(g==0 && !bus_enable),
            .YIELD_READY(yield_ready[g]), .SS_ADDR('0), .SS_WDATA('0),
            .SS_WE(1'b0), .SS_RDATA(), .SS_ERR(), .SS_BUS_QUIET(quiet[g]),
            .bkd_load(bkd_load), .bkd_regs(bkd_regs),
            .bkd_queue(case_id==9 ? 48'h020006fff090 : case_id==11 ? 48'hf4f402eb9090 : case_id==12 ? 48'h909090f49090 : case_id>=14 && case_id<=15 ? 48'h909090909050 : 48'h909090909090),
            .bkd_qlen((case_id>=9 && case_id<=12 || case_id>=14 && case_id<=15) ? 3'd6 : 3'd0),
            .bkd_fetch_ip((case_id>=9 && case_id<=12 || case_id>=14 && case_id<=15) ? 16'd6 : 16'd0), .scr_en(1'b0),
            .scr_qop('0), .dbg_regs(regs[g]), .dbg_first_pop(), .dbg_pend()
        );
        assign actual_phase[g] = cpu.u_biu.r_ts;
        assign actual_page[g] = cpu.u_eu.upc_page;
        assign actual_eu_state[g] = cpu.u_eu.st;
        always_comb begin
            ready[g] = !hold_ready && waits_left[g] == 0;
            data_i[g] = (g == 0 && !bus_enable) ? 16'h0000 : cycle_kind[g] == 0 ? 16'h0020 :
                {mem[g][{addr[g][15:1],1'b1}],mem[g][{addr[g][15:1],1'b0}]};
        end
    end
    // Separate public-port BIU fixture; not core/native reachability.
    logic u_reset=1,u_ce=0,u_pending=0,u_owned=0,u_exclude=0,u_mode=0;
    logic u_post=0,u_split=0,u_susp=0,u_vector=0,u_sswe=0;
    logic [2:0] u_kind=5;
    logic [19:0] u_address=20'h0200,u_address2=20'h0202;
    wire u_ready,u_rd_done;
    wire [2:0] u_bs;
    wire [19:0] u_addr;
    wire [15:0] u_rdata;
    v30u_biu unit_biu (
        .clk(clk),
        .ce(u_ce),
        .srst(u_reset),
        .yield_pending(u_pending),
        .bus_owned(u_owned),
        .yield_exclude(u_exclude),
        .yield_ready(u_ready),
        .bs(u_bs),
        .addr_o(u_addr),
        .data_o(),
        .status_o(),
        .ube_n(),
        .rd_n(),
        .qs(),
        .ad_i(u_kind==0 ? 16'h0020 : u_addr[15:0]==16'h0080 ? 16'h0100 :
              u_addr[15:0]==16'h0201 ? 16'h01a5 :
              (u_addr[15:0]==16'h0200 || u_addr[15:0]==16'h0202) ? 16'h5a00 : 16'h9090),
        .ready(1'b1),
        .psw_ie('0),
        .md8080(u_mode),
        .q_byte(),
        .q_ripe(),
        .q_ripe_lead_n(),
        .q_cnt_o(),
        .q_pop('0),
        .q_first('0),
        .q_flush('0),
        .flush_pre('0),
        .flush_rep('0),
        .flush_stage('0),
        .flush_pend('0),
        .flush_nmi('0),
        .flush_int_live('0),
        .flush_cs('0),
        .flush_cs_old('0),
        .flush_cs_we('0),
        .flush_ip('0),
        .eu_post(u_post),
        .eu_post_hold('0),
        .eu_halt_irq('0),
        .eu_vector_post(u_vector),
        .eu_bs(u_kind),
        .eu_addr(u_address),
        .eu_addr2(u_address2),
        .eu_split(u_split),
        .eu_seg('0),
        .eu_seg2('0),
        .eu_word(1'b1),
        .eu_slot_busy(),
        .eu_slot_busy_n(),
        .eu_access_active(),
        .eu_direct_fetch(),
        .eu_fetch_tail(),
        .eu_ghost_full(),
        .eu_ghost_idle(),
        .eu_ghost_stack_first(),
        .eu_ghost_row('0),
        .eu_ghost_acc('0),
        .eu_ghost_sp('0),
        .eu_ghost_bare('0),
        .eu_pair('0),
        .eu_pair2('0),
        .eu_wdata('0),
        .eu_rdata_n(u_rdata),
        .eu_rd_done_n(u_rd_done),
        .eu_rd_edge(),
        .eu_rd_edge_d(),
        .eu_wr_done_n(),
        .eu_wr_eval(),
        .eu_opr_free(),
        .eu_susp(u_susp),
        .eu_resume('0),
        .eu_halt('0),
        .eu_unhalt('0),
        .eu_unhalt_disp('0),
        .halted_o(),
        .eu_bnd_take('0),
        .eu_bnd_post('0),
        .bkd_load('0),
        .bkd_cs('0),
        .bkd_ip('0),
        .bkd_queue('0),
        .bkd_qlen('0),
        .ss_addr('0),
        .ss_wdata('0),
        .ss_we(u_sswe),
        .ss_rdata(),
        .ss_bus_quiet()
    );
    task automatic tick;
        logic [1:0] consume_wait;
        logic sampled_cpu_bus_enable, sampled_bus_enable, sampled_yield_ready, sampled_exclude;
        logic [1:0] sampled_grant;
        int commits_before;
        // Model T1/T2/T3/Tw/T4 from public BS and READY with CPU CE live.
        // Yield must inhibit launches while EU/queue/debts continue advancing.
        #1;
        consume_wait = 0;
        sampled_cpu_bus_enable = bus_enable; sampled_bus_enable = bus_enable;
        sampled_yield_ready=yield_ready[0]; sampled_exclude=exclude[0]; sampled_grant=grant;
        if(!reset && !bus_enable && (bs[0]!=7 || cores[0].cpu.u_biu.r_run || cores[0].cpu.u_biu.r_cmt_valid ||
            cores[0].cpu.u_biu.inta_preview || cores[0].cpu.u_biu.vector_follow_preview || cores[0].cpu.u_biu.flush_fast))
            $fatal(1,"pre-edge owned CPU announcement/preview");
        commits_before = completions[0];
        if(!reset && !bus_enable) begin
            if(cores[0].cpu.u_biu.pop_now) owned_pops++;
            if(cores[0].cpu.u_eu.eu_post) owned_posts++;
            if(cores[0].cpu.u_biu.done_fire) owned_deliveries++;
            if(cores[0].cpu.u_eu.q_flush) owned_flushes++;
        end
        if (!reset && (case_id==5 || case_id==10) && actual_eu_state[0]==32 && !irq_boundary_seen) begin
            irq_saved_ip=regs[0][192+:16]; irq_boundary_seen=1;
        end
        if (!reset && owned_seen && sampled_cpu_bus_enable) begin
            owned_seen = 0; resumed = 1;
        end
        for (int g = 0; g < 2; g++) begin
            if (reset) begin
                phase[g] = 0; waits_left[g] = 0;
                writes[g] = 0; intas[g] = 0; completions[g] = 0; cycle_kind[g] = 7;
            end else if (enables[g]) begin
                if (phase[g] == 0 || phase[g] == 5) begin
                    if (bs[g] != 7) begin
                        phase[g] = 1; cycle_kind[g] = int'(bs[g]);
                        cycle_addr[g] = int'(addr[g][15:0]);
                        cycle_ube[g] = ube[g];
                        waits_left[g] = wait_mode;

                    end else phase[g] = 0;
                end else if (phase[g] == 1 || phase[g] == 2) begin
                    // BS announces before T1; UBE_N can retain the previous
                    // cycle on a zero-age announcement. Capture lanes on the
                    // following real T1, not the announcement's stale value.
                    if (phase[g] == 1) begin
                        if (cycle_kind[g] == 6 && actual_phase[g] != 1)
                            $fatal(1,"write lane sample is not actual T1");
                        cycle_ube[g] = ube[g];
                    end
                    phase[g]++;
                end
                else if ((phase[g] == 3 || phase[g] == 4) && !ready[g]) begin
                    phase[g] = 4; consume_wait[g] = 1;
                end else begin
                    if ((cycle_kind[g]==0 || cycle_kind[g]==5) && !(actual_phase[g]==3 || actual_phase[g]==4))
                        $fatal(1,"completion phase mismatch modeled=%0d actual=%0d kind=%0d",phase[g],actual_phase[g],cycle_kind[g]);
                    if(g==0 && (case_id==5 || case_id==10) && completions[g]<24)
                        $display("IRQ transaction kind=%0d addr=%04x input=%04x output=%04x IP=%04x CS=%04x st=%0d",cycle_kind[g],cycle_addr[g],data_i[g],data_o[g],regs[g][192+:16],regs[g][144+:16],actual_eu_state[g]);
                    if(g==0 && announced_watch && cycle_kind[g]==announced_bs && cycle_addr[g]==announced_addr)
                        announced_completions++;
                    if(g==0 && cycle_kind[g]==5) begin
                        if(cycle_addr[g]==513) split_read_first++;
                        if(cycle_addr[g]==514) split_read_second++;
                    end
                    phase[g] = 5; completions[g]++;
                    if (cycle_kind[g] == 0) intas[g]++;
                    if (g == 0 && resumed && cycle_kind[g] == 5 && cycle_addr[g] == 1536)
                        post_reads++;
                    if (cycle_kind[g] == 6) begin
                        writes[g]++;
                        if (g == 0 && resumed && cycle_addr[g] == 1538 && data_o[g] == 16'h6a35)
                            post_stores++;
                        // Write data may arrive via the existing paired-store
                        // forwarding path after T1. Sample it at completion;
                        // address and lane selection remain the T1 ownerships.
                        if ((cycle_addr[g] & 1) != 0) begin
                            if (!cycle_ube[g]) mem[g][cycle_addr[g]] = data_o[g][15:8];
                        end else begin
                            mem[g][cycle_addr[g]] = data_o[g][7:0];
                            if (!cycle_ube[g]) mem[g][cycle_addr[g]+1] = data_o[g][15:8];
                        end
                    end
                end
            end
        end
        // The synthetic interrupt controller withdraws INT only after both
        // acknowledged transactions have completed.
        if (!reset && (case_id==5 || case_id==10) && intas[0]==2) pin_int=0;
        #1 clk = 1; #1 clk = 0;
        if (!reset && !sampled_bus_enable &&
            commits_before != completions[0])
            $fatal(1,"modeled CPU transaction committed while isolated");
        if (!reset && !sampled_bus_enable) begin
            owned_edges++;
            if (cores[0].cpu.u_biu.r_run || cores[0].cpu.u_biu.r_cmt_valid || bs[0]!=7)
                $fatal(1,"new CPU launch/announcement while externally owned");
        end
        if (!reset && (|grant) && sampled_grant==0) begin
            owned_seen=1; acquisition_queue=int'(cores[0].cpu.u_biu.r_q_cnt);
            if(!sampled_yield_ready) $fatal(1,"acquired without registered yield boundary");
            if(sampled_exclude) $fatal(1,"acquisition during exclusion");
            if ((case_id==1 && writes[0]<1) || (case_id==2 && writes[0]<2) ||
                (case_id==3 && (writes[0]<3 || regs[0][16+:16]!=0)) ||
                (case_id==5 && intas[0]!=2)) $fatal(1,"grant preceded protected completion");
        end
        for (int g = 0; g < 2; g++) if (consume_wait[g] && waits_left[g]>0) waits_left[g]--;
    endtask
    task automatic load_case(input int kind, input int waits);
        reset = 1; bkd_load = 1; pin_int = 0; pin_nmi = 0; request = 0;
        hold_ready = 0; owned_seen = 0; resumed = 0;
        owned_edges = 0; post_reads = 0; post_stores = 0; irq_boundary_seen=0;
        owned_pops=0; owned_posts=0; owned_deliveries=0; owned_flushes=0; announced_watch=0; announced_completions=0; split_read_first=0; split_read_second=0;
        case_id = kind; wait_mode = waits;
        bkd_regs = 0;
        bkd_regs[0 +: 16] = 16'h1234;
        bkd_regs[16 +: 16] = (kind == 6 || kind==13) ? 1 : 3;
        bkd_regs[64 +: 16] = kind==15 ? 16'h0801 : 16'h0800;
        bkd_regs[96 +: 16] = 16'h0300;
        bkd_regs[112 +: 16] = 16'h0400;
        bkd_regs[208 +: 16] = (kind == 5 || kind == 10) ? 16'h0202 : 16'h0002;
        for (int g = 0; g < 2; g++) begin
            for (int i = 0; i < 65536; i++) mem[g][i] = 8'h90;
            // All interrupt vectors used here point to 0000:0100.
            mem[g][8] = 0; mem[g][9] = 1; mem[g][10] = 0; mem[g][11] = 0;
            mem[g][128] = 0; mem[g][129] = 1; mem[g][130] = 0; mem[g][131] = 0;
            mem[g][256] = 8'h90; mem[g][257] = 8'h26;
            mem[g][258] = 8'h90; mem[g][259] = 8'hf4;
            mem[g][512] = 1; mem[g][513] = 0; mem[g][514] = 0;
            mem[g][768] = 8'h11; mem[g][769] = 8'h11;
            mem[g][770] = 8'h22; mem[g][771] = 8'h22;
            mem[g][772] = 8'h33; mem[g][773] = 8'h33;
            if (kind == 2) begin
                mem[g][512] = 8'ha5; mem[g][513] = 1;
                mem[g][514] = 0; mem[g][515] = 8'h5a;
            end
            mem[g][1536] = 8'h11; mem[g][1537] = 8'h11;
            if(kind==14 || kind==15) begin
                mem[g][0]=8'h50; mem[g][6]=8'hf4;
                mem[g][2046]=8'ha5; mem[g][2049]=8'h5a;
            end else if(kind==13) begin
                mem[g][0]=8'hf7; mem[g][1]=8'hf1; mem[g][2]=8'heb; mem[g][3]=8'hfc;
            end else if(kind==7 || kind==8) begin
                mem[g][0]=kind==7 ? 8'hff : 8'h8b; mem[g][1]=8'h06;
                mem[g][2]=1; mem[g][3]=2; mem[g][4]=8'hf4;
                mem[g][512]=8'ha5; mem[g][513]=1; mem[g][514]=0; mem[g][515]=8'h5a;
            end else if(kind==9 || kind==10 || kind==11) begin
                // Front-loaded register-only work demonstrates live EU pops.
                for(int j=0;j<8;j++) mem[g][j]=8'h90;
                if(kind==9) begin
                    mem[g][0]=8'h90; mem[g][1]=8'hf0; mem[g][2]=8'hff; mem[g][3]=8'h06;
                    mem[g][4]=0; mem[g][5]=2; mem[g][6]=8'hf4;
                end else if(kind==11) begin
                    mem[g][2]=8'heb; mem[g][3]=8'h02;
                    mem[g][4]=8'hf4; mem[g][5]=8'hf4; mem[g][6]=8'h90; mem[g][7]=8'hf4;
                end else mem[g][8]=8'hf4;
            end else if (kind == 6) begin
                mem[g][0]=8'ha1; mem[g][1]=0; mem[g][2]=6;
                mem[g][3]=8'ha3; mem[g][4]=2; mem[g][5]=6;
                mem[g][6]=8'hf7; mem[g][7]=8'hf1;
                mem[g][8]=8'heb; mem[g][9]=8'hf6;
            end else if (kind == 0) begin
                mem[g][0] = 8'hff; mem[g][1] = 8'h06;
                mem[g][2] = 0; mem[g][3] = 2; mem[g][4] = 8'hf4;
            end else if (kind == 1 || kind == 2) begin
                mem[g][0] = 8'hf0; mem[g][1] = 8'hff; mem[g][2] = 8'h06;
                mem[g][3] = kind == 2 ? 1 : 0; mem[g][4] = 2;
                mem[g][5] = 8'h90; mem[g][6] = 8'h26;
                mem[g][7] = 8'h90; mem[g][8] = 8'hf4;
            end else if (kind == 3) begin
                mem[g][0] = 8'hf0; mem[g][1] = 8'hf3;
                mem[g][2] = 8'ha5; mem[g][3] = 8'h90; mem[g][4] = 8'hf4;
            end else if (kind == 4) begin
                mem[g][0] = 8'hf0; mem[g][1] = 8'hf4;
            end else begin
                mem[g][0] = 8'h90; mem[g][1] = 8'h90; mem[g][2] = 8'hf4;
            end
        end
        repeat (4) tick(); reset = 0; bkd_load = 0;
    endtask

    task automatic compare_raw;
        if (regs[0] !== regs[1] ||
            {addr[0],data_o[0],status_o[0],bs[0],qs[0],rd[0],ube[0],buslock[0]} !==
            {addr[1],data_o[1],status_o[1],bs[1],qs[1],rd[1],ube[1],buslock[1]})
            $fatal(1,"raw/chained mismatch case=%0d waits=%0d",case_id,wait_mode);
    endtask
    task automatic no_request_control(input int kind,input int waits);
        load_case(kind,waits);
        for(int n=0;n<200;n++) begin
            if(kind==5 && n==30) pin_int=1;
            tick(); compare_raw();
        end
    endtask
    task automatic pulse(input logic [1:0] channel);
        request=channel; tick();
    endtask
    task automatic wait_external(input logic [1:0] channel,input int limit=4096);
        int n;
        n=0;
        while(external_grant!=channel && n<limit) begin tick(); n++; end
        if(external_grant!=channel) $fatal(1,"level ownership watchdog case=%0d",case_id);
    endtask
    task automatic return_pulse(input logic [1:0] channel);
        request=0; tick(); tick();
    endtask
    task automatic wait_cpu;
        int n;
        n=0;
        while(!resumed && n<4096) begin tick(); n++; end
        if(!resumed) $fatal(1,"CPU return watchdog");
    endtask
    task automatic check_result;
        if(case_id==1 && {mem[0][513],mem[0][512]}!=16'h0002)
            $fatal(1,"even RMW literal mismatch");
        if(case_id==2 && ({mem[0][514],mem[0][513]}!=16'h0002 ||
            mem[0][512]!=8'ha5 || mem[0][515]!=8'h5a || writes[0]<2))
            $fatal(1,"odd split literal/neighbor mismatch");
        if(case_id==3 && (regs[0][16+:16]!=0 ||
            {mem[0][1025],mem[0][1024]}!=16'h1111 ||
            {mem[0][1027],mem[0][1026]}!=16'h2222 ||
            {mem[0][1029],mem[0][1028]}!=16'h3333))
            $fatal(1,"REP literal mismatch");
        if((case_id==5 || case_id==10) && (intas[0]!=2 || regs[0][64+:16]!=16'h07fa ||
            regs[0][144+:16]!=0 || regs[0][192+:16]!=16'h0104 || !irq_boundary_seen ||
            {mem[0][2047],mem[0][2046]}!=16'hf202 ||
            {mem[0][2045],mem[0][2044]}!=16'h0000 ||
            {mem[0][2043],mem[0][2042]}!=irq_saved_ip))
            $fatal(1,"IRQ vector/frame/handler mismatch");
    endtask
    task automatic unit_reset;
        reset=1; request=0; u_reset=1; u_ce=1; u_pending=0; u_owned=0;
        u_post=0; u_split=0; u_susp=0; u_vector=0; u_exclude=0; u_mode=0; u_sswe=0;
        repeat(4) tick(); u_reset=0;
    endtask
    task automatic unit_edge;
        #1;
        if(!u_reset && u_owned && (unit_biu.r_run || unit_biu.r_cmt_valid || u_bs!=7 ||
            unit_biu.inta_preview || unit_biu.vector_follow_preview || unit_biu.flush_fast))
            $fatal(1,"pre-edge unit owned launch/preview");
        tick();
        if(u_owned && (unit_biu.r_run || unit_biu.r_cmt_valid || u_bs!=7))
            $fatal(1,"unit owned launch/preview");
    endtask
    int profiles=0, tw_clocks, n, kind, gaps, unit_deliveries, unit_cycles;
    initial begin
        if($test$plusargs("bad_owned_mode")) begin
            unit_reset(); u_mode=1; u_owned=1; tick();
            $fatal(1,"missing owned-mode diagnostic");
        end
        if($test$plusargs("bad_ss_arbitration")) begin
            unit_reset(); u_pending=1; u_sswe=1; tick();
            $fatal(1,"missing SS arbitration diagnostic");
        end
        for(int w=0;w<3;w++) for(int c=0;c<4;c++) begin
            kind=c==3?5:c+1;
            no_request_control(kind,w==2?3:w);
            load_case(kind,w==2?3:w);
            n=0;
            while(!exclude[0] && n<4096) begin
                if(kind==5 && n==30) pin_int=1;
                tick(); n++;
            end
            if(!exclude[0]) $fatal(1,"real exclusion not reached");
            pulse(1);
            gaps=0; n=0;
            while(external_grant!=1 && n<4096) begin
                if(kind==5 && intas[0]==1 && bs[0]==7) begin
                    gaps++; if(!exclude[0]) $fatal(1,"IRQ acknowledge gap lost exclusion");
                end
                tick(); n++;
            end
            if(external_grant!=1) $fatal(1,"protected ownership watchdog");
            repeat(32) tick();
            if(owned_edges<32) $fatal(1,"protected ownership bar missed");
            return_pulse(1); wait_cpu();
            n=0;
            while(actual_eu_state[0]!=30 && n<4096) begin tick(); n++; end
            if(actual_eu_state[0]!=30) $fatal(1,"terminal HALT watchdog state=%0d IP=%04x CS=%04x PSW=%04x INTA=%0d frame=%04x/%04x/%04x",actual_eu_state[0],regs[0][192+:16],regs[0][144+:16],regs[0][208+:16],intas[0],{mem[0][2047],mem[0][2046]},{mem[0][2045],mem[0][2044]},{mem[0][2043],mem[0][2042]});
            check_result();
            if(kind==5 && gaps==0) $fatal(1,"IRQ gap coverage absent");
            profiles++;
            $display("PASS biu-yield protected kind=%0d waits=%0d owned=%0d gap=%0d",kind,wait_mode,owned_edges,gaps);
        end
        // Retained requests in real Tw; priority and continuous ownership.
        no_request_control(6,0); load_case(6,0);
        n=0;
        while(!(cycle_kind[0]==5 && cycle_addr[0]==1536 && !rd[0]) && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"MEMR wait setup watchdog");
        hold_ready=1; request=3; tw_clocks=0; n=0;
        while(tw_clocks<16 && n<4096) begin
            if(actual_phase[0]==4 && !ready[0]) tw_clocks++;
            if(|grant) $fatal(1,"grant in actual Tw");
            tick(); n++;
        end
        if(tw_clocks!=16) $fatal(1,"sixteen actual Tw clocks absent");
        hold_ready=0; wait_external(1);
        repeat(128) tick();
        if(owned_edges<32) $fatal(1,"READY owned interval absent");
        request=2; n=0;
        while(grant!=2 && n<4096) begin
            #1; if(bus_enable || resumed) $fatal(1,"CPU bus resumed between queued owners");
            tick(); n++;
        end
        if(grant!=2 || resumed) $fatal(1,"queued ownership watchdog/isolation");
        repeat(32) tick();
        request=0; tick(); tick(); wait_cpu();
        n=0;
        while(post_reads<1 && n<4096) begin tick(); n++; end
        if(post_reads<1) $fatal(1,"retained real memory access did not resume");
        profiles++; $display("PASS yield READY priority Tw=%0d queue=%0d owned=%0d pops=%0d posts=%0d debts=%0d",tw_clocks,acquisition_queue,owned_edges,owned_pops,owned_posts,owned_deliveries);

        // Natural DIV loop fills the prefetch queue without request pressure.
        no_request_control(13,0); load_case(13,0); n=0;
        while(cores[0].cpu.u_biu.r_q_cnt!=6 && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"natural full queue not reached");
        request=1; wait_external(1); repeat(128) tick();
        if(acquisition_queue!=6 || owned_pops<2) $fatal(1,"full acquisition/live queue consumption absent");
        return_pulse(1); wait_cpu(); profiles++;
        $display("PASS yield natural full queue=%0d owned pops=%0d",acquisition_queue,owned_pops);

        // A split already started must drain both halves before acquisition.
        for(int splitcase=7;splitcase<=8;splitcase++) for(int w=0;w<3;w++) begin
            load_case(splitcase,w==2?3:w); n=0;
            while(!(cores[0].cpu.u_biu.r_run && !cores[0].cpu.u_biu.r_cur_rd_last &&
                    ((splitcase==7 && cores[0].cpu.u_biu.r_cur_wr) ||
                     (splitcase==8 && !cores[0].cpu.u_biu.r_cur_wr))) && n<4096) begin tick(); n++; end
            if(n==4096) $fatal(1,"started split coverage absent");
            request=1; wait_external(1);
            if(cores[0].cpu.u_biu.yield_split_started) $fatal(1,"grant between split partners");
            if((splitcase==7 && (writes[0]!=2 || {mem[0][514],mem[0][513]}!=16'h0002 ||
                mem[0][512]!=8'ha5 || mem[0][515]!=8'h5a)) ||
                (splitcase==8 && (split_read_first!=1 || split_read_second!=1)))
                $fatal(1,"public completion witness missing before split grant");
            repeat(32) tick(); return_pulse(1); wait_cpu();
            n=0; while(actual_eu_state[0]!=30 && n<4096) begin tick(); n++; end
            if(n==4096) $fatal(1,"split HALT watchdog");
            if(mem[0][512]!=8'ha5 || mem[0][515]!=8'h5a ||
               (splitcase==7 && ({mem[0][514],mem[0][513]}!=2 || writes[0]!=2)) ||
               (splitcase==8 && regs[0][0+:16]!=1)) $fatal(1,"split literal/neighbor failure");
            profiles++; $display("PASS yield started split kind=%0d waits=%0d pregrant_writeparts=%0d readparts=%0d/%0d",splitcase,wait_mode,writes[0],split_read_first,split_read_second);
        end

        // Acquire before later LOCK / IRQ / branch: EU runs while bus waits.
        for(int livecase=9;livecase<=11;livecase++) begin
            load_case(livecase,0);
            request=1; wait_external(1); if(livecase==10) pin_int=1;
            repeat(128) tick();
            if(owned_pops<2) $fatal(1,"live EU two-pop bar missed kind=%0d pops=%0d",livecase,owned_pops);
            if(livecase==9 && (!exclude[0] || owned_posts<1 || !cores[0].cpu.u_biu.r_slot_busy || cores[0].cpu.u_biu.r_rq_n==0)) $fatal(1,"late LOCK exclusion/post coverage absent");
            if(livecase==9) begin
                stalled_regs=regs[0]; stalled_pops=owned_pops;
                stalled_slot=int'(cores[0].cpu.u_biu.r_slot_busy); stalled_rq=int'(cores[0].cpu.u_biu.r_rq_n);
                stalled_row_blocked=cores[0].cpu.u_eu.row_blocked;
                stalled_eu={cores[0].cpu.u_eu.st,cores[0].cpu.u_eu.upc_page,
                    cores[0].cpu.u_eu.upc_opc,cores[0].cpu.u_eu.upc_loc,cores[0].cpu.u_eu.rloop_n};
                repeat(16) begin
                    tick();
                    if(regs[0]!==stalled_regs || owned_pops!=stalled_pops ||
                       {cores[0].cpu.u_eu.st,cores[0].cpu.u_eu.upc_page,
                        cores[0].cpu.u_eu.upc_opc,cores[0].cpu.u_eu.upc_loc,cores[0].cpu.u_eu.rloop_n}!==stalled_eu)
                        $fatal(1,"retained-access natural EU stall absent");
                end
            end
            if(livecase==10 && (!exclude[0] || owned_posts<1 || intas[0]!=0)) $fatal(1,"late IRQ exclusion/post coverage absent");
            if(livecase==11 && owned_flushes<1) $fatal(1,"owned branch flush absent");
            return_pulse(1); wait_cpu();
            n=0; while(actual_eu_state[0]!=30 && n<4096) begin tick(); n++; end
            if(n==4096) $fatal(1,"live EU HALT watchdog");
            if(livecase==9 && {mem[0][513],mem[0][512]}!=2) $fatal(1,"late LOCK result");
            if(livecase==10) check_result();
            if(livecase==11 && regs[0][192+:16]!=8) $fatal(1,"branch target literal");
            profiles++; $display("PASS yield live EU kind=%0d pops=%0d posts=%0d flush=%0d",livecase,owned_pops,owned_posts,owned_flushes);
            if(livecase==9) $display("PASS yield natural stall st=%0d upc=%0d/%02x/%0d slot=%0d rq=%0d row_blocked=%0d stable=16",stalled_eu[36:31],stalled_eu[30:28],stalled_eu[27:20],stalled_eu[19:16],stalled_slot,stalled_rq,stalled_row_blocked);
        end
        // Real EU post and real controller acquisition share an eligible edge.
        for(int postcase=14;postcase<=15;postcase++) begin
            load_case(postcase,0); n=0;
            while(!(yield_ready[0] && !exclude[0] && cores[0].cpu.u_eu.eu_post) && n<4096) begin tick(); n++; end
            if(n==4096) $fatal(1,"actual EU acquisition/post coincidence absent kind=%0d",postcase);
            posted_address=cores[0].cpu.u_eu.eu_addr;
            posted_address2=cores[0].cpu.u_eu.eu_addr2;
            posted_bs=cores[0].cpu.u_eu.eu_bs;
            posted_split=cores[0].cpu.u_eu.eu_split;
            if(posted_bs!=6 || posted_split!=(postcase==15)) $fatal(1,"actual post payload class");
            request=1; tick();
            if(grant!=1 || cores[0].cpu.u_biu.r_rq_n!=(postcase==15?2:1) ||
                cores[0].cpu.u_biu.r_rq_addr[0]!=posted_address ||
                cores[0].cpu.u_biu.r_rq_bs[0]!=posted_bs ||
                (posted_split && cores[0].cpu.u_biu.r_rq_addr[1]!=posted_address2))
                $fatal(1,"actual acquisition-edge EU payload lost");
            repeat(32) tick();
            if(writes[0]!=0) $fatal(1,"acquisition post launched while owned");
            return_pulse(1); wait_cpu(); n=0;
            while(actual_eu_state[0]!=30 && n<4096) begin tick(); n++; end
            if(n==4096 || writes[0]!=(postcase==15?2:1) ||
                (postcase==14 && {mem[0][2047],mem[0][2046]}!=16'h1234) ||
                (postcase==15 && ({mem[0][2048],mem[0][2047]}!=16'h1234 ||
                 mem[0][2046]!=8'ha5 || mem[0][2049]!=8'h5a)))
                $fatal(1,"actual acquisition post literal/unique write/neighbor");
            profiles++; $display("PASS yield actual EU post acquisition kind=%0d split=%0d addr=%05x writes=%0d",postcase,posted_split,posted_address,writes[0]);
        end

        // An existing CODE announcement is allowed to reach physical completion.
        load_case(6,0); n=0;
        while(!(cores[0].cpu.u_biu.r_cmt_valid && !cores[0].cpu.u_biu.r_run) && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"announced commitment coverage absent");
        announced_bs=int'(cores[0].cpu.u_biu.r_cmt_bs);
        announced_addr=int'(cores[0].cpu.u_biu.r_cmt_addr[15:0]); announced_watch=1;
        request=1; wait_external(1);
        if(announced_completions!=1) $fatal(1,"announced cycle did not drain");
        repeat(32) tick(); return_pulse(1); wait_cpu();
        profiles++; $display("PASS yield actual announced cycle drained");

        // A HALT decode while owned retains its separate status commitment.
        load_case(12,0); request=1; wait_external(1); repeat(128) tick();
        if(actual_eu_state[0]!=30 || !cores[0].cpu.u_biu.r_halt_pending || cores[0].cpu.u_biu.r_cmt_valid)
            $fatal(1,"pending HALT status coverage absent");
        return_pulse(1); wait_cpu(); n=0;
        while(cores[0].cpu.u_biu.r_halt_pending && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"pending HALT did not resume");
        profiles++; $display("PASS yield actual pending HALT retained and resumed");

        // RESET witnesses: real Tw drain, owned, and release/resume boundary.
        load_case(6,0); n=0;
        while(!(cores[0].cpu.u_biu.r_run && actual_phase[0]==3) && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"reset drain setup");
        hold_ready=1; request=1; tick();
        if(actual_phase[0]!=4 || grant!=0) $fatal(1,"reset Tw phase absent");
        reset=1; tick(); if(grant!=0 || !bus_enable || cores[0].cpu.u_biu.r_run) $fatal(1,"reset drain");
        load_case(9,0); request=1; wait_external(1);
        if(grant!=1) $fatal(1,"reset owned phase absent");
        reset=1; tick(); if(grant!=0 || !bus_enable || cores[0].cpu.u_biu.r_run) $fatal(1,"reset owned");
        load_case(9,0); request=1; wait_external(1); request=0; tick();
        if(grant!=0 || !bus_enable || resumed) $fatal(1,"reset release phase absent");
        reset=1; tick(); if(grant!=0 || !bus_enable || cores[0].cpu.u_biu.r_run) $fatal(1,"reset resume");
        profiles++; $display("PASS yield actual RESET drain owned release");

        // Build INTA debt through CODE-T4 replacement, public ports only.
        for(int vector_case=0;vector_case<2;vector_case++) begin
        unit_reset(); n=0;
        while(!(unit_biu.r_run && unit_biu.r_cur_fetch && unit_biu.r_ts==5 &&
                unit_biu.r_cmt_valid && unit_biu.r_cmt_fetch) && n<4096) begin unit_edge(); n++; end
        if(n==4096) $fatal(1,"unit CODE T4 replacement setup absent");
        u_kind=0; u_post=1; u_susp=1; #1;
        if(!unit_biu.inta_tail_replace) $fatal(1,"raw tail-replacement absent");
        unit_edge(); u_post=0; n=0;
        while(!unit_biu.r_rd_was_split && n<4096) begin unit_edge(); n++; end
        if(n==4096) $fatal(1,"public INTA debt creation absent");
        u_pending=1;
        n=0; while(!u_ready && n<4096) begin unit_edge(); n++; end
        if(n==4096 || !unit_biu.r_rd_was_split) $fatal(1,"debt did not reach unit yield boundary");
        u_owned=1; unit_edge(); u_kind=vector_case!=0 ? 5 : 0; u_address=20'h0080; u_vector=vector_case!=0; u_post=1; #1;
        if((vector_case==0 && (!unit_biu.inta_follow_preview || unit_biu.inta_preview)) ||
           (vector_case!=0 && (!unit_biu.vector_follow_intent || unit_biu.vector_follow_preview)) || u_bs!=7)
            $fatal(1,"raw1/eligible0 INTA bar absent");
        unit_edge(); u_post=0; u_vector=0;
        if(unit_biu.r_rd_was_split || unit_biu.r_rq_n!=1 ||
           (vector_case!=0 && unit_biu.r_rq_addr[0]!=20'h0080)) $fatal(1,"raw debt clear/retained post/address absent");
        repeat(32) unit_edge();
        u_owned=0; u_pending=0; unit_deliveries=0; unit_cycles=0;
        repeat(64) begin
            if(u_rd_done) begin unit_deliveries++; if(u_rdata!=(vector_case!=0?16'h0100:16'h0020)) $fatal(1,"unit INTA composition"); end
            if(unit_biu.r_run && (unit_biu.r_ts==3 || unit_biu.r_ts==4)) begin
                unit_cycles++;
                if(vector_case!=0 && u_addr!=20'h0080) $fatal(1,"unit vector completion address");
            end
            unit_edge();
        end
        if(unit_deliveries!=1 || unit_cycles!=1 || unit_biu.r_rq_n!=0) $fatal(1,"unit follow delivery not unique");
        $display("PASS yield unit conservation IRQ vector=%0d: public creation raw1 eligible0 clear, addr=%05x one delivery",vector_case,u_address);
        end

        // Same acquisition edge accepts a full EU payload, including queued split.
        for(int split=0;split<2;split++) begin
            unit_reset(); u_susp=1; u_pending=1; #1;
            if(!u_ready || unit_biu.r_run || unit_biu.r_cmt_valid) $fatal(1,"fixture acquisition boundary absent");
            u_owned=1;
            u_kind=5; u_address=split!=0 ? 20'h0201 : 20'h0200; u_address2=20'h0202;
            u_split=split!=0; u_post=1; unit_edge(); u_post=0;
            if(unit_biu.r_rq_n!=(split!=0?2:1)) $fatal(1,"unit acquisition post lost");
            repeat(32) unit_edge();
            u_owned=0; u_pending=0; unit_deliveries=0; unit_cycles=0;
            repeat(64) begin
                if(u_rd_done) begin
                    unit_deliveries++;
                    if(u_rdata!=(split!=0?16'h0001:16'h5a00)) $fatal(1,"unit posted read literal");
                end
                if(unit_biu.r_run && (unit_biu.r_ts==3 || unit_biu.r_ts==4)) unit_cycles++;
                unit_edge();
            end
            if(unit_deliveries!=1 || unit_cycles!=(split!=0?2:1) || unit_biu.r_rq_n!=0)
                $fatal(1,"unit queued access not unique");
            $display("PASS yield unit conservation acquisition post split=%0d one delivery",split);
        end

        // Public read creates a remaining delivery debt at the idle boundary.
        unit_reset(); u_susp=1; u_kind=5; u_address=20'h0200; u_post=1;
        unit_edge(); u_post=0; u_pending=1; n=0;
        while(!u_ready && n<4096) begin unit_edge(); n++; end
        if(n==4096 || !u_rd_done) $fatal(1,"public completion debt at boundary absent");
        u_owned=1; unit_deliveries=0;
        repeat(32) begin if(u_rd_done) unit_deliveries++; unit_edge(); end
        if(unit_deliveries!=1) $fatal(1,"owned completion debt not unique");
        $display("PASS yield unit conservation public read debt delivered once owned");

        unit_reset(); u_mode=1; u_pending=1; repeat(16) unit_edge();
        if(u_ready || unit_biu.yield_inhibit || !(unit_biu.r_run || unit_biu.r_cmt_valid || unit_biu.r_q_cnt!=0))
            $fatal(1,"8080 pending-only behavior changed");
        $display("PASS yield unit 8080 pending inert");
        u_mode=0; u_pending=0;
        if(profiles!=28) $fatal(1,"core profile count bar missed: %0d",profiles);
        $display("PASS experimental BIU yield actual core profiles=%0d plus six separate BIU fixtures",profiles);
        $finish;
    end
endmodule
