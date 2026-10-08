// SPDX-License-Identifier: GPL-2.0-only
// Actual multiplexed core/frontend/level-adapter simulation.
// Modeled transactions are not hardware or native NEC pin timing evidence.
module tb_rqak_mux_yield;
    logic clk = 0, reset = 1, bkd_load = 0;
    logic ce=0, ce_half=0, pad_override=0;
    int ce_div=2, fabric_phase=0, cpu_intervals=0, trace_profile=0;
    int trace_file=0, trace_only=0, pad_probe_kind=0, pad_probe_hits=0, total_pad_probes=0;
    int halt_announcements=0, halt_completions=0, t4_drains=0, div_t4_base=0, half_requests=0, half_returns=0, div_req_base=0, div_return_base=0;
    logic [19:0] pin_history=0, retained_snapshot=0;
    logic halt_retention_watch=0;
    string trace_path;
    wire [19:0] ad [2];
    wire [19:0] ad_oe [2];
    wire [19:0] peer_pattern = pad_override ? 20'h559c1 : fabric_phase[0] ? 20'ha35ca : 20'h5ca35;
    wire peer_drive = !reset && (peer_permission || pad_override);
    logic memory_drive[2], tw_watch=0;
    logic [3:0] cycle_hi[2];
    logic [223:0] bkd_regs = 0;
    logic pin_int = 0, pin_nmi = 0;
    logic [1:0] remote_low = 0;
    wire [1:0] request, drive_low, external_grant, protocol_error;
    wire [1:0] resolved_n = ~(remote_low | drive_low);
    v30_rqak_frontend frontend (
        .CLK(clk), .RESET(reset), .CE(ce), .RQAK_I_N(resolved_n),
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
    logic cycle_ube [2], address_sampled[2];
    int writes [2], intas [2], completions [2];
    logic [15:0] irq_saved_ip;
    logic irq_boundary_seen = 0;
    int wait_mode = 0, case_id = 0;
    wire [1:0] enables = {ce,ce};
    v30_bus_ownership arb (
        .CLK(clk), .RESET(reset), .CE(ce), .CE_HALF(ce_half),
        .REQUEST(request), .CORE_QUIET(yield_ready[0]), .EXCLUDE(exclude[0]),
        .GRANT(grant), .CORE_CE(core_ce), .CORE_CE_HALF(core_half),
        .CORE_BUS_ENABLE(bus_enable)
    );
    for (genvar g = 0; g < 2; g++) begin : cores
        wire [19:0] shared_ad;
        assign ad[g]=shared_ad;
        v30_core cpu (
            .CLK(clk), .CE(enables[g]), .CE_HALF(ce_half), .RESET(reset), .READY(ready[g]),
            .INT(pin_int), .NMI(pin_nmi), .POLL_N(1'b1),
            .AD(shared_ad), .AD_OE(ad_oe[g]), .ADDR_O(addr[g]), .DATA_O(data_o[g]),
            .STATUS_O(status_o[g]), .QS(qs[g]), .BS(bs[g]),
            .RD_N(rd[g]), .UBE_N(ube[g]), .BUSLOCK_N(buslock[g]),
`ifdef V30_BUS_OWNERSHIP
            .BUS_EXCLUDE(exclude[g]),
`endif
`ifdef V30_BIU_YIELD
            .YIELD_PENDING(g==0 && |request), .BUS_OWNED(g==0 && (!bus_enable || pad_override)),
            .YIELD_READY(yield_ready[g]),
`endif
            .SS_ADDR('0), .SS_WDATA('0),
            .SS_WE(1'b0), .SS_RDATA(), .SS_ERR(), .SS_BUS_QUIET(quiet[g]),
            .bkd_load(bkd_load), .bkd_regs(bkd_regs), .bkd_queue('0),
            .bkd_qlen('0), .bkd_fetch_ip('0), .scr_en(1'b0),
            .scr_qop('0), .dbg_regs(regs[g]), .dbg_first_pop(), .dbg_pend()
        );
`ifndef V30_BUS_OWNERSHIP
        assign exclude[g]=1'b0;
`endif
`ifndef V30_BIU_YIELD
        assign yield_ready[g]=1'b0;
`endif
        assign shared_ad[15:0] = memory_drive[g] ? data_i[g] : 16'hzzzz;
        if(g==0) begin : peer_connection
            assign shared_ad[15:0] = peer_drive ? peer_pattern[15:0] : 16'hzzzz;
            assign shared_ad[19:16] = peer_drive ? peer_pattern[19:16] : 4'hz;
        end
        assign actual_phase[g] = cpu.u_biu.r_ts;
        assign actual_page[g] = cpu.u_eu.upc_page;
        assign actual_eu_state[g] = cpu.u_eu.st;
        always_comb begin
            ready[g] = !hold_ready && waits_left[g] == 0;
            memory_drive[g]=!reset && (g!=0 || (bus_enable && !pad_override)) && !rd[g];
            data_i[g] = cycle_kind[g] == 0 ? 16'h0020 :
                {mem[g][(cycle_addr[g]&65534)+1],mem[g][cycle_addr[g]&65534]};
        end
    end
    task automatic reject_cpu_activity;
        if(bs[0]!=7 || cores[0].cpu.u_biu.r_run || cores[0].cpu.u_biu.r_cmt_valid ||
           cores[0].cpu.u_biu.inta_preview || cores[0].cpu.u_biu.vector_follow_preview ||
           cores[0].cpu.u_biu.flush_fast)
            $fatal(1,"isolated CPU announcement/physical preview case=%0d",case_id);
    endtask
    task automatic trace_row(input int position);
        if(trace_only!=0) $fdisplay(trace_file,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %05x %05x %05x %04x %01x %01x %01x %01x %01x %01x %056x",trace_profile,case_id,wait_mode,ce_div,cpu_intervals,fabric_phase,position,ce,ce_half,reset,ad[0],ad_oe[0],addr[0],data_o[0],status_o[0],bs[0],qs[0],rd[0],ube[0],buslock[0],regs[0]);
    endtask
    task automatic pad_probe(input logic low_required);
        logic [43:0] raw_before;
        logic [19:0] driven_before;
        raw_before={cores[0].cpu.ad_o,cores[0].cpu.ad_oe_addr,cores[0].cpu.ad_oe_ps,cores[0].cpu.ad_oe_data,cores[0].cpu.u_biu.t1_half2,cores[0].cpu.u_biu.last_ad_hi,cores[0].cpu.u_biu.last_ad_lo};
        driven_before=ad[0];
        if(!low_required && (ad_oe[0][0] || ((driven_before[19:16] & ~4'h5)==0)))
            $fatal(1,"read high-only mask probe not value-visible against peer5");
        if(low_required && cores[0].cpu.u_biu.t1_half2==0 && ad[0][15:0]!=16'h0200) $fatal(1,"write pre-HALF address literal absent");
        if(low_required && cores[0].cpu.u_biu.t1_half2==1 && ad[0][15:0]!=16'h1234) $fatal(1,"write post-HALF data literal absent");
        if(!ad_oe[0][16] || (low_required && !ad_oe[0][0])) $fatal(1,"pad probe raw OE not nonzero");
        pad_override=1; #1;
        if(ad_oe[0]!=0 || ad[0]!=peer_pattern || raw_before!={cores[0].cpu.ad_o,cores[0].cpu.ad_oe_addr,cores[0].cpu.ad_oe_ps,cores[0].cpu.ad_oe_data,cores[0].cpu.u_biu.t1_half2,cores[0].cpu.u_biu.last_ad_hi,cores[0].cpu.u_biu.last_ad_lo})
            $fatal(1,"combinational public pad mask probe failed");
        pad_override=0; #1;
        if(ad[0]!=driven_before || !ad_oe[0][16] || (low_required && !ad_oe[0][0])) $fatal(1,"CPU drive not restored before clock");
        pad_probe_hits++;
    endtask
    task automatic pins_check;
        if(!reset && !bus_enable && ad_oe[0]!=0) $fatal(1,"isolated CPU pad drive");
        if(peer_drive && (ad_oe[0]!=0 || memory_drive[0] || ad[0]!=peer_pattern)) $fatal(1,"shared peer value/OE/isolation mismatch");
        for(int g=0;g<2;g++) if(memory_drive[g] && ad_oe[g][0]) $fatal(1,"CPU/memory shared low-lane overlap");
        if(!reset && owned_seen && !bus_enable &&
           {cores[0].cpu.u_biu.last_ad_hi,cores[0].cpu.u_biu.last_ad_lo}!=retained_snapshot) $fatal(1,"peer traffic altered raw pad retention");
    endtask
    task automatic fabric_edge;
        logic [1:0] consume_wait, sampled_grant, sampled_external, sampled_drive, sampled_request;
        logic sampled_bus_enable, sampled_ready, sampled_exclude;
        int commits_before;
        #1;
        if(ce && ce_half) $fatal(1,"bench enables coincide");
        if(ce_half && !reset) for(int g=0;g<2;g++) if(phase[g]==1 && !address_sampled[g] && (g!=0 || bus_enable)) begin
            if(actual_phase[g]!=1) $fatal(1,"address sample is not actual T1 half");
            if(cycle_kind[g]!=0) begin
                if(ad_oe[g]!=20'hfffff || ad[g][15:0]!=addr[g][15:0]) $fatal(1,"actual T1 shared address/OE mismatch kind=%0d AD=%05x ADDR=%05x",cycle_kind[g],ad[g],addr[g]);
                cycle_addr[g]=int'(ad[g][15:0]);
                if({cycle_hi[g],ad[g][15:0]}!=addr[g]) $fatal(1,"announced high/T1 low address mismatch");
            end else cycle_addr[g]=0;
            cycle_ube[g]=ube[g]; address_sampled[g]=1;
            if(g==0 && case_id==16 && halt_retention_watch && resumed && cycle_kind[g]==3 && (ad[g]!=retained_snapshot || addr[g]!=retained_snapshot))
                $fatal(1,"HALT publication mismatch AD=%05x ADDR=%05x retained=%05x rawlast=%05x history=%05x phase=%0d actual=%0d run=%0d halt=%0d cmthalt=%0d resumed=%0d",ad[g],addr[g],retained_snapshot,{cores[0].cpu.u_biu.last_ad_hi,cores[0].cpu.u_biu.last_ad_lo},pin_history,phase[g],actual_phase[g],cores[0].cpu.u_biu.r_run,cores[0].cpu.u_biu.r_cur_halt,cores[0].cpu.u_biu.r_cmt_halt,resumed);
        end
        if(trace_only==0 && ce_half && pad_probe_kind==1 && pad_probe_hits==0 && actual_phase[0]==1 && cycle_kind[0]==6 && cycle_addr[0]==512) pad_probe(1);
        if(trace_only==0 && ce_half && pad_probe_kind==2 && pad_probe_hits==0 && actual_phase[0]==2 && cycle_kind[0]==5 && cycle_addr[0]==1536) pad_probe(0);
        pins_check(); trace_row(0);
        if(!reset && ce && tw_watch && actual_phase[0]==4 && !ready[0] && resolved_n==3 && request==3) tw_clocks++;
        if(!reset && ce) begin
            if(ad_oe[0][16]) pin_history[19:16]=ad[0][19:16];
            if(ad_oe[0][0]) pin_history[15:0]=ad[0][15:0];
        end
        consume_wait=0; sampled_bus_enable=bus_enable; sampled_grant=grant;
        sampled_external=external_grant; sampled_drive=drive_low; sampled_request=request;
        sampled_ready=yield_ready[0]; sampled_exclude=exclude[0];
        commits_before=completions[0];
        // Corroborate the public T4 before the observer advances its phase.
        if(!reset && ce && actual_phase[0]==5 && phase[0]==5 && (|request) && !(|grant)) begin
            t4_drains++;
            $display("T4 drain div=%0d case=%0d completion=%0d kind=%0d address=%04x grant=%b",ce_div,case_id,completions[0],cycle_kind[0],cycle_addr[0],grant);
        end
        if(enables!={ce,ce}) $fatal(1,"core CE is not live");
        if(!reset && !bus_enable) reject_cpu_activity();
        if(!reset && (|grant) && bus_enable) $fatal(1,"internal owner/ACK/return gap lost isolation");
        if(!reset && continuous_isolation && bus_enable)
            $fatal(1,"bus isolation broken between queued owners/ACK/gaps CE=%0d HALF=%0d f=%0d grant=%b ext=%b req=%b frontendphase=%0d ready=%0d exclude=%0d resumed=%0d",ce,ce_half,fabric_phase,grant,external_grant,request,frontend.phase,yield_ready[0],exclude[0],resumed);
        if(!reset && owned_seen && sampled_bus_enable) begin owned_seen=0; resumed=1; end
        if(!reset && ce && (|sampled_external)) begin
            if(cores[0].cpu.u_biu.pop_now) external_pops++;
            for(int c=0;c<2;c++) if(sampled_external[c]) external_edges[c]++;
        end
        if(!reset && case_id==5 && ce && actual_eu_state[0]==32 && !irq_boundary_seen) begin
            irq_saved_ip=regs[0][192+:16]; irq_boundary_seen=1;
        end
        // Transaction phase is derived from public BS/READY. Registered BIU
        // phase corroborates T1/complete; bus permission gates the model.
        for(int g=0;g<2;g++) begin
            if(reset) begin
                phase[g]=0; address_sampled[g]=0; waits_left[g]=0; writes[g]=0; intas[g]=0;
                completions[g]=0; cycle_kind[g]=7;
            end else if(enables[g] && (g!=0 || bus_enable)) begin
                if(phase[g]==0 || phase[g]==5) begin
                    if(bs[g]!=7) begin
                        phase[g]=1; address_sampled[g]=0; cycle_kind[g]=int'(bs[g]); cycle_addr[g]=0; cycle_hi[g]=ad[g][19:16];
                        cycle_ube[g]=ube[g]; waits_left[g]=wait_mode;
                        if(g==0 && cycle_kind[g]==3) halt_announcements++;
                    end else phase[g]=0;
                end else if(phase[g]==1 || phase[g]==2) begin
                    phase[g]++;
                end else if((phase[g]==3 || phase[g]==4) && !ready[g]) begin
                    phase[g]=4; consume_wait[g]=1;
                end else begin
                    if((cycle_kind[g]==0 || cycle_kind[g]==5) && !(actual_phase[g]==3 || actual_phase[g]==4))
                        $fatal(1,"public completion phase mismatch");
                    phase[g]=5; completions[g]++;
                    if(g==0 && cycle_kind[g]==3) halt_completions++;
                    if(cycle_kind[g]==0) intas[g]++;
                    if(g==0 && cycle_kind[g]==5) begin
                        if(cycle_addr[g]==513) split_read_first++;
                        if(cycle_addr[g]==514) split_read_second++;
                        if(resumed && cycle_addr[g]==1536) post_reads++;
                    end
                    if(cycle_kind[g]==6) begin
                        writes[g]++;
                        if(g==0 && resumed && cycle_addr[g]==1538 && ad[g][15:0]==16'h6a35) post_stores++;
                        if((cycle_addr[g]&1)!=0) begin
                            if(!cycle_ube[g]) mem[g][cycle_addr[g]]=ad[g][15:8];
                        end else begin
                            mem[g][cycle_addr[g]]=ad[g][7:0];
                            if(!cycle_ube[g]) mem[g][cycle_addr[g]+1]=ad[g][15:8];
                        end
                    end
                end
            end
        end
        if(!reset && case_id==5 && intas[0]==2) pin_int=0;
        #1 clk=1; #1 clk=0;
        pins_check(); trace_row(1);
        if(trace_only==0 && ce_half && pad_probe_kind==1 && pad_probe_hits==1 && actual_phase[0]==1 && cycle_kind[0]==6 && cycle_addr[0]==512) pad_probe(1);
        if(!reset && ce && !sampled_bus_enable) begin
            owned_edges++;
            if(commits_before!=completions[0]) $fatal(1,"modeled CPU completion while isolated");
            // Release edge is also inhibited by pre-edge BUS_OWNED.
            reject_cpu_activity();
        end
        if(!reset && !bus_enable) reject_cpu_activity();
        if(!reset && (|grant) && bus_enable) $fatal(1,"internal owner/ACK/return gap lost isolation");
        if(!reset && (|grant) && sampled_grant==0) begin
            owned_seen=1; acquisition_queue=int'(cores[0].cpu.u_biu.r_q_cnt);
            retained_snapshot={cores[0].cpu.u_biu.last_ad_hi,cores[0].cpu.u_biu.last_ad_lo};
            if(case_id==16) halt_retention_watch=1;
            if(retained_snapshot!=pin_history) $fatal(1,"retained latch differs from actual driven-pin history");
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
            if(!ce && request!=sampled_request) $fatal(1,"frontend request changed without actual core CE");
            if(grant==3 || external_grant==3) $fatal(1,"non-onehot grant");
            if((external_grant & grant)!=external_grant || ((|external_grant) && bus_enable))
                $fatal(1,"external permission without internal grant/isolation");
            if((|drive_low) && (|external_grant)) $fatal(1,"ACK overlaps external permission");
            if((|sampled_drive) && (request!=sampled_request || sampled_drive!=sampled_grant))
                $fatal(1,"ACK echo captured a spurious request");
            if(|protocol_error) $fatal(1,"unexpected protocol diagnostic %b",protocol_error);
        end
        for(int g=0;g<2;g++) if(ce && consume_wait[g] && waits_left[g]>0) waits_left[g]--;
    endtask
    task automatic tick;
        for(int f=0;f<ce_div;f++) begin
            fabric_phase=f; ce=f==0; ce_half=f==ce_div/2;
            fabric_edge();
        end
        cpu_intervals++;
    endtask
    task automatic load_case(input int kind, input int waits);
        reset = 1; bkd_load = 1; pin_int = 0; pin_nmi = 0; remote_low = 0;
        hold_ready = 0; owned_seen = 0; resumed = 0; continuous_isolation=0;
        owned_edges = 0; external_edges[0]=0; external_edges[1]=0; external_pops=0;
        split_read_first=0; split_read_second=0; post_reads = 0; post_stores = 0; irq_boundary_seen=0;
        case_id = kind; wait_mode = waits; cpu_intervals=0; tw_watch=0; pin_history=0; halt_announcements=0; halt_completions=0; halt_retention_watch=0; pad_override=0;
        bkd_regs = 0;
        bkd_regs[0 +: 16] = 16'h1234;
        bkd_regs[16 +: 16] = (kind == 6 || kind==13 || kind==16) ? 1 : 3;
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
            if(kind==16) begin
                mem[g][0]=8'ha3; mem[g][1]=0; mem[g][2]=2;
                mem[g][3]=8'hf7; mem[g][4]=8'hf1;
                mem[g][5]=8'hf4;
            end else if(kind==13) begin
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
        if (regs[0] !== regs[1] || ad[0]!==ad[1] || ad_oe[0]!==ad_oe[1] ||
            {addr[0],data_o[0],status_o[0],bs[0],qs[0],rd[0],ube[0],buslock[0]} !==
            {addr[1],data_o[1],status_o[1],bs[1],qs[1],rd[1],ube[1],buslock[1]})
            $fatal(1,"raw/chained mismatch case=%0d waits=%0d",case_id,wait_mode);
    endtask
    task automatic no_request_control(input int kind,input int waits);
        trace_profile++; load_case(kind,waits);
        for(int n=0;n<200;n++) begin
            if(kind==5 && n==30) pin_int=1;
            tick(); compare_raw();
        end
    endtask
    task automatic pulse(input logic [1:0] channel);
        // Begin LOW just before HALF, retaining it through the next actual CE.
        begin
            logic [1:0] before_request;
            before_request=request; remote_low=channel; ce=0; ce_half=1; fabric_phase=ce_div/2;
            fabric_edge(); if(request!=before_request) $fatal(1,"frontend captured on HALF without CE");
            half_requests++;
        end
        tick(); remote_low=0; tick();
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
        tick(); tick();
        // Begin LOW just after an actual HALF, then hold through CE.
        ce=0; ce_half=1; fabric_phase=ce_div/2; fabric_edge();
        remote_low=channel; half_returns++; tick(); remote_low=0; tick();
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
    function automatic logic natural_halt_queued;
        logic present;
        present=0;
        for(int q=0;q<int'(cores[0].cpu.u_biu.r_q_cnt);q++)
            if(cores[0].cpu.u_biu.r_q_mem[(int'(cores[0].cpu.u_biu.r_q_head)+q)%6]==8'hf4) present=1;
        return present;
    endfunction
    task automatic trace_matrix;
        for(int d=2;d<=4;d++) begin
            ce_div=d;
            for(int w=0;w<3;w++) for(int c=0;c<4;c++) no_request_control(c==3?5:c+1,w==2?3:w);
            no_request_control(6,0); no_request_control(13,0);
            for(int k=7;k<=8;k++) for(int w=0;w<3;w++) no_request_control(k,w==2?3:w);
            no_request_control(16,0);
        end
        if(trace_profile!=63) $fatal(1,"baseline63 trace profiles missing");
    endtask
    int profiles=0, tw_clocks, n, kind, gaps;
    initial begin
        if($test$plusargs("bad_ce_overlap")) begin ce=1; ce_half=1; #1 clk=1; #1; $fatal(1,"missing C-a diagnostic"); end
        if($test$plusargs("bad_no_half")) begin
            ce_div=2; repeat(4) tick(); reset=0; bkd_load=0; ce=1; ce_half=0;
            #1 clk=1; #1 clk=0; #1 clk=1; #1; $fatal(1,"missing S-1 diagnostic");
        end
        if($value$plusargs("trace_only=%d",trace_only) && trace_only!=0) begin
            if(!$value$plusargs("trace=%s",trace_path)) $fatal(1,"trace filename required");
            trace_file=$fopen(trace_path,"w"); if(trace_file==0) $fatal(1,"trace open failed");
            trace_matrix(); $fclose(trace_file); $display("PASS mux baseline/inactive traces profiles=63"); $finish;
        end
`ifndef V30_MUXED_YIELD
        $fatal(1,"baseline executable is trace-only");
`endif
        for(int d=2;d<=4;d++) begin
        ce_div=d; div_t4_base=t4_drains; div_req_base=half_requests; div_return_base=half_returns;
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
            $display("PASS rqak-mux-yield protected kind=%0d waits=%0d externalCE=%0d gap=%0d",kind,wait_mode,external_edges[0],gaps);
        end
        no_request_control(6,0); load_case(6,0);
        n=0;
        while(!(cycle_kind[0]==5 && cycle_addr[0]==1536 && !rd[0]) && n<4096) begin tick(); n++; end
        if(n==4096) $fatal(1,"targeted MEMR watchdog");
        hold_ready=1; pulse(2); pulse(1);
        if(request!=3) $fatal(1,"both priority requests not retained");
        tw_clocks=0; n=0; tw_watch=1;
        while(tw_clocks<16 && n<128) begin
            if((|grant)||(|external_grant)||(|drive_low)) $fatal(1,"ownership/ACK during READY wait");
            tick(); n++;
        end
        if(tw_clocks<16) $fatal(1,"actual Tw sixteen-clock bar missed");
        tw_watch=0; hold_ready=0; wait_external(1);
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
        $display("PASS rqak-mux-yield READY/DMA Tw=%0d queue=%0d ownersCE=%0d/%0d postreads=%0d poststores=%0d",tw_clocks,acquisition_queue,external_edges[0],external_edges[1],post_reads,post_stores);
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
        profiles++; $display("PASS rqak-mux-yield natural queue=%0d externalCE=%0d pops=%0d",acquisition_queue,external_edges[0],external_pops);
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
            profiles++; $display("PASS rqak-mux-yield split kind=%0d waits=%0d writes=%0d reads=%0d/%0d",splitcase,wait_mode,writes[0],split_read_first,split_read_second);
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
                // Sample idle HIGH and establish actual driven-pin history.
                n=0; while(completions[0]==0 && n<4096) begin tick(); n++; end
                if(n==4096) $fatal(1,"reset ACK/owned initial public cycle watchdog");
                pulse(1); n=0;
                while((r==1 ? drive_low!=1 : external_grant!=1) && n<4096) begin tick(); n++; end
                if(n==4096) $fatal(1,"reset ACK/owned watchdog");
                if(r==2 && !peer_permission) $fatal(1,"reset owned permission absent");
            end
            reset_saved_word={mem[0][1537],mem[0][1536]};
            ce=0; ce_half=1; fabric_phase=ce_div/2; reset=1; #1;
            if(peer_permission) $fatal(1,"reset peer permission did not independently fall");
            try_peer_write(1,16'hdead,stale_accepted); reset_peer_attempts++;
            if(stale_accepted || {mem[0][1537],mem[0][1536]}!=reset_saved_word)
                $fatal(1,"stale peer transaction accepted on reset assertion");
            fabric_edge();
            try_peer_write(1,16'hbeef,stale_accepted); reset_peer_attempts++;
            if(stale_accepted || {mem[0][1537],mem[0][1536]}!=reset_saved_word)
                $fatal(1,"stale peer transaction accepted after reset edge");
            if(request!=0 || grant!=0 || external_grant!=0 || drive_low!=0 ||
               protocol_error!=0 || peer_permission || !bus_enable)
                $fatal(1,"reset protocol/isolation cleanup failure");
            remote_low=0; hold_ready=0; reset=0;
            repeat(16) begin tick(); if((|grant)||(|drive_low)||(|external_grant)||(|request)) $fatal(1,"stale ownership after reset"); end
            profiles++; $display("PASS rqak-mux-yield reset phase=%0d idleCE=16",r);
        end
        no_request_control(16,0); load_case(16,0); n=0;
        while(!(writes[0]==1 && natural_halt_queued() && actual_eu_state[0]!=30) && n<4096) begin tick(); n++; end
        if(n==4096 || {mem[0][513],mem[0][512]}!=16'h1234) $fatal(1,"HALT store/naturally queued byte watchdog writes=%0d q=%0d state=%0d IP=%04x store=%04x",writes[0],cores[0].cpu.u_biu.r_q_cnt,actual_eu_state[0],regs[0][192+:16],{mem[0][513],mem[0][512]});
        $display("HALT request naturalbyte=1 q=%0d state=%0d",cores[0].cpu.u_biu.r_q_cnt,actual_eu_state[0]);
        pulse(1); wait_external(1); n=0;
        while(!(actual_eu_state[0]==30 && cores[0].cpu.u_biu.r_halt_pending) && n<512) begin tick(); n++; end
        if(n==512 || halt_announcements!=0 || cores[0].cpu.u_biu.r_cmt_valid) $fatal(1,"pending HALT ownership witness absent");
        repeat(32) tick(); return_pulse(1); wait_cpu(); n=0;
        while(halt_completions!=1 && n<4096) begin tick(); n++; end
        if(n==4096 || halt_announcements!=1 || {mem[0][513],mem[0][512]}!=16'h1234)
            $fatal(1,"retained HALT completion/literal failure");
        profiles++; $display("PASS rqak-mux-yield pendingHALT div=%0d retained=%05x",ce_div,retained_snapshot);
        if(t4_drains<=div_t4_base || half_requests<=div_req_base || half_returns<=div_return_base) $fatal(1,"per-divisor witness missing T4=%0d reqHALF=%0d returnHALF=%0d",t4_drains-div_t4_base,half_requests-div_req_base,half_returns-div_return_base);
        $display("PASS mux divisor=%0d T4drains=%0d halfrequests=%0d halfreturns=%0d",ce_div,t4_drains-div_t4_base,half_requests-div_req_base,half_returns-div_return_base);
        end
        if(reset_peer_attempts!=18 || profiles!=72 || t4_drains<3 || half_requests<3 || half_returns<3) $fatal(1,"72 profile/reset/T4 witness bar missed profiles=%0d T4=%0d",profiles,t4_drains);
        for(int d=2;d<=4;d++) for(int probe=1;probe<=2;probe++) begin
            ce_div=d; pad_probe_kind=probe; pad_probe_hits=0;
            load_case(probe==1?16:6,0); n=0;
            while(pad_probe_hits<(probe==1?2:1) && n<4096) begin tick(); n++; end
            if(n==4096) $fatal(1,"non-clocked pad probe target watchdog");
            pad_probe_kind=0;
            if(probe==1) begin
                n=0; while(writes[0]==0 && n<4096) begin tick(); n++; end
                if(n==4096 || {mem[0][513],mem[0][512]}!=16'h1234) $fatal(1,"pad probe store did not complete normally");
            end
            total_pad_probes++;
            $display("PASS mux combinational public pad probe div=%0d kind=%0d phases=%0d",d,probe,pad_probe_hits);
        end
        if(total_pad_probes!=6) $fatal(1,"six combinational pad fixtures missing");
        $display("PASS rqak-mux-yield actual chain: %0d profiles; separate pad fixtures=%0d; no-request comparison >=200 per63functionalprofiles",profiles,total_pad_probes);
        $finish;
    end
endmodule
