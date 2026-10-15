`timescale 1ns/1ps
module tb_8080_final53;
import v30_ss_pkg::*;
logic clk,rig_reset,int_req,nmi_req;
always #10 clk=~clk;
integer waits;
logic ss_we;
logic [8:0] ss_addr;
logic [15:0] ss_wdata;
wire [15:0] ss_rdata;
wire ss_err,ss_quiet;
wire ce,half_ce,core_reset,rig_ready,core_int,core_nmi,core_poll;
logic cadence_fault;
wire core_ce=ce||cadence_fault;
wire [19:0] addr,mem_addr;
wire [15:0] data_out,ad_drive,mem_wdata;
logic [15:0] mem_rdata;
wire [3:0] status;
wire [2:0] bs,mem_kind;
wire [1:0] qs,mem_be;
wire lock_n,ube_n,rd_n,ad_drive_en,mem_wr_req,cap_valid,cpu_running;
wire [63:0] cap_record;
wire [19:0] observed_ad;
logic [19:0] pad_hold;
logic withdraw_active;
wire actual_ready=rig_ready&&!withdraw_active;
logic [7:0] ram[0:1048575],mirror[0:1048575];

v30_core dut(.CLK(clk),.CE(core_ce),.RESET(core_reset),.READY(actual_ready),
 .INT(core_int),.NMI(core_nmi),.POLL_N(core_poll),.DATA_I(core_read_data),
 .ADDR_O(addr),.DATA_O(data_out),.STATUS_O(status),.QS(qs),.BS(bs),.RD_N(rd_n),
 .UBE_N(ube_n),.BUSLOCK_N(lock_n),.SS_ADDR(ss_addr),.SS_WDATA(ss_wdata),.SS_WE(ss_we),
 .SS_RDATA(ss_rdata),.SS_ERR(ss_err),.SS_BUS_QUIET(ss_quiet));

// Engineering transcoder for the declared demux profile, not native pad fidelity.
// The real nec_bus T-state tracker defines the external address half: public
// ADDR is held for ALL T1, including the SYS preceding tick_fall's old-ad_in_q
// latch. Public DATA drives write bodies; rig read data drives other read halves.
// No private BIU ad_o or ad_oe_* formatting participates in this adapter.
wire adapter_t1=rig.t_state==3'd1;
wire adapter_body=rig.t_state>=3'd2&&rig.t_state<=3'd5;
wire adapter_write=adapter_body&&(mem_kind==3'd6||mem_kind==3'd2);
wire [15:0] core_read_data=ad_drive_en?ad_drive:16'h0000;
assign observed_ad={adapter_t1?addr[19:16]:(adapter_body?status:pad_hold[19:16]),
 adapter_t1?addr[15:0]:(ad_drive_en?ad_drive:(adapter_write?data_out:pad_hold[15:0]))};
always @(posedge clk)begin
 if(adapter_t1||adapter_body)pad_hold[19:16]<=observed_ad[19:16];
 if(adapter_t1||ad_drive_en||adapter_write)pad_hold[15:0]<=observed_ad[15:0];
end
logic [19:0] adapter_owner_addr;
logic [1:0] adapter_owner_be;
logic adapter_owner_valid;
logic [2:0] adapter_announced_kind,adapter_owner_kind;
logic adapter_announced_valid;
integer adapter_owner_seq,public_owner_used_seq;
// The reference owning address/BE is sampled from PUBLIC ports, not RAM results.
always @(posedge clk)begin : check_external_address_and_read
 logic check_address,check_read;
 logic [19:0] expected_addr;
 logic [1:0] expected_be;
 logic [15:0] expected_read;
 check_address=!core_reset&&half_ce&&adapter_t1;
 check_read=!core_reset&&ce&&dut.u_biu.r_run&&dut.u_biu.r_ts==3'd2&&
  !dut.u_biu.r_cur_wr&&!dut.u_biu.r_cur_halt;
 expected_addr=addr;expected_be={!ube_n,!addr[0]};
 expected_read=(mem_kind==3'd0)?16'h0020:(mem_kind==3'd1)?
  (adapter_owner_addr[0]?{io_read_byte,8'h69}:{8'h96,io_read_byte}):
  {ram[{adapter_owner_addr[19:1],1'b1}],ram[{adapter_owner_addr[19:1],1'b0}]};
 if(core_reset)begin
  adapter_owner_valid<=0;adapter_announced_valid<=0;adapter_announced_kind<=3'd7;adapter_owner_kind<=3'd7;adapter_owner_seq<=0;
 end else if(ce&&rig.next_t_state==3'd1)begin
  // bs_q is the registered PUBLIC NEC_BS announcement used by nec_bus.
  adapter_announced_kind<=rig.bs_q;adapter_announced_valid<=1;
 end
 if(check_address)begin
  if(!adapter_announced_valid||adapter_announced_kind==3'd7||rig.ad_in_q!==expected_addr||rig.ube_n_q!==ube_n)
   $fatal(1,"FIXTURE_PUBLIC_ADDRESS_SAMPLE_FAIL");
  adapter_owner_addr<=expected_addr;adapter_owner_be<=expected_be;adapter_owner_valid<=1;
  adapter_owner_kind<=adapter_announced_kind;adapter_owner_seq<=adapter_owner_seq+1;
  $display("PUBLIC_ADDRESS_ANCHOR sys=%0d addr=%05x be=%b sample=%05x kind=%0d",sys,expected_addr,expected_be,rig.ad_in_q,adapter_announced_kind);
 end
 if(check_read)begin
  if(!adapter_owner_valid||adapter_owner_kind!==mem_kind||mem_addr!==adapter_owner_addr||mem_be!==adapter_owner_be)
   $fatal(1,"FIXTURE_READ_OWNING_ADDRESS_FAIL");
  if(!ad_drive_en||core_read_data!==expected_read||dut.u_biu.ad_i!==expected_read)
   $fatal(1,"FIXTURE_PUBLIC_READ_DATA_FAIL");
  $display("PUBLIC_READ_ANCHOR sys=%0d addr=%05x kind=%0d DATA_I=%04x",sys,adapter_owner_addr,mem_kind,expected_read);
 end
 #1;
 if(check_address&&(mem_addr!==expected_addr||mem_be!==expected_be))
  $fatal(1,"FIXTURE_RIG_ADDRESS_LATCH_FAIL");
 if(check_read&&dut.u_biu.r_cur_data!==expected_read)
  $fatal(1,"FIXTURE_CORE_T2_READ_LATCH_FAIL");
end
logic [9:0] unused_wvec_addr;
logic [6:0] unused_iords_addr;
logic unused_evt_fired;
logic unused_vec_used;
logic unused_nec_clk;
logic unused_enable_n;
logic unused_power_good;
nec_bus #(.EVT_N(1)) rig(.clk(clk),.reset(rig_reset),.cfg_small_mode(1'b0),
 .cfg_cpu_off(1'b0),.cfg_short_pwrup(1'b1),.cfg_clk_div(6'd5),
 .cfg_wait_states(4'(waits)),.cfg_int_vector(8'h20),.cfg_wait_rand(1'b0),
 .cfg_wmax(4'd0),.cfg_wseed(16'h0001),.cfg_wait_replay(1'b0),
 .wvec_raddr(unused_wvec_addr),.wvec_rdata(32'd0),.iords_raddr(unused_iords_addr),.int_req(int_req),.nmi_req(nmi_req),
 .poll_n_in(1'b1),.evt_arm(1'b0),.evt_addr(20'd0),.evt_delay(16'd0),
 .evt_hold(12'd0),.evt_pin(3'd0),.evt_vecsub_en(1'b0),.evt_fired(unused_evt_fired),
 .cfg_tvec(32'd0),.vec_used(unused_vec_used),.ad_drive(ad_drive),.ad_drive_en(ad_drive_en),
 .ad_sample(observed_ad),.NEC_CLK(unused_nec_clk),.NEC_POLL_N(core_poll),.NEC_READY(rig_ready),
 .NEC_RESET(core_reset),.NEC_INT(core_int),.NEC_NMI(core_nmi),.NEC_QS(qs),.NEC_BS(bs),
 .NEC_BUSLOCK_N(lock_n),.NEC_UBE_N(ube_n),.NEC_RD_N(rd_n),.NEC_ENABLE_N(unused_enable_n),
 .mem_addr(mem_addr),.mem_cycle_type(mem_kind),.mem_rdata(mem_rdata),
 .mem_wr_req(mem_wr_req),.mem_wdata(mem_wdata),.mem_be(mem_be),
 .cap_valid(cap_valid),.cap_record(cap_record),.cpu_running(cpu_running),.pwr_good_o(unused_power_good),
 .tick_rise_o(ce),.tick_fall_o(half_ce));
always_comb mem_rdata=(mem_kind==3'd1)?(mem_addr[0]?{io_read_byte,8'h69}:{8'h96,io_read_byte}):{ram[{mem_addr[19:1],1'b1}],ram[{mem_addr[19:1],1'b0}]};


// Selected literal input. No expected value is computed from DUT state.
logic [16383:0] selected_record[0:0];
string record_file;
function automatic [15:0] w(input integer index);
 w=selected_record[0][index*16+:16];
endfunction
integer sys,accepted,case_id,population,selected_opcode,family,event_kind,event_point;
integer native_ip,emu_ip,native_cs,emu_cs,frame_sp,return_ip,final_pc,retem_pc;
integer expected_owned,owned_count,read_count,write_count,ram_read_stage,public_read_stage;
integer ram_write_stage,public_write_stage,ram_read_mask,public_read_mask,ram_write_mask,public_write_mask;
integer target_rows,halt_age,finish_age,inta_count,isr_count,event_sys,reset_age;
integer expected_inta,expected_irq,reset_case,halt_required;
logic [7:0] io_read_byte;
logic [15:0] native_psw,entry_psw,expected_flags,flags_mask;
logic [15:0] pre_gpr[0:7],final_gpr[0:7],native_sreg[0:3],emu_sreg[0:3];
logic pre_valid,entry_frame_seen,retem_seen,returned,event_issued,isr_owned;
logic entry_flush,return_flush,native_hlt_owned,public_seen,reset_seen,reset_fetch_seen;
logic previous_mode,accepted_ce_snapshot;
logic masked_wake_seen,int_withdrawn;
integer irq_restart,irq_owned_cursor;
logic irq_snapshot,irq_resumed;
logic halt_announced,halt_parked,first_successor_complete;
integer halt_owner_seq,halt_owned_count,masked_int_cpu_age,masked_int_wait_age;

task automatic score_group(input logic reading,input logic public_side,input integer space,
 input logic [19:0] address,input logic [15:0] value,input logic [1:0] lanes);
 integer stage,mask,base,width,phase,index,matched;
 logic [7:0] expected_byte;
 logic [19:0] byte_address,expected_address;
 begin
 stage=reading?(public_side?public_read_stage:ram_read_stage):(public_side?public_write_stage:ram_write_stage);
 mask=reading?(public_side?public_read_mask:ram_read_mask):(public_side?public_write_mask:ram_write_mask);
 if(stage>=(reading?read_count:write_count)||lanes==0)$fatal(1,"F53_ORACLE_UNEXPECTED_BUS_GROUP");
 base=(reading?448:672)+stage*9;width=int'(w(base+7));phase=(int'(w(base+8))&32'h000000ff);
 if(reading)begin
  if(ram_write_stage<(int'(w(base+8))>>8)||public_write_stage<(int'(w(base+8))>>8))$fatal(1,"F53_ORACLE_READ_BEFORE_REQUIRED_WRITE");
 end else if(ram_read_stage<(int'(w(base+8))>>8)||public_read_stage<(int'(w(base+8))>>8))$fatal(1,"F53_ORACLE_WRITE_BEFORE_REQUIRED_READ");
 if(int'(w(base))!=space)$fatal(1,"F53_ORACLE_MEMORY_IO_CLASS");
 if(phase==0&&reading)begin
  if(pre_valid||entry_frame_seen||dut.u_eu.mode8080||dut.u_eu.md_write_enabled||dut.u_eu.pc!==16'(return_ip)||dut.u_eu.flags_rd!==native_psw)$fatal(1,"F53_PROTO_IVT_NATIVE_PHASE");
  for(integer k=0;k<8;k=k+1)if(dut.u_eu.gpr[k]!==pre_gpr[k])$fatal(1,"F53_PROTO_IVT_NATIVE_GPR");
  for(integer k=0;k<4;k=k+1)if(dut.u_eu.sreg[k]!==native_sreg[k])$fatal(1,"F53_PROTO_IVT_NATIVE_SREG");
 end
 if(phase==1&&(!entry_frame_seen||retem_seen||!dut.u_eu.mode8080))$fatal(1,"F53_ORACLE_OPERAND_PHASE");
 if((phase==2||phase==3)&&(!event_issued||expected_irq!=1||retem_seen))$fatal(1,"F53_ORACLE_IRQ_BUS_PHASE");
 if(phase==3&&(!isr_owned||dut.u_eu.mode8080))$fatal(1,"F53_ORACLE_IRET_PHASE");
 if(phase==4&&(!entry_frame_seen||!retem_seen))$fatal(1,"F53_ORACLE_RETEM_READ_PHASE");
 if(phase==5&&(!returned||!retem_seen||ram_read_stage!=read_count||public_read_stage!=read_count))$fatal(1,"F53_ORACLE_MARKER_PHASE");
 for(integer lane=0;lane<2;lane=lane+1)if(lanes[lane])begin
  byte_address={address[19:1],1'b0}+20'(lane);matched=0;
  for(index=0;index<width;index=index+1)begin
   expected_address={4'(w(base+2+index*2)),w(base+1+index*2)};
   if(byte_address==expected_address&&(mask&(1<<index))==0)begin
    expected_byte=8'(w(base+5+index));
    if(expected_irq==1&&(selected_opcode==32'd243||selected_opcode==32'd251)&&
       ((!reading&&phase==2&&stage==5)||(reading&&phase==3&&stage==4)))begin
     if(!irq_snapshot)$fatal(1,"F53_PROTO_IRQ_PC_WITHOUT_BOUNDARY");
     expected_byte=8'(irq_restart>>(index*8));
    end
    if(value[8*lane+:8]!==expected_byte)begin
     $display("F53_BUS_MISMATCH read=%b public=%b group=%0d addr=%05x data=%04x lanes=%b expected_byte=%02x",reading,public_side,stage,address,value,lanes,expected_byte);
     $fatal(1,"F53_ORACLE_BUS_BYTE");
    end
    mask=mask|(1<<index);matched=matched+1;
    if(!reading&&public_side&&space==0)mirror[byte_address]=value[8*lane+:8];
   end
  end
  if(matched!=1)$fatal(1,"F53_ORACLE_BUS_OWNING_ADDRESS");
 end
 if(mask==((1<<width)-1))begin stage=stage+1;mask=0;end
 if(reading)begin
  if(public_side)begin public_read_stage=stage;public_read_mask=mask;end
  else begin ram_read_stage=stage;ram_read_mask=mask;end
 end else begin
  if(public_side)begin public_write_stage=stage;public_write_mask=mask;end
  else begin ram_write_stage=stage;ram_write_mask=mask;end
 end
 $display("F53_BUS_GROUP read=%b public=%b space=%0d addr=%05x data=%04x lanes=%b next=%0d mask=%0d phase=%0d",reading,public_side,space,address,value,lanes,stage,mask,phase);
 end
endtask

task automatic final_memory_and_coverage;
 begin
 if(ram_read_stage!=read_count||public_read_stage!=read_count||ram_write_stage!=write_count||public_write_stage!=write_count||ram_read_mask!=0||public_read_mask!=0||ram_write_mask!=0||public_write_mask!=0)$fatal(1,"F53_ORACLE_BUS_COVERAGE");
 if(owned_count!=expected_owned||target_rows==0||inta_count!=expected_inta||isr_count!=expected_irq)$fatal(1,"F53_ORACLE_EXECUTION_COVERAGE");
 for(integer j=0;j<1048576;j=j+1)if(ram[j]!==mirror[j])$fatal(1,"F53_ORACLE_FULL_RAM_MIRROR");
 end
endtask

initial begin
 clk=0;rig_reset=1;int_req=0;nmi_req=0;ss_we=0;ss_addr=0;ss_wdata=0;cadence_fault=0;withdraw_active=0;pad_hold=0;
 sys=0;accepted=0;owned_count=0;public_owner_used_seq=0;ram_read_stage=0;public_read_stage=0;ram_write_stage=0;public_write_stage=0;
 ram_read_mask=0;public_read_mask=0;ram_write_mask=0;public_write_mask=0;target_rows=0;halt_age=0;finish_age=0;inta_count=0;isr_count=0;event_sys=0;reset_age=0;
 pre_valid=0;entry_frame_seen=0;retem_seen=0;returned=0;event_issued=0;isr_owned=0;entry_flush=0;return_flush=0;native_hlt_owned=0;public_seen=0;reset_seen=0;reset_fetch_seen=0;previous_mode=0;masked_wake_seen=0;int_withdrawn=0;
 irq_restart=0;irq_owned_cursor=0;irq_snapshot=0;irq_resumed=0;
 halt_announced=0;halt_parked=0;first_successor_complete=0;halt_owner_seq=0;halt_owned_count=0;masked_int_cpu_age=0;masked_int_wait_age=0;
 case_id=-1;population=-1;
 if($value$plusargs("case_id=%d",case_id))begin end
 if($value$plusargs("population=%d",population))begin end
 if(!$value$plusargs("record=%s",record_file)||case_id<0||population<0||population>3)$fatal(1,"F53_PROTO_CASE_ARGS");
 $readmemh(record_file,selected_record);
 if(w(0)!==16'hf053||w(1)!==16'd1||w(2)!==16'(population)||w(3)!==16'(case_id)||w(1023)!==16'hf35a)$fatal(1,"F53_PROTO_LITERAL_BINDING");
 selected_opcode=int'(w(4));family=int'(w(5));waits=int'(w(6));event_kind=int'(w(7));event_point=int'(w(8));expected_irq=int'(w(9));expected_inta=int'(w(10));reset_case=int'(w(11));
 native_ip=int'(w(12));emu_ip=int'(w(13));native_cs=int'(w(14));emu_cs=int'(w(15));frame_sp=int'(w(20));native_psw=w(21);entry_psw=w(22);flags_mask=w(23);expected_flags=w(24);retem_pc=int'(w(25));
 expected_owned=int'(w(26));read_count=int'(w(27));write_count=int'(w(28));return_ip=int'(w(31));final_pc=int'(w(33));halt_required=int'(w(34));io_read_byte=8'(w(36));
 if(expected_owned<1||expected_owned>32||read_count<2||read_count>24||write_count<3||write_count>24||w(29)>85||waits>3||event_kind>3||event_point>4)$fatal(1,"F53_PROTO_LITERAL_LIMIT");
 if(selected_opcode==32'd118)begin
  for(integer k=0;k<expected_owned;k=k+1)
   if(w(128+k*2)==16'(w(38)-16'd1)&&w(129+k*2)==16'h0076)begin
    if(halt_owned_count!=0)$fatal(1,"F53_PROTO_HALT_LITERAL_OWNER");
    halt_owned_count=k+1;
   end
  if(halt_owned_count<1)$fatal(1,"F53_PROTO_HALT_LITERAL_OWNER");
 end
 for(integer k=0;k<8;k=k+1)begin pre_gpr[k]=w(40+k);final_gpr[k]=w(48+k);end
 for(integer k=0;k<4;k=k+1)begin native_sreg[k]=w(56+k);emu_sreg[k]=w(60+k);end
 for(integer j=0;j<1048576;j=j+1)ram[j]=0;
 for(integer j=0;j<int'(w(29));j=j+1)ram[{4'(w(193+j*3)),w(192+j*3)}]=8'(w(194+j*3));
 for(integer j=0;j<int'(w(30));j=j+1)ram[20'(native_cs*16+native_ip+j)]=8'(w(64+j));
 for(integer j=0;j<1048576;j=j+1)mirror[j]=ram[j];
 $display("F53_CASE population=%0d id=%0d opcode=%02x family=%0d waits=%0d event=%0d point=%0d expected_owned=%0d reads=%0d writes=%0d reset=%0d",population,case_id,selected_opcode,family,waits,event_kind,event_point,expected_owned,read_count,write_count,reset_case);
 repeat(8)@(negedge clk);rig_reset=0;
end

always @(posedge clk)begin
 accepted_ce_snapshot=ce&&!core_reset;sys<=sys+1;
 $display("F53_SYS_PRE n=%0d CE=%b HALF=%b RESET=%b READY=%b PC=%04x st=%0d UPC=%0d.%02x.%0d GPR=%04x,%04x,%04x,%04x,%04x,%04x,%04x,%04x FLAGS=%04x MODE=%b SESSION=%b OPC8080=%b PE8080=%b POSTE=%b Q=%02x POP=%b RIPE=%b FLUSH=%b ADDR=%05x DATA=%04x STATUS=%x BS=%0d UBE=%b RD=%b LOCK=%b MEMADDR=%05x MEMDATA=%04x BE=%b MEMWR=%b INT=%b NMI=%b",sys,ce,half_ce,core_reset,actual_ready,dut.u_eu.pc,dut.u_eu.st,dut.u_eu.upc_page,dut.u_eu.upc_opc,dut.u_eu.upc_loc,dut.u_eu.gpr[0],dut.u_eu.gpr[1],dut.u_eu.gpr[2],dut.u_eu.gpr[3],dut.u_eu.gpr[4],dut.u_eu.gpr[5],dut.u_eu.gpr[6],dut.u_eu.gpr[7],dut.u_eu.flags_rd,dut.u_eu.mode8080,dut.u_eu.md_write_enabled,dut.u_eu.opc8080,dut.u_eu.pe_opc8080,dut.u_eu.poste,dut.q_byte,dut.eu_pop,dut.q_ripe,dut.eu_flush,addr,data_out,status,bs,ube_n,rd_n,lock_n,mem_addr,mem_wdata,mem_be,mem_wr_req,core_int,core_nmi);
 // Snapshot every SYS, including non-CE intervals. T-state metadata is the public rig tracker.
 if(selected_opcode==32'd118&&entry_frame_seen&&!retem_seen)
  $display("F53_HLT_MON sys=%0d CE=%b T=%0d NEXT=%0d BSQ=%0d BS=%0d RD=%b UBE=%b INT=%b RESET=%b owned=%0d OWNER=%0d SEQ=%0d",sys,ce,rig.t_state,rig.next_t_state,rig.bs_q,bs,rd_n,ube_n,core_int,core_reset,owned_count,adapter_owner_kind,adapter_owner_seq);
 // RESET wins over standby checking and counting; historical raw anchors remain retained.
 if(core_reset)begin halt_parked=0;halt_age=0;masked_int_cpu_age=0;masked_int_wait_age=0;end
 else if(halt_parked&&!event_issued)begin
  if(bs!==3'd7||rd_n!==1'b1||ube_n!==1'b1)$fatal(1,"F53_ORACLE_PUBLIC_HALT");
  if(dut.u_eu.st!==6'd30||dut.u_eu.pc!==w(38)||!dut.u_eu.mode8080||!dut.u_eu.md_write_enabled||owned_count!=halt_owned_count)$fatal(1,"F53_ORACLE_HALT_PARKED_STATE");
 end
 if(!core_reset&&ce)begin
  if(event_kind==1&&expected_irq==0&&event_point==4&&event_issued&&!int_withdrawn)begin
   if(int_req!==1'b1||core_int!==1'b1)$fatal(1,"F53_PROTO_MASKED_HALT_INT_PULSE");
   masked_int_cpu_age=masked_int_cpu_age+1;
   if(rig.t_state==3'd4)masked_int_wait_age=masked_int_wait_age+1;
  end
  if(!dut.u_eu.mode8080&&dut.u_eu.mode8080_commit&&!pre_valid)begin
   for(integer k=0;k<8;k=k+1)if(dut.u_eu.gpr[k]!==pre_gpr[k])$fatal(1,"F53_PROTO_NATIVE_PREP_GPR");
   for(integer k=0;k<4;k=k+1)if(dut.u_eu.sreg[k]!==native_sreg[k])$fatal(1,"F53_PROTO_NATIVE_PREP_SREG");
   if(dut.u_eu.flags_rd!==native_psw||dut.u_eu.pc!==16'(return_ip))$fatal(1,"F53_PROTO_NATIVE_PREP_FLAGS_PC");
   pre_valid=1;$display("F53_NATIVE_PREP FLAGS=%04x PC=%04x",dut.u_eu.flags_rd,dut.u_eu.pc);
  end
  // IRQ_D follows a taken boundary before a new qpop; pre-popped opcodes execute first.
  if(expected_irq==1&&(selected_opcode==32'd243||selected_opcode==32'd251)&&dut.u_eu.st==32)begin
   if(irq_snapshot||!event_issued||!entry_frame_seen||retem_seen||isr_owned||
      !dut.u_eu.mode8080||dut.u_eu.opc_valid||dut.eu_pop||owned_count<1||owned_count>=expected_owned-2||
      w(129+owned_count*2)!==16'h0000||(selected_opcode==32'd251&&event_kind==1&&owned_count<2))$fatal(1,"F53_PROTO_IRQ_BOUNDARY_OWNER");
   irq_owned_cursor=owned_count;irq_restart=int'(w(128+owned_count*2));irq_snapshot=1;
   if(dut.u_eu.pc!==16'(irq_restart))$fatal(1,"F53_ORACLE_IRQ_BOUNDARY_PC");
   $display("F53_IRQ_BOUNDARY next_owned=%0d restart=%04x",irq_owned_cursor,16'(irq_restart));
  end
  if(dut.eu_pop&&dut.q_ripe&&!dut.eu_flush)begin
   accepted=accepted+1;
   if(dut.u_eu.mode8080)begin
    if(irq_snapshot&&!irq_resumed)begin
     if(!isr_owned||owned_count!=irq_owned_cursor||dut.u_eu.pc!==16'(irq_restart)||
        ram_read_stage!=7||public_read_stage!=7||ram_write_stage!=6||public_write_stage!=6)$fatal(1,"F53_ORACLE_IRQ_IRET_RESUMPTION");
     irq_resumed=1;$display("F53_IRQ_RESUME next_owned=%0d restart=%04x",irq_owned_cursor,16'(irq_restart));
    end
    if(owned_count>=expected_owned||dut.u_eu.pc!==w(128+owned_count*2)||dut.q_byte!==8'(w(129+owned_count*2)))$fatal(1,"F53_ORACLE_OWNED_PC_BYTE");
    if(owned_count==0)begin
     if(!pre_valid||!entry_flush||dut.u_eu.flags_rd!==entry_psw||!dut.u_eu.md_write_enabled||ram_write_stage!=3||public_write_stage!=3||ram_read_stage!=2||public_read_stage!=2)$fatal(1,"F53_PROTO_ENTRY_FRAME_STATE");
     for(integer k=0;k<8;k=k+1)if(dut.u_eu.gpr[k]!==((k==4)?16'(frame_sp):pre_gpr[k]))$fatal(1,"F53_PROTO_ENTRY_GPR");
     for(integer k=0;k<4;k=k+1)if(dut.u_eu.sreg[k]!==emu_sreg[k])$fatal(1,"F53_PROTO_ENTRY_SREG");
     entry_frame_seen=1;$display("F53_ENTRY_FRAME nativeSP=%04x frameSP=%04x FLAGS=%04x",pre_gpr[4],dut.u_eu.gpr[4],dut.u_eu.flags_rd);
    end
    if(event_issued&&event_kind==1&&expected_irq==0&&event_point==4&&!masked_wake_seen)begin
     if(dut.u_eu.pc!==w(38)||inta_count!=0||isr_count!=0)$fatal(1,"F53_ORACLE_MASKED_HALT_RESTART");
     masked_wake_seen=1;$display("F53_WAKE_EMU PC=%04x FLAGS=%04x",dut.u_eu.pc,dut.u_eu.flags_rd);
    end
    $display("F53_OWNED index=%0d PC=%04x byte=%02x",owned_count,dut.u_eu.pc,dut.q_byte);owned_count=owned_count+1;
    // Owning the THIRD NOP implies that the FIRST NOP finished, even with one pre-pop latch.
    if(selected_opcode==32'd118&&event_kind==1&&expected_irq==0&&event_point==4&&event_issued&&owned_count==halt_owned_count+3)begin
     if(!masked_wake_seen||first_successor_complete||w(129+halt_owned_count*2)!==16'h0000||w(131+halt_owned_count*2)!==16'h0000||w(133+halt_owned_count*2)!==16'h0000)$fatal(1,"F53_PROTO_MASKED_HALT_SUCCESSOR_CURSOR");
     first_successor_complete=1;$display("F53_HLT_SUCCESSOR_COMPLETE sys=%0d owned=%0d",sys,owned_count);
    end
   end else begin
    if(dut.u_eu.pc==16'(return_ip+3)&&dut.u_eu.sreg[1]==16'(native_cs)&&dut.q_byte==8'hf4)native_hlt_owned=1;
    if(event_issued&&expected_irq==1&&dut.u_eu.sreg[1]==(population==0||population==2?16'h0600:16'h0800)&&dut.q_byte==8'hcf)begin
     if(isr_owned||dut.u_eu.gpr[4]!==16'(frame_sp-6))$fatal(1,"F53_ORACLE_NATIVE_ISR_FRAME");
     isr_owned=1;isr_count=isr_count+1;$display("F53_ISR PC=%04x FLAGS=%04x SP=%04x",dut.u_eu.pc,dut.u_eu.flags_rd,dut.u_eu.gpr[4]);
    end
   end
  end
  if(dut.u_eu.mode8080&&entry_frame_seen)begin
   if((dut.u_eu.st==22&&dut.u_eu.upc_page==6&&int'(dut.u_eu.upc_opc)==selected_opcode)||(dut.u_eu.st==33&&int'(dut.u_eu.ld_b)==selected_opcode)||(dut.u_eu.st==30&&selected_opcode==118))begin
    target_rows=target_rows+1;$display("F53_TARGET opcode=%02x PC=%04x st=%0d UPC=%0d.%02x.%0d",selected_opcode,dut.u_eu.pc,dut.u_eu.st,dut.u_eu.upc_page,dut.u_eu.upc_opc,dut.u_eu.upc_loc);
   end
   if(selected_opcode==32'd118&&!event_issued&&!retem_seen)begin
    if(rig.next_t_state==3'd1&&rig.bs_q==3'd3)begin
     if(halt_announced||owned_count!=halt_owned_count||dut.u_eu.pc!==w(38)||!dut.u_eu.md_write_enabled)$fatal(1,"F53_PROTO_HALT_ANNOUNCE_OWNER");
     halt_announced=1;halt_owner_seq=adapter_owner_seq+1;
     $display("F53_HLT_ANNOUNCE sys=%0d seq=%0d",sys,halt_owner_seq);
    end
    if(halt_announced&&!halt_parked&&rig.t_state==3'd5&&rig.next_t_state==3'd0)begin
     if(adapter_owner_kind!==3'd3||adapter_owner_seq!=halt_owner_seq)$fatal(1,"F53_PROTO_HALT_END_OWNER");
     halt_parked=1;$display("F53_HLT_PARKED sys=%0d seq=%0d",sys,halt_owner_seq);
    end
    // No fetch or HALT pseudo-cycle clock contributes to the registered32/48 standby bar.
    if(halt_parked&&rig.t_state==3'd0)begin
     halt_age=halt_age+1;
     if(halt_age==halt_required)
      $display("F53_HALT_STABLE cycles=%0d PC=%04x FLAGS=%04x BS=%0d",halt_age,dut.u_eu.pc,dut.u_eu.flags_rd,bs);
    end
   end
  end
  if(event_kind!=0&&!event_issued&&entry_frame_seen&&
   ((event_point==1&&owned_count==1)||(event_point==2&&dut.u_eu.st==33)||(event_point==3&&owned_count>=2)||(event_point==4&&halt_age>=halt_required)))begin
   event_issued=1;event_sys=sys;
   if(event_kind==1)int_req=1;
   if(event_kind==2)nmi_req=1;
   if(event_kind==3)rig_reset=1;
   $display("F53_EVENT type=%0d point=%0d PC=%04x FLAGS=%04x owned=%0d",event_kind,event_point,dut.u_eu.pc,dut.u_eu.flags_rd,owned_count);
  end
  if(event_kind==1&&expected_irq==0&&event_issued&&!int_withdrawn&&owned_count>=expected_owned-2&&
     (event_point!=4||(sys-event_sys>=75&&first_successor_complete&&masked_int_cpu_age>=15+masked_int_wait_age)))begin
   if(sys-event_sys<75||(event_point==4&&!masked_wake_seen))$fatal(1,"F53_PROTO_MASKED_INT_STIMULUS_DURATION");
   int_req=0;int_withdrawn=1;$display("F53_INT_WITHDRAW heldSYS=%0d owned=%0d PC=%04x",sys-event_sys,owned_count,dut.u_eu.pc);
   if(event_point==4)$display("F53_HLT_INT_WITHDRAW sys=%0d CPU=%0d TW=%0d successor=%b owned=%0d",sys,masked_int_cpu_age,masked_int_wait_age,first_successor_complete,owned_count);
  end
  if(dut.u_eu.st==22&&dut.u_eu.upc_page==5&&dut.u_eu.upc_opc==8'hfd&&dut.u_eu.upc_loc==0)begin
   $display("F53_PRE_RETEM PC=%04x FLAGS=%04x GPR=%04x,%04x,%04x,%04x,%04x,%04x,%04x,%04x SREG=%04x,%04x,%04x,%04x reads=%0d,%0d writes=%0d,%0d",dut.u_eu.pc,dut.u_eu.flags_rd,dut.u_eu.gpr[0],dut.u_eu.gpr[1],dut.u_eu.gpr[2],dut.u_eu.gpr[3],dut.u_eu.gpr[4],dut.u_eu.gpr[5],dut.u_eu.gpr[6],dut.u_eu.gpr[7],dut.u_eu.sreg[0],dut.u_eu.sreg[1],dut.u_eu.sreg[2],dut.u_eu.sreg[3],ram_read_stage,public_read_stage,ram_write_stage,public_write_stage);
   if(!entry_frame_seen||retem_seen||reset_case!=0||!dut.u_eu.mode8080||!dut.u_eu.md_write_enabled||dut.u_eu.pc!==16'(retem_pc+2)||(dut.u_eu.flags_rd&flags_mask)!==expected_flags||(dut.u_eu.flags_rd&16'h802a)!==16'h0002)$fatal(1,"F53_ORACLE_PRE_RETEM_FLAGS_MODE");
   for(integer k=0;k<8;k=k+1)if(dut.u_eu.gpr[k]!==((k==4)?16'(frame_sp):final_gpr[k]))$fatal(1,"F53_ORACLE_PRE_RETEM_GPR");
   for(integer k=0;k<4;k=k+1)if(dut.u_eu.sreg[k]!==emu_sreg[k])$fatal(1,"F53_ORACLE_PRE_RETEM_SREG");
   if(owned_count!=expected_owned||ram_read_stage!=read_count-3||public_read_stage!=read_count-3||ram_write_stage!=write_count-1||public_write_stage!=write_count-1)$fatal(1,"F53_ORACLE_PRE_RETEM_COVERAGE");
   if(expected_irq==1&&(selected_opcode==32'd243||selected_opcode==32'd251)&&(!irq_snapshot||!irq_resumed))$fatal(1,"F53_ORACLE_IRQ_BOUNDARY_COVERAGE");
   if(inta_count!=expected_inta||isr_count!=expected_irq||(event_kind!=0&&!event_issued))$fatal(1,"F53_ORACLE_EVENT_ELIGIBILITY");
   if(event_kind==1&&expected_irq==0&&(!int_withdrawn||int_req))$fatal(1,"F53_PROTO_MASKED_INT_NOT_WITHDRAWN");
   retem_seen=1;
  end
  if(dut.u_biu.r_run&&dut.u_biu.r_ts==2&&!dut.u_biu.r_cur_wr&&!dut.u_biu.r_cur_halt)begin
   if(dut.u_biu.r_cur_bs==0)begin
    if(event_kind!=1||expected_irq!=1||!event_issued||inta_count>=expected_inta)$fatal(1,"F53_ORACLE_UNEXPECTED_INTA");
    inta_count=inta_count+1;int_req=0;$display("F53_INTA count=%0d DATA_I=%04x",inta_count,core_read_data);
   end else if(dut.u_biu.r_cur_bs==5||dut.u_biu.r_cur_bs==1)begin
    if(!adapter_owner_valid||adapter_owner_seq==public_owner_used_seq||mem_kind!==dut.u_biu.r_cur_bs||adapter_owner_kind!==mem_kind)$fatal(1,"F53_PROTO_READ_BUS_CLASS");
    score_group(1,0,mem_kind==1?1:0,mem_addr,mem_rdata,mem_be);
    score_group(1,1,adapter_owner_kind==3'd1 ? 1 : 0,adapter_owner_addr,core_read_data,adapter_owner_be);
    public_owner_used_seq=adapter_owner_seq;
   end else if(dut.u_biu.r_cur_bs!=4)$fatal(1,"F53_ORACLE_UNEXPECTED_READ_KIND");
  end
 end
 if(nmi_req&&sys-event_sys>=20)nmi_req=0;
 if(event_kind==3&&event_issued)begin
  if(core_reset)reset_seen=1;
  if(sys-event_sys>=60)rig_reset=0;
  if(reset_seen&&!core_reset&&half_ce&&adapter_t1&&addr==20'hffff0&&bs==4)reset_fetch_seen=1;
 end
 if(mem_wr_req)begin
  if(mem_kind!=6&&mem_kind!=2)$fatal(1,"F53_PROTO_RAM_WRITE_CLASS");
  score_group(0,0,mem_kind==2?1:0,mem_addr,mem_wdata,mem_be);
  if(mem_kind==6)begin
   if(mem_be[0])ram[{mem_addr[19:1],1'b0}]<=mem_wdata[7:0];
   if(mem_be[1])ram[{mem_addr[19:1],1'b1}]<=mem_wdata[15:8];
  end
 end
 if(!core_reset&&ce&&dut.eu_flush)begin
  if(dut.u_eu.flush_cs==16'(emu_cs)&&dut.u_eu.flush_ip==16'(emu_ip))entry_flush=1;
  if(retem_seen&&dut.u_eu.flush_cs==16'(native_cs)&&dut.u_eu.flush_ip==16'(return_ip))return_flush=1;
  $display("F53_FLUSH target=%04x:%04x",dut.u_eu.flush_cs,dut.u_eu.flush_ip);
 end
 if(!dut.u_biu.r_run||dut.u_biu.r_ts==0||dut.u_biu.r_ts==5)public_seen=0;
 if(!core_reset&&ce&&dut.u_biu.r_run&&dut.u_biu.r_ts==3&&dut.u_biu.r_cur_wr&&!public_seen)begin
  if(!adapter_owner_valid||adapter_owner_seq==public_owner_used_seq||(adapter_owner_kind!=3'd6&&adapter_owner_kind!=3'd2))$fatal(1,"F53_PROTO_PUBLIC_WRITE_CLASS");
  score_group(0,1,adapter_owner_kind==3'd2 ? 1 : 0,adapter_owner_addr,data_out,adapter_owner_be);
  public_owner_used_seq=adapter_owner_seq;public_seen=1;
 end
 #2;
 $display("F53_SYS_POST n=%0d PC=%04x st=%0d FLAGS=%04x MODE=%b SESSION=%b GPR=%04x,%04x,%04x,%04x,%04x,%04x,%04x,%04x SREG=%04x,%04x,%04x,%04x",sys,dut.u_eu.pc,dut.u_eu.st,dut.u_eu.flags_rd,dut.u_eu.mode8080,dut.u_eu.md_write_enabled,dut.u_eu.gpr[0],dut.u_eu.gpr[1],dut.u_eu.gpr[2],dut.u_eu.gpr[3],dut.u_eu.gpr[4],dut.u_eu.gpr[5],dut.u_eu.gpr[6],dut.u_eu.gpr[7],dut.u_eu.sreg[0],dut.u_eu.sreg[1],dut.u_eu.sreg[2],dut.u_eu.sreg[3]);
 if(previous_mode&&!dut.u_eu.mode8080&&retem_seen)returned=1;
 previous_mode=dut.u_eu.mode8080;
 if(reset_case!=0&&reset_fetch_seen)begin
  if(!reset_seen||!event_issued||dut.u_eu.mode8080||dut.u_eu.md_write_enabled||!dut.u_eu.flags_rd[15])$fatal(1,"F53_ORACLE_RESET_NATIVE");
  final_memory_and_coverage;
  $display("F53_PASS population=%0d id=%0d reset=1 owned=%0d targetrows=%0d INTA=%0d ISR=%0d",population,case_id,owned_count,target_rows,inta_count,isr_count);$finish;
 end
 if(dut.u_eu.st==30&&!core_reset&&accepted_ce_snapshot&&!dut.u_eu.mode8080&&retem_seen)begin
  finish_age=finish_age+1;
  if(finish_age==20)begin
   if(!pre_valid||!entry_frame_seen||!returned||!return_flush||!native_hlt_owned||dut.u_eu.md_write_enabled||dut.u_eu.flags_rd!==native_psw||dut.u_eu.pc!==16'(final_pc))$fatal(1,"F53_ORACLE_NATIVE_RETURN");
   for(integer k=0;k<8;k=k+1)if(dut.u_eu.gpr[k]!==final_gpr[k])$fatal(1,"F53_ORACLE_FINAL_GPR");
   for(integer k=0;k<4;k=k+1)if(dut.u_eu.sreg[k]!==native_sreg[k])$fatal(1,"F53_ORACLE_FINAL_SREG");
   final_memory_and_coverage;
   $display("F53_PASS population=%0d id=%0d reset=0 owned=%0d targetrows=%0d INTA=%0d ISR=%0d",population,case_id,owned_count,target_rows,inta_count,isr_count);$finish;
  end
 end else if(dut.u_eu.st!=30)finish_age=0;
 if(sys>=100000)$fatal(1,"F53_ORACLE_BOUNDED_TIMEOUT");
end
endmodule
