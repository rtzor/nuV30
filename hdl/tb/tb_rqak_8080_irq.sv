// SPDX-License-Identifier: GPL-2.0-only
// Fixed native/8080 IRQ ownership regression; no NEC pin-timing claim.
module tb_rqak_8080_irq;
    logic clk=0, reset=1, bkd_load=0, pin_int=0;
    logic [223:0] seed=0;
    logic [1:0] remote_low=0;
    wire [1:0] request, drive_low, external_grant, protocol_error, grant;
    wire [1:0] resolved_n=~(remote_low|drive_low);
    wire core_ce, core_half, bus_enable, quiet, exclude, rd, ube, buslock;
    wire [19:0] address;
    wire [15:0] data_out;
    wire [15:0] unused_ss_rdata;
    wire unused_ss_err, unused_dbg_first_pop, unused_dbg_pend;
    logic [15:0] data_in;
    wire [3:0] status;
    wire [2:0] bs;
    wire [1:0] qs;
    wire [223:0] regs;
    logic [7:0] mem[0:65535];
    integer phase=0, cycle_kind=7, cycle_address=0, waits_left=0;
    integer wait_mode=0, writes=0, reads=0, intas=0, profiles=0;
    integer decision_seen=0, entry_seen=0, gap_seen=0, frozen=0, emu_decision_seen=0;
    logic cycle_ube=1, ready, emu_case=0, irq_started=0;
    logic [223:0] frozen_regs;
    logic [47:0] frozen_bus;
    wire [47:0] public_bus={address,data_out,status,bs,rd,ube,qs,buslock};
    wire entry_active=cpu.u_eu.upc_page==3'd7 &&
        cpu.u_eu.st>=6'd22 && cpu.u_eu.st<=6'd29;
    wire exclusion_law=(!cpu.u_eu.mode8080 && cpu.u_eu.lock_pfx) ||
        cpu.u_eu.st==6'd32 || entry_active;
    v30_rqak_frontend frontend(.CLK(clk),.RESET(reset),.CE(1'b1),
        .RQAK_I_N(resolved_n),.INTERNAL_GRANT(grant),.REQUEST(request),
        .RQAK_DRIVE_LOW(drive_low),.EXTERNAL_GRANT(external_grant),
        .PROTOCOL_ERROR(protocol_error));
    v30_bus_ownership arb(.CLK(clk),.RESET(reset),.CE(1'b1),.CE_HALF(1'b0),
        .REQUEST(request),.CORE_QUIET(quiet),.EXCLUDE(exclude),.GRANT(grant),
        .CORE_CE(core_ce),.CORE_CE_HALF(core_half),.CORE_BUS_ENABLE(bus_enable));
    v30_core cpu(.CLK(clk),.CE(core_ce),.RESET(reset),.READY(ready),
        .INT(pin_int),.NMI(1'b0),.POLL_N(1'b1),.DATA_I(data_in),
        .ADDR_O(address),.DATA_O(data_out),.STATUS_O(status),.QS(qs),.BS(bs),
        .RD_N(rd),.UBE_N(ube),.BUSLOCK_N(buslock),.BUS_EXCLUDE(exclude),
        .SS_ADDR('0),.SS_WDATA('0),.SS_WE(1'b0),.SS_RDATA(unused_ss_rdata),.SS_ERR(unused_ss_err),
        .SS_BUS_QUIET(quiet),.bkd_load(bkd_load),.bkd_regs(seed),
        .bkd_queue('0),.bkd_qlen('0),.bkd_fetch_ip('0),.scr_en(1'b0),
        .scr_qop('0),.dbg_regs(regs),.dbg_first_pop(unused_dbg_first_pop),.dbg_pend(unused_dbg_pend));
    always_comb begin
        ready=waits_left==0;
        data_in=!bus_enable ? 16'h0000 : cycle_kind==0 ? 16'h0020 :
            {mem[{address[15:1],1'b1}],mem[{address[15:1],1'b0}]};
    end
    // Expected data/address lists are literal program/frame laws, never DUT PCs.
    task automatic expected_write(input integer index, output integer at,
                                   output logic [15:0] value);
        at=-1; value=0;
        if(emu_case) case(index)
            0:begin at='h7fe;value=16'hf202;end
            1:begin at='h7fc;value=0;end
            2:begin at='h7fa;value=3;end
            3:begin at='h7f8;value=16'h7202;end
            4:begin at='h7f6;value=0;end
            5:begin at='h7f4;value=16'h0101;end
            6:begin at='h600;value=16'h1234;end
            default:begin end
        endcase
        else case(index)
            0:begin at='h7fe;value=16'hf202;end
            1:begin at='h7fc;value=0;end
            2:begin at='h7fa;value=1;end
            3:begin at='h600;value=16'h1234;end
            default:begin end
        endcase
    endtask
    task automatic expected_read(input integer index, output integer at,
                                  output logic [15:0] value);
        at=-1; value=0;
        if(emu_case) case(index)
            0:begin at='h180;value=16'h0100;end
            1:begin at='h182;value=0;end
            2:begin at='h080;value=16'h0200;end
            3:begin at='h082;value=0;end
            4:begin at='h7f4;value=16'h0101;end
            5:begin at='h7f6;value=0;end
            6:begin at='h7f8;value=16'h7202;end
            7:begin at='h7fa;value=3;end
            8:begin at='h7fc;value=0;end
            9:begin at='h7fe;value=16'hf202;end
            default:begin end
        endcase
        else case(index)
            0:begin at='h080;value=16'h0200;end
            1:begin at='h082;value=0;end
            2:begin at='h7fa;value=1;end
            3:begin at='h7fc;value=0;end
            4:begin at='h7fe;value=16'hf202;end
            default:begin end
        endcase
    endtask
    task automatic tick;
        logic sampled_ce, sampled_enable, consume_wait;
        integer expected_address;
        logic [15:0] expected_value;
        #1;
        sampled_ce=core_ce;sampled_enable=bus_enable;consume_wait=0;
        if(!reset)begin
            if(exclude!==exclusion_law)$fatal(1,"IRQ guard equation mismatch");
            if(irq_started)begin
                if(cpu.u_eu.st==6'd32)begin
                    decision_seen++;
                    if(cpu.u_eu.mode8080)emu_decision_seen++;
                end
                if(entry_active)entry_seen++;
                if(intas==1&&bs==7)begin
                    gap_seen++;
                    if(!exclude)$fatal(1,"INTA gap lost exclusion");
                end
            end
            if((|grant)&&exclude)$fatal(1,"grant inside excluded interval");
            if((|grant)&&intas!=2)$fatal(1,"grant before complete acknowledge pair");
            if(|protocol_error)$fatal(1,"unexpected RQAK protocol error");
        end
        if(reset)begin phase=0;waits_left=0;writes=0;reads=0;intas=0;cycle_kind=7;end
        else if(core_ce)begin
            if(phase==0||phase==5)begin
                if(bs!=7)begin
                    phase=1;cycle_kind=int'(bs);cycle_address=int'(address[15:0]);
                    waits_left=wait_mode;
                end else phase=0;
            end else if(phase==1||phase==2)begin
                if(phase==1)begin
                    cycle_ube=ube;
                    if((cycle_kind==4||cycle_kind==5||cycle_kind==6)&&address[19:16]!=0)
                        $fatal(1,"unexpected nonzero memory segment address BS=%0d address=%05x modeled_phase=%0d actual_r_ts=%0d",cycle_kind,address,phase,cpu.u_biu.r_ts);
                    if(cycle_kind==0&&address!==20'h00000)
                        $fatal(1,"INTA must publish zero address BS=%0d address=%05x modeled_phase=%0d actual_r_ts=%0d",cycle_kind,address,phase,cpu.u_biu.r_ts);
                    if(cycle_kind==3)
                        $display("OBS HALT retention BS=%0d address=%05x modeled_phase=%0d actual_r_ts=%0d",cycle_kind,address,phase,cpu.u_biu.r_ts);
                end
                phase++;
            end else if((phase==3||phase==4)&&!ready)begin phase=4;consume_wait=1;end
            else begin
                phase=5;
                if(cycle_kind==0)intas++;
                if(cycle_kind==5)begin
                    expected_read(reads,expected_address,expected_value);
                    if(cycle_address!=expected_address||cycle_ube||data_in!==expected_value)
                        $fatal(1,"literal IVT/IRET/RETEM read mismatch index=%0d",reads);
                    reads++;
                end
                if(cycle_kind==6)begin
                    expected_write(writes,expected_address,expected_value);
                    if(cycle_address!=expected_address||cycle_ube||data_out!==expected_value)
                        $fatal(1,"literal frame/marker write mismatch index=%0d",writes);
                    mem[cycle_address]=data_out[7:0];mem[cycle_address+1]=data_out[15:8];
                    writes++;
                end
            end
        end
        if(consume_wait&&waits_left>0)waits_left--;
        if(intas==2)pin_int=0;
        #1 clk=1;#1 clk=0;
        if(!reset&&(|grant))begin
            if(sampled_ce&&frozen==0)$fatal(1,"acquisition edge advanced core");
            if(!quiet)$fatal(1,"grant without quiet boundary");
            if(frozen==0)begin frozen_regs=regs;frozen_bus=public_bus;end
            else if(regs!==frozen_regs||public_bus!==frozen_bus)
                $fatal(1,"owned core or public bus changed");
            frozen++;
        end
        if(!reset&&!sampled_enable&&sampled_ce)$fatal(1,"isolated core advanced");
    endtask
    task automatic setup(input logic emulation,input integer delay_clocks);
        reset=1;bkd_load=1;pin_int=0;remote_low=0;emu_case=emulation;
        irq_started=0;decision_seen=0;entry_seen=0;gap_seen=0;frozen=0;emu_decision_seen=0;
        wait_mode=delay_clocks;seed=0;seed[0+:16]=16'h1234;
        seed[64+:16]=16'h0800;seed[208+:16]=16'h0202;
        for(integer j=0;j<65536;j++)mem[j]=8'h90;
        mem['h80]=0;mem['h81]=2;mem['h82]=0;mem['h83]=0;mem['h200]=8'hcf;
        if(emulation)begin
            mem[0]=8'h0f;mem[1]=8'hff;mem[2]=8'h60;
            mem[3]=8'ha3;mem[4]=0;mem[5]=6;mem[6]=8'hf4;
            mem['h180]=0;mem['h181]=1;mem['h182]=0;mem['h183]=0;
            mem['h100]=8'h76;
            for(integer j=1;j<=16;j++)mem['h100+j]=0;
            mem['h111]=8'hed;mem['h112]=8'hfd;
        end else begin
            mem[0]=8'hf4;
            for(integer j=1;j<=16;j++)mem[j]=8'h90;
            mem['h11]=8'ha3;mem['h12]=0;mem['h13]=6;mem['h14]=8'hf4;
        end
        repeat(4)tick();reset=0;bkd_load=0;
    endtask
    task automatic run_profile(input logic emulation,input integer point,
                               input integer delay_clocks);
        integer n;
        logic target;
        setup(emulation,delay_clocks);n=0;
        while(cpu.u_eu.st!=6'd30&&n<4096)begin tick();n++;end
        if(n==4096)$fatal(1,"initial HLT not reached");
        pin_int=1;irq_started=1;n=0;target=0;
        while(!target&&n<4096)begin
            target=point==0 ? cpu.u_eu.st==6'd32 : point==1 ?
                entry_active : intas==1&&bs==7;
            if(!target)begin tick();n++;end
        end
        if(!target||!exclude)$fatal(1,"fixed IRQ request cut absent");
        remote_low=1;tick();remote_low=0;tick();n=0;
        while(external_grant!=1&&n<8192)begin tick();n++;end
        if(n==8192)$fatal(1,"excluded request never released");
        repeat(32)tick();
        if(frozen<32)$fatal(1,"owned snapshot bar absent");
        tick();tick();remote_low=1;tick();remote_low=0;tick();n=0;
        while((|grant)&&n<128)begin tick();n++;end
        if(n==128)$fatal(1,"return release watchdog");
        n=0;
        while(!(cpu.u_eu.st==6'd30&&writes==(emulation?7:4))&&n<8192)begin tick();n++;end
        if(n==8192||reads!=(emulation?10:5)||intas!=2||
           {mem['h601],mem['h600]}!=16'h1234||regs[0+:16]!=16'h1234||
           regs[64+:16]!=16'h0800||regs[144+:16]!=0||
           regs[192+:16]!=(emulation?16'h0007:16'h0015)||
           regs[208+:16]!=16'hf202||cpu.u_eu.mode8080||
           decision_seen==0||entry_seen==0||gap_seen==0||
           (emulation&&emu_decision_seen==0)||(!emulation&&emu_decision_seen!=0))
            $fatal(1,"fixed IRQ frame/IRET/RETEM/end or coverage mismatch");
        profiles++;
        $display("PASS rqak forced-native IRQ emu=%0d point=%0d waits=%0d writes=%0d reads=%0d frozen=%0d",emulation,point,delay_clocks,writes,reads,frozen);
    endtask
    initial begin
        integer selected_profile;
        logic selection_present;
        string selected_argument;
        selected_profile=-1;
        selection_present=$test$plusargs("profile=");
        if(selection_present)begin
            if(!$value$plusargs("profile=%s",selected_argument)||
               !$value$plusargs("profile=%d",selected_profile)||
               selected_profile<0||selected_profile>17||
               selected_argument!=$sformatf("%0d",selected_profile))
                $fatal(1,"profile must be canonical decimal 0..17");
        end
        for(integer e=0;e<2;e++)for(integer p=0;p<3;p++)for(integer w=0;w<3;w++)
            if(!selection_present||selected_profile==9*e+3*p+w)
                run_profile(e!=0,p,w==2?3:w);
        if(profiles!=(selection_present?1:18))$fatal(1,"fixed profile count mismatch");
        $display("PASS rqak native and 8080 forced-native IRQ: fixed profiles=%0d selected=%0d",profiles,selected_profile);
        $finish;
    end
endmodule
