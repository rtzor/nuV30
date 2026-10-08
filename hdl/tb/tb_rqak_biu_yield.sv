// SPDX-License-Identifier: GPL-2.0-only
// Actual demultiplexed core/frontend/level-adapter simulation.
// Modeled transactions are not hardware or native NEC pin timing evidence.
module tb_rqak_biu_yield;
    logic clk = 0, reset = 1, bkd_load = 0;
    logic [223:0] bkd_regs = 0;
    logic pin_int = 0, pin_nmi = 0;
    logic [1:0] remote_low = 0;
    wire [1:0] request, drive_low, external_grant, protocol_error;
    wire [1:0] resolved_n = ~(remote_low | drive_low);
    v30_rqak_frontend frontend (
        .CLK(clk), .RESET(reset), .CE(1'b1), .RQAK_I_N(resolved_n),
        .INTERNAL_GRANT(grant), .REQUEST(request), .RQAK_DRIVE_LOW(drive_low),
        .EXTERNAL_GRANT(external_grant), .PROTOCOL_ERROR(protocol_error)
    );
    logic hold_ready=0, owned_seen=0, resumed=0, continuous_isolation=0;
    wire [1:0] yield_ready;
    int owned_edges=0, acquisition_queue=0, post_reads=0, post_stores=0;
    int external_edges[2], external_pops=0, split_read_first=0, split_read_second=0;
    int reset_peer_attempts=0;
    logic stale_accepted;
    logic [15:0] reset_saved_word;
    wire peer_permission = !reset && (|external_grant) && !bus_enable;
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
            .bkd_load(bkd_load), .bkd_regs(bkd_regs), .bkd_queue('0),
            .bkd_qlen('0), .bkd_fetch_ip('0), .scr_en(1'b0),
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
    task automatic reject_cpu_activity;
        if(bs[0]!=7 || cores[0].cpu.u_biu.r_run || cores[0].cpu.u_biu.r_cmt_valid ||
           cores[0].cpu.u_biu.inta_preview || cores[0].cpu.u_biu.vector_follow_preview ||
           cores[0].cpu.u_biu.flush_fast)
            $fatal(1,"isolated CPU announcement/physical preview case=%0d",case_id);
    endtask
    task automatic tick;
        logic [1:0] consume_wait, sampled_grant, sampled_external, sampled_drive, sampled_request;
        logic sampled_bus_enable, sampled_ready, sampled_exclude;
        int commits_before;
        #1;
        consume_wait=0; sampled_bus_enable=bus_enable; sampled_grant=grant;
        sampled_external=external_grant; sampled_drive=drive_low; sampled_request=request;
        sampled_ready=yield_ready[0]; sampled_exclude=exclude[0];
        commits_before=completions[0];
        if(enables!=2'b11) $fatal(1,"core CE is not live");
        if(!reset && !bus_enable) reject_cpu_activity();
        if(!reset && (|grant) && bus_enable) $fatal(1,"internal owner/ACK/return gap lost isolation");
        if(!reset && continuous_isolation && bus_enable)
            $fatal(1,"bus isolation broken between queued owners/ACK/gaps");
        if(!reset && owned_seen && sampled_bus_enable) begin owned_seen=0; resumed=1; end
        if(!reset && (|sampled_external)) begin
            if(cores[0].cpu.u_biu.pop_now) external_pops++;
            for(int c=0;c<2;c++) if(sampled_external[c]) external_edges[c]++;
        end
        if(!reset && case_id==5 && actual_eu_state[0]==32 && !irq_boundary_seen) begin
            irq_saved_ip=regs[0][192+:16]; irq_boundary_seen=1;
        end
        // Transaction phase is derived from public BS/READY. Registered BIU
        // phase corroborates T1/complete; bus permission gates the model.
        for(int g=0;g<2;g++) begin
            if(reset) begin
                phase[g]=0; waits_left[g]=0; writes[g]=0; intas[g]=0;
                completions[g]=0; cycle_kind[g]=7;
            end else if(enables[g] && (g!=0 || bus_enable)) begin
                if(phase[g]==0 || phase[g]==5) begin
                    if(bs[g]!=7) begin
                        phase[g]=1; cycle_kind[g]=int'(bs[g]); cycle_addr[g]=int'(addr[g][15:0]);
                        cycle_ube[g]=ube[g]; waits_left[g]=wait_mode;
                    end else phase[g]=0;
                end else if(phase[g]==1 || phase[g]==2) begin
                    if(phase[g]==1) begin
                        if(cycle_kind[g]==6 && actual_phase[g]!=1) $fatal(1,"write lane sample is not T1");
                        cycle_ube[g]=ube[g];
                    end
                    phase[g]++;
                end else if((phase[g]==3 || phase[g]==4) && !ready[g]) begin
                    phase[g]=4; consume_wait[g]=1;
                end else begin
                    if((cycle_kind[g]==0 || cycle_kind[g]==5) && !(actual_phase[g]==3 || actual_phase[g]==4))
                        $fatal(1,"public completion phase mismatch");
                    phase[g]=5; completions[g]++;
                    if(cycle_kind[g]==0) intas[g]++;
                    if(g==0 && cycle_kind[g]==5) begin
                        if(cycle_addr[g]==513) split_read_first++;
                        if(cycle_addr[g]==514) split_read_second++;
                        if(resumed && cycle_addr[g]==1536) post_reads++;
                    end
                    if(cycle_kind[g]==6) begin
                        writes[g]++;
                        if(g==0 && resumed && cycle_addr[g]==1538 && data_o[g]==16'h6a35) post_stores++;
                        if((cycle_addr[g]&1)!=0) begin
                            if(!cycle_ube[g]) mem[g][cycle_addr[g]]=data_o[g][15:8];
                        end else begin
                            mem[g][cycle_addr[g]]=data_o[g][7:0];
                            if(!cycle_ube[g]) mem[g][cycle_addr[g]+1]=data_o[g][15:8];
                        end
                    end
                end
            end
        end
        if(!reset && case_id==5 && intas[0]==2) pin_int=0;
        #1 clk=1; #1 clk=0;
        if(!reset && !sampled_bus_enable) begin
            owned_edges++;
            if(commits_before!=completions[0]) $fatal(1,"modeled CPU completion while isolated");
            // Release edge is also inhibited by pre-edge BUS_OWNED.
            reject_cpu_activity();
        end
        if(!reset && !bus_enable) reject_cpu_activity();
        if(!reset && (|grant) && bus_enable) $fatal(1,"internal owner/ACK/return gap lost isolation");
        if(!reset && (|grant) && sampled_grant==0) begin
            owned_seen=1; acquisition_queue=int'(cores[0].cpu.u_biu.r_q_cnt);
            if(!sampled_ready || sampled_exclude) $fatal(1,"acquired without eligible boundary");
            if((case_id==1 && writes[0]<1) || (case_id==2 && writes[0]<2) ||
               (case_id==3 && (writes[0]<3 || regs[0][16+:16]!=0)) ||
               (case_id==5 && intas[0]!=2)) $fatal(1,"grant preceded protected work");
            if(case_id==7 && (writes[0]!=2 || {mem[0][514],mem[0][513]}!=16'h0002 ||
               mem[0][512]!=8'ha5 || mem[0][515]!=8'h5a)) $fatal(1,"grant preceded split write partners");
            if(case_id==8 && (split_read_first!=1 || split_read_second!=1))
                $fatal(1,"grant preceded split read partners");
        end
        if(!reset) begin
            if(grant==3 || external_grant==3) $fatal(1,"non-onehot grant");
            if((external_grant & grant)!=external_grant || ((|external_grant) && bus_enable))
                $fatal(1,"external permission without internal grant/isolation");
            if((|drive_low) && (|external_grant)) $fatal(1,"ACK overlaps external permission");
            if((|sampled_drive) && (request!=sampled_request || sampled_drive!=sampled_grant))
                $fatal(1,"ACK echo captured a spurious request");
            if(|protocol_error) $fatal(1,"unexpected protocol diagnostic %b",protocol_error);
        end
        for(int g=0;g<2;g++) if(consume_wait[g] && waits_left[g]>0) waits_left[g]--;
    endtask
    task automatic load_case(input int kind, input int waits);
        reset = 1; bkd_load = 1; pin_int = 0; pin_nmi = 0; remote_low = 0;
        hold_ready = 0; owned_seen = 0; resumed = 0; continuous_isolation=0;
        owned_edges = 0; external_edges[0]=0; external_edges[1]=0; external_pops=0;
        split_read_first=0; split_read_second=0; post_reads = 0; post_stores = 0; irq_boundary_seen=0;
        case_id = kind; wait_mode = waits;
        bkd_regs = 0;
        bkd_regs[0 +: 16] = 16'h1234;
        bkd_regs[16 +: 16] = (kind == 6 || kind==13) ? 1 : 3;
        bkd_regs[64 +: 16] = 16'h0800;
        bkd_regs[96 +: 16] = 16'h0300;
        bkd_regs[112 +: 16] = 16'h0400;
        bkd_regs[208 +: 16] = kind == 5 ? 16'h0202 : 16'h0002;
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
            if (kind == 2 || kind==7 || kind==8) begin
                mem[g][512] = 8'ha5; mem[g][513] = 1;
                mem[g][514] = 0; mem[g][515] = 8'h5a;
            end
            mem[g][1536] = 8'h11; mem[g][1537] = 8'h11;
            if(kind==13) begin
                mem[g][0]=8'hf7; mem[g][1]=8'hf1; mem[g][2]=8'heb; mem[g][3]=8'hfc;
            end else if(kind==7 || kind==8) begin
                mem[g][0]=kind==7 ? 8'hff : 8'h8b; mem[g][1]=8'h06;
                mem[g][2]=1; mem[g][3]=2; mem[g][4]=8'hf4;
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
        remote_low=channel; tick(); remote_low=0; tick();
    endtask
    task automatic wait_external(input logic [1:0] channel,input int limit=4096);
        int n;
        n=0;
        while(external_grant!=channel && n<limit) begin tick(); n++; end
        if(external_grant!=channel) $fatal(1,"ACK/ownership watchdog case=%0d",case_id);
    endtask
    task automatic try_peer_write(input logic [1:0] channel,input logic [15:0] value,output logic accepted);
        accepted=!reset && peer_permission && external_grant==channel && !bus_enable;
        if(accepted) begin mem[0][1536]=value[7:0]; mem[0][1537]=value[15:8]; end
    endtask
    task automatic peer_write(input logic [1:0] channel,input logic [15:0] value);
        logic accepted;
        try_peer_write(channel,value,accepted);
        if(!accepted) $fatal(1,"peer write lacks matching external grant/isolation");
    endtask
    task automatic return_pulse(input logic [1:0] channel);
        // E+1 HIGH rearm and one further HIGH interval precede valid return.
        tick(); tick(); remote_low=channel; tick(); remote_low=0; tick();
    endtask
    task automatic wait_cpu;
        int n;
        n=0;
        while(!resumed && n<128) begin tick(); n++; end
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
        if(case_id==5 && (intas[0]!=2 || regs[0][64+:16]!=16'h07fa ||
            regs[0][144+:16]!=0 || regs[0][192+:16]!=16'h0104 || !irq_boundary_seen ||
            {mem[0][2047],mem[0][2046]}!=16'hf202 ||
            {mem[0][2045],mem[0][2044]}!=16'h0000 ||
            {mem[0][2043],mem[0][2042]}!=irq_saved_ip))
            $fatal(1,"IRQ vector/frame/handler mismatch");
    endtask
    int profiles=0, tw_clocks, n, kind, gaps;
    initial begin
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
            if(external_edges[0]<32) $fatal(1,"protected live ownership bar missed");
            return_pulse(1); wait_cpu();
            n=0;
            while(actual_eu_state[0]!=30 && n<4096) begin tick(); n++; end
            if(actual_eu_state[0]!=30) $fatal(1,"terminal HALT watchdog state=%0d IP=%04x CS=%04x PSW=%04x INTA=%0d frame=%04x/%04x/%04x",actual_eu_state[0],regs[0][192+:16],regs[0][144+:16],regs[0][208+:16],intas[0],{mem[0][2047],mem[0][2046]},{mem[0][2045],mem[0][2044]},{mem[0][2043],mem[0][2042]});
            check_result();
            if(kind==5 && gaps==0) $fatal(1,"IRQ gap coverage absent");
            profiles++;
            $display("PASS rqak-biu-yield protected kind=%0d waits=%0d externalCE=%0d gap=%0d",kind,wait_mode,external_edges[0],gaps);
        end
        no_request_control(6,0); load_case(6,0);
        n=0;
        while(!(cycle_kind[0]==5 && cycle_addr[0]==1536 && !rd[0]) && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"targeted MEMR watchdog");
        hold_ready=1; pulse(2); pulse(1);
        if(request!=3) $fatal(1,"both priority requests not retained");
        tw_clocks=0; n=0;
        while(tw_clocks<16 && n<128) begin
            if(enables[0] && actual_phase[0]==4 && !ready[0] && resolved_n==3 && request==3)
                tw_clocks++;
            if((|grant)||(|external_grant)||(|drive_low)) $fatal(1,"ownership/ACK during READY wait");
            tick(); n++;
        end
        if(tw_clocks<16) $fatal(1,"actual Tw sixteen-clock bar missed");
        hold_ready=0; wait_external(1);
        if(grant!=1 || request!=3) $fatal(1,"channel0 priority/queued channel1 missing");
        continuous_isolation=1;
        peer_write(1,16'h3c5a); repeat(32) tick();
        if(external_edges[0]<32) $fatal(1,"first live DMA owner bar missed");
        return_pulse(1); wait_external(2,128);
        if(resumed) $fatal(1,"CPU bus resumed between queued owners");
        peer_write(2,16'h6a35); repeat(32) tick();
        if(external_edges[1]<32) $fatal(1,"second live DMA owner bar missed");
        return_pulse(2); continuous_isolation=0; wait_cpu();
        n=0;
        while((post_reads<1 || post_stores<1 || regs[0][0+:16]!=16'h6a35) && n<4096) begin tick(); n++; end
        if(n==4096 || {mem[0][1539],mem[0][1538]}!=16'h6a35)
            $fatal(1,"fresh postresume read/literal store bar missed reads=%0d stores=%0d AX=%04x",post_reads,post_stores,regs[0][0+:16]);
        profiles++;
        $display("PASS rqak-biu-yield READY/DMA Tw=%0d queue=%0d ownersCE=%0d/%0d postreads=%0d poststores=%0d",tw_clocks,acquisition_queue,external_edges[0],external_edges[1],post_reads,post_stores);
        no_request_control(13,0); load_case(13,0); n=0;
        while(cores[0].cpu.u_biu.r_q_cnt!=6 && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"natural queue6 watchdog");
        pulse(1); wait_external(1); repeat(128) tick();
        if(acquisition_queue!=6 || external_edges[0]<32 || external_pops<2)
            $fatal(1,"natural queue/live pops bar missed q=%0d pops=%0d",acquisition_queue,external_pops);
        return_pulse(1); wait_cpu();
        // Require fresh public transaction activity after accepted return.
        begin
            int baseline, clocks;
            baseline=completions[0]; clocks=0;
            while(completions[0]<=baseline && clocks<4096) begin tick(); clocks++; end
            if(clocks==4096) $fatal(1,"natural queue transaction resume watchdog");
        end
        profiles++; $display("PASS rqak-biu-yield natural queue=%0d externalCE=%0d pops=%0d",acquisition_queue,external_edges[0],external_pops);
        for(int splitcase=7;splitcase<=8;splitcase++) for(int w=0;w<3;w++) begin
            no_request_control(splitcase,w==2?3:w); load_case(splitcase,w==2?3:w); n=0;
            while(!(cores[0].cpu.u_biu.r_run && !cores[0].cpu.u_biu.r_cur_rd_last &&
                  cycle_addr[0]==513 && cycle_kind[0]==(splitcase==7?6:5) &&
                  actual_phase[0]>=1 && actual_phase[0]<=4) && n<4096) begin tick(); n++; end
            if(n==4096) $fatal(1,"public first split kind/phase watchdog");
            $display("SPLIT request kind=%0d actualphase=%0d modeledphase=%0d addr=%04x",cycle_kind[0],actual_phase[0],phase[0],cycle_addr[0]);
            pulse(1); wait_external(1); repeat(32) tick();
            if(external_edges[0]<32) $fatal(1,"split external live bar missed");
            return_pulse(1); wait_cpu(); n=0;
            while(actual_eu_state[0]!=30 && n<4096) begin tick(); n++; end
            if(n==4096 || mem[0][512]!=8'ha5 || mem[0][515]!=8'h5a ||
               (splitcase==7 && ({mem[0][514],mem[0][513]}!=2 || writes[0]!=2)) ||
               (splitcase==8 && regs[0][0+:16]!=1)) $fatal(1,"split terminal literal failure");
            profiles++; $display("PASS rqak-biu-yield split kind=%0d waits=%0d writes=%0d reads=%0d/%0d",splitcase,wait_mode,writes[0],split_read_first,split_read_second);
        end
        for(int r=0;r<3;r++) begin
            load_case(6,0);
            if(r==0) begin
                n=0; while(!(cycle_kind[0]==5 && cycle_addr[0]==1536 && !rd[0]) && n<4096) begin tick(); n++; end
                if(n==4096) $fatal(1,"reset drain target watchdog");
                hold_ready=1; pulse(1); n=0;
                while(actual_phase[0]!=4 && n<128) begin tick(); n++; end
                if(n==128 || request!=1 || (|grant)) $fatal(1,"reset drain witness absent");
            end else begin
                // RESET clears edge arming; first sample idle HIGH before LOW.
                tick(); pulse(1); n=0;
                while((r==1 ? drive_low!=1 : external_grant!=1) && n<4096) begin tick(); n++; end
                if(n==4096) $fatal(1,"reset ACK/owned watchdog");
                if(r==2 && !peer_permission) $fatal(1,"reset owned permission absent");
            end
            reset_saved_word={mem[0][1537],mem[0][1536]};
            reset=1; #1;
            if(peer_permission) $fatal(1,"reset peer permission did not independently fall");
            try_peer_write(1,16'hdead,stale_accepted); reset_peer_attempts++;
            if(stale_accepted || {mem[0][1537],mem[0][1536]}!=reset_saved_word)
                $fatal(1,"stale peer transaction accepted on reset assertion");
            tick();
            try_peer_write(1,16'hbeef,stale_accepted); reset_peer_attempts++;
            if(stale_accepted || {mem[0][1537],mem[0][1536]}!=reset_saved_word)
                $fatal(1,"stale peer transaction accepted after reset edge");
            if(request!=0 || grant!=0 || external_grant!=0 || drive_low!=0 ||
               protocol_error!=0 || peer_permission || !bus_enable)
                $fatal(1,"reset protocol/isolation cleanup failure");
            remote_low=0; hold_ready=0; reset=0;
            repeat(16) begin tick(); if((|grant)||(|drive_low)||(|external_grant)||(|request)) $fatal(1,"stale ownership after reset"); end
            profiles++; $display("PASS rqak-biu-yield reset phase=%0d idleCE=16",r);
        end
        if(reset_peer_attempts!=6) $fatal(1,"reset stale attempt coverage missing");
        if(profiles!=23) $fatal(1,"exact 23-profile bar missed");
        $display("PASS rqak-biu-yield actual chain: %0d profiles; no-request comparison >=200 per 20 functional profiles",profiles);
        $finish;
    end
endmodule
