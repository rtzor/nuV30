// SPDX-License-Identifier: GPL-2.0-only
// Actual demultiplexed core/frontend/level-adapter simulation.
// Modeled transactions are not hardware or native NEC pin timing evidence.
module tb_rqak_core;
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
    logic hold_ready = 0, freeze_active = 0, resumed = 0;
    int frozen_edges = 0, acquisition_queue = 0, post_reads = 0, post_stores = 0;
    logic [223:0] saved_regs;
    logic [47:0] saved_bus;
    logic [36:0] saved_eu;
    logic [3:0] saved_biu;
    logic [22:0] saved_queue;
    logic [7:0] saved_bytes [6];
    wire [36:0] eu_progress = {cores[0].cpu.u_eu.st,
        cores[0].cpu.u_eu.upc_page, cores[0].cpu.u_eu.upc_opc,
        cores[0].cpu.u_eu.upc_loc, cores[0].cpu.u_eu.rloop_n};
    wire [3:0] biu_progress = {cores[0].cpu.u_biu.r_run,actual_phase[0]};
    wire [22:0] queue_progress = {cores[0].cpu.u_biu.r_q_cnt,
        cores[0].cpu.u_biu.r_q_head,cores[0].cpu.u_biu.r_fetch_ptr};
    wire [47:0] public_bus = {addr[0],data_o[0],status_o[0],bs[0],
        rd[0],ube[0],qs[0],buslock[0]};
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
    wire [1:0] enables = {1'b1,core_ce};
    v30_bus_ownership arb (
        .CLK(clk), .RESET(reset), .CE(1'b1), .CE_HALF(1'b0),
        .REQUEST(request), .CORE_QUIET(quiet[0]), .EXCLUDE(exclude[0]),
        .GRANT(grant), .CORE_CE(core_ce), .CORE_CE_HALF(core_half),
        .CORE_BUS_ENABLE(bus_enable)
    );
    for (genvar g = 0; g < 2; g++) begin : cores
        wire [15:0] unused_ss_rdata;
        wire unused_ss_err, unused_dbg_first_pop, unused_dbg_pend;
        v30_core cpu (
            .CLK(clk), .CE(enables[g]), .RESET(reset), .READY(ready[g]),
            .INT(pin_int), .NMI(pin_nmi), .POLL_N(1'b1),
            .DATA_I(data_i[g]), .ADDR_O(addr[g]), .DATA_O(data_o[g]),
            .STATUS_O(status_o[g]), .QS(qs[g]), .BS(bs[g]),
            .RD_N(rd[g]), .UBE_N(ube[g]), .BUSLOCK_N(buslock[g]),
            .BUS_EXCLUDE(exclude[g]), .SS_ADDR('0), .SS_WDATA('0),
            .SS_WE(1'b0), .SS_RDATA(unused_ss_rdata), .SS_ERR(unused_ss_err), .SS_BUS_QUIET(quiet[g]),
            .bkd_load(bkd_load), .bkd_regs(bkd_regs), .bkd_queue('0),
            .bkd_qlen('0), .bkd_fetch_ip('0), .scr_en(1'b0),
            .scr_qop('0), .dbg_regs(regs[g]), .dbg_first_pop(unused_dbg_first_pop), .dbg_pend(unused_dbg_pend)
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
    task automatic tick;
        logic [1:0] consume_wait;
        logic sampled_cpu_ce, sampled_bus_enable;
        int commits_before;
        // Model T1/T2/T3/Tw/T4 from public BS and READY. Advance with the
        // same enable as its CPU, so ownership never commits a frozen cycle.
        #1;
        consume_wait = 0;
        sampled_cpu_ce = core_ce; sampled_bus_enable = bus_enable;
        commits_before = completions[0];
        if (!reset && case_id==5 && core_ce && actual_eu_state[0]==32 && !irq_boundary_seen) begin
            irq_saved_ip=regs[0][192+:16]; irq_boundary_seen=1;
        end
        if (!reset && freeze_active && sampled_cpu_ce) begin
            freeze_active = 0; resumed = 1;
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
                    if(g==0 && case_id==5 && completions[g]<24)
                        $display("IRQ transaction kind=%0d addr=%04x input=%04x output=%04x IP=%04x CS=%04x st=%0d",cycle_kind[g],cycle_addr[g],data_i[g],data_o[g],regs[g][192+:16],regs[g][144+:16],actual_eu_state[g]);
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
                        // address and lane selection remain the T1 snapshots.
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
        if (!reset && case_id==5 && intas[0]==2) pin_int=0;
        #1 clk = 1; #1 clk = 0;
        if (!reset && !sampled_bus_enable &&
            commits_before != completions[0])
            $fatal(1,"modeled CPU transaction committed while isolated");
        if (!reset && (|grant) && !freeze_active) begin
            if (sampled_cpu_ce) $fatal(1,"acquisition edge advanced CPU");
            if (!quiet[0] || cores[0].cpu.u_biu.r_run || cores[0].cpu.u_biu.r_cmt_valid)
                $fatal(1,"acquisition with active/committed CPU cycle");
            freeze_active = 1; frozen_edges = 0;
            saved_regs = regs[0]; saved_bus = public_bus;
            saved_eu = eu_progress; saved_biu = biu_progress; saved_queue = queue_progress;
            acquisition_queue = int'(cores[0].cpu.u_biu.r_q_cnt);
            for (int i=0;i<6;i++) saved_bytes[i] = cores[0].cpu.u_biu.r_q_mem[i];
        end
        if (!reset && freeze_active && !sampled_cpu_ce) begin
            frozen_edges++;
            if (regs[0] !== saved_regs || public_bus !== saved_bus ||
                eu_progress !== saved_eu || biu_progress !== saved_biu || queue_progress !== saved_queue)
                $fatal(1,"CPU state/phase advanced on frozen clock case=%0d",case_id);
            for (int i=0;i<6;i++)
                if (saved_bytes[i] !== cores[0].cpu.u_biu.r_q_mem[i])
                    $fatal(1,"queue bytes changed on frozen clock");
        end
        if (!reset && (|protocol_error)) $fatal(1,"unexpected protocol diagnostic %b",protocol_error);
        if (!reset && (|grant)) begin
            if (exclude[0]) $fatal(1,"grant during real exclusion");
            if ((case_id==1 && writes[0]<1) || (case_id==2 && writes[0]<2) ||
                (case_id==3 && (writes[0]<3 || regs[0][16+:16]!=0)) ||
                (case_id==5 && intas[0]!=2)) $fatal(1,"grant preceded protected operation completion");
        end
        for (int g = 0; g < 2; g++) if (consume_wait[g] && waits_left[g]>0) waits_left[g]--;
    endtask
    task automatic load_case(input int kind, input int waits);
        reset = 1; bkd_load = 1; pin_int = 0; pin_nmi = 0; remote_low = 0;
        hold_ready = 0; freeze_active = 0; resumed = 0;
        frozen_edges = 0; post_reads = 0; post_stores = 0; irq_boundary_seen=0;
        case_id = kind; wait_mode = waits;
        bkd_regs = 0;
        bkd_regs[0 +: 16] = 16'h1234;
        bkd_regs[16 +: 16] = kind == 6 ? 1 : 3;
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
            if (kind == 2) begin
                mem[g][512] = 8'ha5; mem[g][513] = 1;
                mem[g][514] = 0; mem[g][515] = 8'h5a;
            end
            mem[g][1536] = 8'h11; mem[g][1537] = 8'h11;
            if (kind == 6) begin
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
    task automatic wait_external(input logic [1:0] channel,input int limit=8192);
        int n;
        n=0;
        while(external_grant!=channel && n<limit) begin tick(); n++; end
        if(external_grant!=channel) $fatal(1,"ACK/ownership watchdog case=%0d",case_id);
    endtask
    task automatic peer_write(input logic [1:0] channel,input logic [15:0] value);
        if(external_grant!=channel || bus_enable || core_ce)
            $fatal(1,"peer write lacks external grant/isolation");
        mem[0][1536]=value[7:0]; mem[0][1537]=value[15:8];
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
            while(external_grant!=1 && n<8192) begin
                if(kind==5 && intas[0]==1 && bs[0]==7) begin
                    gaps++; if(!exclude[0]) $fatal(1,"IRQ acknowledge gap lost exclusion");
                end
                tick(); n++;
            end
            if(external_grant!=1) $fatal(1,"protected ownership watchdog");
            repeat(32) tick();
            if(frozen_edges<32) $fatal(1,"protected pause bar missed");
            return_pulse(1); wait_cpu();
            n=0;
            while(actual_eu_state[0]!=30 && n<4096) begin tick(); n++; end
            if(actual_eu_state[0]!=30) $fatal(1,"terminal HALT watchdog state=%0d IP=%04x CS=%04x PSW=%04x INTA=%0d frame=%04x/%04x/%04x",actual_eu_state[0],regs[0][192+:16],regs[0][144+:16],regs[0][208+:16],intas[0],{mem[0][2047],mem[0][2046]},{mem[0][2045],mem[0][2044]},{mem[0][2043],mem[0][2042]});
            check_result();
            if(kind==5 && gaps==0) $fatal(1,"IRQ gap coverage absent");
            profiles++;
            $display("PASS rqak-core protected kind=%0d waits=%0d snapshot=%0d gap=%0d",kind,wait_mode,frozen_edges,gaps);
        end
        no_request_control(6,0); load_case(6,0);
        n=0;
        while(!(cycle_kind[0]==5 && cycle_addr[0]==1536 && !rd[0]) && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"targeted MEMR watchdog");
        hold_ready=1; pulse(2); pulse(1);
        if(request!=3) $fatal(1,"both priority requests not retained");
        tw_clocks=0; n=0;
        while(tw_clocks<16 && n<128) begin
            if(core_ce && actual_phase[0]==4 && !ready[0] && resolved_n==3 && request==3)
                tw_clocks++;
            if((|grant)||(|external_grant)||(|drive_low)) $fatal(1,"ownership/ACK during READY wait");
            tick(); n++;
        end
        if(tw_clocks<16) $fatal(1,"actual Tw sixteen-clock bar missed");
        hold_ready=0; wait_external(1);
        if(acquisition_queue<1) $fatal(1,"nonempty acquisition queue bar missed");
        peer_write(1,16'h3c5a); repeat(32) tick();
        if(frozen_edges<32) $fatal(1,"DMA snapshot bar missed");
        return_pulse(1); wait_external(2,128);
        if(resumed) $fatal(1,"CPU resumed between queued owners");
        peer_write(2,16'h6a35); return_pulse(2); wait_cpu();
        n=0;
        while((post_reads<1 || post_stores<1 || regs[0][0+:16]!=16'h6a35) && n<4096) begin tick(); n++; end
        if(n==4096 || {mem[0][1539],mem[0][1538]}!=16'h6a35)
            $fatal(1,"fresh postresume read/literal store bar missed reads=%0d stores=%0d AX=%04x",post_reads,post_stores,regs[0][0+:16]);
        profiles++;
        $display("PASS rqak-core READY/DMA Tw=%0d queue=%0d frozen=%0d postreads=%0d poststores=%0d",tw_clocks,acquisition_queue,frozen_edges,post_reads,post_stores);
        if(profiles!=13) $fatal(1,"profile count bar missed");
        $display("PASS rqak-core actual chain: %0d profiles; raw comparison >=200 per profile",profiles);
        $finish;
    end
endmodule
