`timescale 1ns/1ps
// Full public EU/BIU and actual nec_bus sampler. No capture/replay oracle.
module tb_staged_integration;
import v30_ss_pkg::*;
logic clk,rig_reset=1,int_req,nmi_req=0;
always #10 clk=~clk;
initial begin : fixture_literal_initial_values
 int_req=0;
 withdraw_active=0;
 sys=0;
 ce_count=0;
 write_count=0;
 write_bytes=0;
 mirror_writes=0;
 mirror_bytes=0;
 inta_count=0;
 halt_count=0;
 finish_age=0;
 first_halt_ce=-1;
 seen_t1=0;
 mirror_seen=0;
 inta_prev=0;
 irq_sent=0;
 ref_phase=0;
 ref_started=0;
 ref_epoch=0;
 ref_h=0;
 ref_h1=0;
 ref_sampler=1;
 early_h_samples=0;
 aperture_differences=0;
 acquires=0;
 acquire_priority=0;
 row_writes=0;
 tail_pending=0;
 entry_seen=0;
 dry_ce0=0;
 deadline_seen=0;
 if_rise=0;
 if_fall=0;
 readedge_seen=0;
 withdraw_seen=0;
 previous_if=0;
 boundary_at20=0;
 flush_at20=0;
 primitive_at20=0;
 withdraw_phase=0;
 withdraw_done=0;
 adapter_owner_addr=0;adapter_owner_be=0;adapter_owner_valid=0;
 clk=0;
end

integer family=0,waits=0,negative=0,withdraw_case=0;
integer reset_case=0;
logic reset_test_done=0,invalid_test_done=0;
logic profile_ok=1,ss_we=0;
logic [8:0] ss_addr=0;
logic [15:0] ss_wdata=0;
wire [15:0] ss_rdata;
wire ss_err,ss_quiet;
wire ce,half_ce,core_reset,rig_ready,core_int,core_nmi,core_poll;
logic cadence_fault=0;
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
logic [19:0] pad_hold=0;
logic withdraw_active;
wire actual_ready=rig_ready&&!withdraw_active;
logic [7:0] ram[0:1048575],mirror[0:1048575];

v30_core dut(.CLK(clk),.CE(core_ce),.RESET(core_reset),.READY(actual_ready),
 .INT(core_int),.NMI(core_nmi),.POLL_N(core_poll),.DATA_I(core_read_data),
 .ADDR_O(addr),.DATA_O(data_out),.STATUS_O(status),.QS(qs),.BS(bs),.RD_N(rd_n),
 .UBE_N(ube_n),.BUSLOCK_N(lock_n),.SS_ADDR(ss_addr),.SS_WDATA(ss_wdata),.SS_WE(ss_we),
 .SS_RDATA(ss_rdata),.SS_ERR(ss_err),.SS_BUS_QUIET(ss_quiet),.STAGED_PROFILE_OK(profile_ok));

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
 expected_read=(mem_kind==3'd0)?16'h0020:
  {ram[{adapter_owner_addr[19:1],1'b1}],ram[{adapter_owner_addr[19:1],1'b0}]};
 if(core_reset)adapter_owner_valid<=0;
 if(check_address)begin
  if(rig.ad_in_q!==expected_addr||rig.ube_n_q!==ube_n)
   $fatal(1,"FIXTURE_PUBLIC_ADDRESS_SAMPLE_FAIL");
  adapter_owner_addr<=expected_addr;adapter_owner_be<=expected_be;adapter_owner_valid<=1;
  $display("PUBLIC_ADDRESS_ANCHOR sys=%0d addr=%05x be=%b sample=%05x",sys,expected_addr,expected_be,rig.ad_in_q);
 end
 if(check_read)begin
  if(!adapter_owner_valid||mem_addr!==adapter_owner_addr||mem_be!==adapter_owner_be)
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
always_comb mem_rdata={ram[{mem_addr[19:1],1'b1}],ram[{mem_addr[19:1],1'b0}]};

integer sys,ce_count,write_count,write_bytes,mirror_writes,mirror_bytes;
integer inta_count,halt_count,finish_age,first_halt_ce;
logic seen_t1,mirror_seen,inta_prev,irq_sent;
wire inta_level=dut.u_biu.r_run&&dut.u_biu.r_ts==3'd1&&
 dut.u_biu.r_cur_noaddr&&dut.u_biu.r_cur_bs==3'd0;
wire bus_t1=dut.u_biu.r_run&&dut.u_biu.r_ts==3'd1;
always @(posedge clk) begin
 if(mem_wr_req)begin
  if(!adapter_owner_valid||mem_addr!==adapter_owner_addr||mem_be!==adapter_owner_be)
   $fatal(1,"FIXTURE_WRITE_OWNING_ADDRESS_FAIL");
  write_count<=write_count+1;
  if(mem_be[0])begin ram[{mem_addr[19:1],1'b0}]<=mem_wdata[7:0];write_bytes<=write_bytes+(mem_be==2'b11 ? 2 : 1);end
  else if(mem_be[1])write_bytes<=write_bytes+1;
  if(mem_be[1])ram[{mem_addr[19:1],1'b1}]<=mem_wdata[15:8];
  $display("RAM_WRITE sys=%0d addr=%05x be=%b data=%04x lock=%b",sys,mem_addr,mem_be,mem_wdata,rig.buslock_n_q);
  if((family==0&&mem_addr>=20'h00200&&mem_addr<=20'h00204)||
     (family==1&&mem_addr>=20'h00300&&mem_addr<=20'h00306))
   if(rig.buslock_n_q!==0)$fatal(1,"FIXTURE_LOCKED_ANNOUNCEMENT_FAIL");
 end
 // Separate architectural bus tracker; never derives its counts from rig writes.
 if(!dut.u_biu.r_run||dut.u_biu.r_ts==3'd5||dut.u_biu.r_ts==3'd0)mirror_seen<=0;
 if(ce&&dut.u_biu.r_run&&dut.u_biu.r_ts==3'd3&&dut.u_biu.r_cur_wr&&!mirror_seen)begin
  mirror_seen<=1;mirror_writes<=mirror_writes+1;
  if(!addr[0])begin mirror[{addr[19:1],1'b0}]<=data_out[7:0];mirror_bytes<=mirror_bytes+(!ube_n?2:1);end
  else if(!ube_n)mirror_bytes<=mirror_bytes+1;
  if(!ube_n)mirror[{addr[19:1],1'b1}]<=data_out[15:8];
 end
 if(bus_t1&&!seen_t1)begin
  $display("ACTUAL_T1 sys=%0d bs=%0d addr=%05x noaddr=%b lock=%b",sys,dut.u_biu.r_cur_bs,addr,dut.u_biu.r_cur_noaddr,lock_n);
  if(dut.u_biu.r_cur_halt)begin halt_count<=halt_count+1;if(first_halt_ce<0)first_halt_ce<=ce_count;end
 end
 seen_t1<=bus_t1;
 if(inta_level&&!inta_prev)begin inta_count<=inta_count+1;int_req<=0;end
 inta_prev<=inta_level;
 if(core_reset)begin irq_sent<=0;int_req<=0;end
 else if(!irq_sent&&family==2&&first_halt_ce>=0&&ce&&ce_count==first_halt_ce+2)begin int_req<=1;irq_sent<=1;end
 if(ce)ce_count<=ce_count+1;
 sys<=sys+1;
end

// Original CURRENT wire oracle; never consume controller primitive/caches/tags.
wire [3:0] ref_boundary={dut.u_eu.bnd_row,
 ((dut.u_eu.st==6'd25)||(dut.u_eu.st==6'd28))&&dut.u_eu.retire_ok_n,
 dut.u_eu.tailw_go&&dut.u_eu.retire_ok_n,dut.u_eu.bnd_opc};
wire ref_r=dut.u_eu.bnd_take;
wire ref_g=(ref_boundary[3]&&(ref_r||(!dut.u_eu.row_flush&&dut.q_ripe)))||
 ((ref_boundary[2]||ref_boundary[1])&&(ref_r||dut.q_ripe))||
 (ref_boundary[0]&&(ref_r||(dut.u_eu.pop_is_first&&dut.q_ripe)));
wire ref_a=!dut.md8080&&dut.eu_pop&&dut.q_ripe&&dut.eu_first&&
 ((dut.q_byte==8'hf0)||(dut.q_byte==8'hf1));
integer ref_phase;
logic ref_started,ref_epoch,ref_h,ref_h1;
wire ref_aperture=ref_started&&(ref_phase>=3);
wire ref_g_published=ref_aperture&&ref_g;
wire ref_inta_low=inta_level?!ref_h1:ref_h1;
wire ref_pin=core_reset?1'b1:!(ref_a||(ref_h&&!ref_g_published)||ref_inta_low);
wire unrestricted_pin=core_reset?1'b1:!(ref_a||(ref_h&&!ref_g)||ref_inta_low);
logic ref_sampler;
integer early_h_samples,aperture_differences,acquires,acquire_priority;
integer row_writes,tail_pending,entry_seen,dry_ce0,deadline_seen;
integer if_rise,if_fall,readedge_seen,withdraw_seen;
logic previous_if;
logic [3:0] boundary_at20;
logic flush_at20;
// Field order is independently spelled from original EU sources, not a tap.
wire [21:0] raw_current_primitive={dut.u_eu.st==6'd22,
 ((dut.u_eu.st==6'd25)||(dut.u_eu.st==6'd28)),dut.u_eu.st==6'd27,
 dut.u_eu.st==6'd0,dut.u_eu.e_e||dut.u_eu.ext4s_early_e,
 dut.u_eu.opc_valid,dut.u_eu.pend_new,dut.u_eu.opr_fresh,dut.u_eu.row_wr_opr,
 dut.u_eu.row_blocked,dut.u_eu.rowq>=dut.u_eu.row_qn,dut.u_eu.row_pre_wait,
 dut.u_eu.row_slot_wait,dut.u_eu.wr_out,dut.u_eu.row_wr_add[1:0],
 dut.eu_wr_done_n,dut.u_eu.nr_wait,dut.u_eu.opr_free_now,dut.u_eu.bnd_armed,dut.u_eu.row_flush};
logic [21:0] primitive_at20;
always @(posedge clk)begin : reference_and_observe
 logic old_sampler,old_pin,old_ce;
 logic [6:0] old_queue;
 old_sampler=ref_sampler;old_pin=ref_pin;old_ce=ce;
 old_queue={dut.u_biu.r_q_head,dut.u_biu.r_q_cnt};
 if(core_reset)begin ref_started<=0;ref_phase<=0;ref_epoch<=0;ref_h<=0;ref_h1<=0;end
 else begin
  if(ce)begin
   ref_started<=1;ref_phase<=0;ref_epoch<=!ref_epoch;
   if(ref_a)ref_h<=1;else if(ref_g_published)ref_h<=0;
   if(inta_level)ref_h1<=!ref_h1;
  end else if(ref_started)ref_phase<=ref_phase+1;
 end
 ref_sampler<=old_pin;
 if(ref_started&&!ce&&ref_phase==0)begin boundary_at20<=ref_boundary;flush_at20<=dut.u_eu.row_flush;primitive_at20<=raw_current_primitive;end
 if(ref_h&&!ref_a&&!inta_level&&(ref_phase==1||ref_phase==2))early_h_samples<=early_h_samples+1;
 if(ref_pin!=unrestricted_pin)aperture_differences<=aperture_differences+1;
 if(ce&&ref_a)begin acquires<=acquires+1;if(ref_g_published)acquire_priority<=acquire_priority+1;end
 if(dut.u_eu.st==6'd22&&dut.u_eu.row_wr_add!=0)row_writes<=row_writes+1;
 if(dut.u_eu.st==6'd27&&dut.u_eu.pend_active)tail_pending<=tail_pending+1;
 if(dut.u_eu.st==6'd18||dut.u_eu.st==6'd19||dut.u_eu.st==6'd20)entry_seen<=entry_seen+1;
 if(!ce&&dut.eu_pop&&!dut.q_ripe)dry_ce0<=dry_ce0+1;
 if(dut.eu_rd_edge)readedge_seen<=readedge_seen+1;
 if(!previous_if&&dut.u_eu.psw[9])if_rise<=if_rise+1;
 if(previous_if&&!dut.u_eu.psw[9])if_fall<=if_fall+1;
 previous_if<=dut.u_eu.psw[9];
 if(ref_started&&ref_phase==3&&ref_h&&ref_g&&!ref_a&&!inta_level)begin
  deadline_seen<=deadline_seen+1;
  $display("DEADLINE_ANCHOR sys=%0d pin_before80=%b G=%b H=%b",sys,old_pin,ref_g,ref_h);
 end
 $display("SYS_PRE n=%0d ns=%0t ce=%b reset=%b rigREADY=%b actualREADY=%b st=%0d upc=%0d/%02x/%0d bound=%b R=%b Q=%b first=%b pop=%b A=%b G=%b H=%b H1=%b pin=%b sample=%b capvalid=%b cap=%016x",sys,$time,ce,core_reset,rig_ready,actual_ready,dut.u_eu.st,dut.u_eu.upc_page,dut.u_eu.upc_opc,dut.u_eu.upc_loc,ref_boundary,ref_r,dut.q_ripe,dut.eu_first,dut.eu_pop,ref_a,ref_g,ref_h,ref_h1,lock_n,rig.buslock_n_q,cap_valid,cap_record);
 #1;
 $display("SYS_POST n=%0d phase=%0d epoch=%b H=%b H1=%b pin=%b stage1=%b/%b stage2=%b/%b cache=%b pub=%b G=%b fault=%b sampler=%b capvalid=%b cap=%016x",sys,ref_phase,ref_epoch,dut.u_staged_lock.r_h[0],dut.u_staged_lock.r_h[1],lock_n,dut.u_staged_lock.r_s1_valid,dut.u_staged_lock.r_s1_tag,dut.u_staged_lock.r_s2_valid,dut.u_staged_lock.r_s2_tag,dut.u_staged_lock.r_boundary,dut.u_staged_lock.publish,dut.u_staged_lock.grant,dut.u_staged_lock.r_fault,rig.buslock_n_q,cap_valid,cap_record);
 if(ref_started&&!core_reset)begin
  if(negative!=1)begin
   if(lock_n!==ref_pin||dut.u_staged_lock.r_h[0]!==ref_h||dut.u_staged_lock.r_h[1]!==ref_h1)$fatal(1,"FIXTURE_PIN_HOLD_FAIL");
   if(rig.buslock_n_q!==old_pin)$fatal(1,"FIXTURE_REAL_SAMPLER_FAIL");
  end
  if(old_ce&&cap_record[50]!==old_sampler)$fatal(1,"FIXTURE_CAP_OLD_Q_FAIL");
  if(!old_ce&&!ss_we&&{dut.u_biu.r_q_head,dut.u_biu.r_q_cnt}!==old_queue)$fatal(1,"FIXTURE_CE0_QUEUE_CONSUME_FAIL");
  if(ref_phase>=1&&dut.u_staged_lock.r_primitive!==primitive_at20)$fatal(1,"FIXTURE_PRIMITIVE_ORACLE_FAIL");
  if(ref_phase>=2&&(dut.u_staged_lock.r_boundary!==ref_boundary||dut.u_staged_lock.r_row_flush!==dut.u_eu.row_flush))$fatal(1,"FIXTURE_CURRENT_PERMISSION_FAIL");
  if(ref_phase>=2&&(ref_boundary!==boundary_at20||dut.u_eu.row_flush!==flush_at20))$fatal(1,"FIXTURE_SOURCE_STABILITY_FAIL");
 end
 if(core_reset&&lock_n!==1)$fatal(1,"FIXTURE_RESET_IMMEDIATE_HIGH_FAIL");
end
// All negative-sensitive source reporters execute on falling edges before
// the next assertion edge; neither original permission nor reference uses caches.
always @(negedge clk)if(ref_started&&!core_reset)
 $display("SOURCE_ANCHOR n=%0d phase=%0d epoch=%b original_boundary=%b G=%b A=%b rowadd=%0d olddebt=%0d retire=%b Q=%b rawpop=%b accepted=%b",sys,ref_phase,ref_epoch,ref_boundary,ref_g,ref_a,dut.u_eu.row_wr_add,dut.u_eu.wr_out,dut.u_eu.retire_ok_e,dut.q_ripe,dut.eu_pop,ce&&dut.eu_pop&&dut.q_ripe);

integer withdraw_phase;
logic withdraw_done;
always @(negedge clk)begin
 if(core_reset)begin withdraw_active=0;withdraw_phase=0;withdraw_done=0;end
 else if(withdraw_case!=0&&!withdraw_done&&ref_started&&(ref_phase==1||ref_phase==2)&&
  dut.u_biu.r_run&&!dut.u_biu.r_cur_wr&&dut.u_biu.r_cur_bs==3'd5&&
  (dut.u_biu.r_ts==3'd3||dut.u_biu.r_ts==3'd4)&&addr==20'h007fe&&rig_ready)begin
  $display("READY_WITHDRAW_ANCHOR kind=%0d wr=%b data_T2=%04x edge=%b phase=%0d",dut.u_biu.r_cur_bs,dut.u_biu.r_cur_wr,dut.u_biu.r_cur_data,dut.eu_rd_edge,ref_phase);
  if(!dut.eu_rd_edge)$fatal(1,"READY_WITHDRAW_COVERAGE_FAIL");
  withdraw_active=1;withdraw_phase=1;withdraw_done=1;withdraw_seen=withdraw_seen+1;
 end else if(withdraw_phase==1)begin withdraw_active=0;withdraw_phase=2;end
end

// Directed reset/invalid profile stimuli are declared inputs. No RTL force,
// cache write, imported SS snapshot, or fake claim of program reachability.
initial begin
 wait(!core_reset&&ref_started);
 if(reset_case!=0)begin
  wait(ref_h&&!ref_a&&ref_phase==1);
  @(negedge clk);$display("RESET_OWNERSHIP_ANCHOR H=%b pin=%b writes=%0d",ref_h,lock_n,write_count);
  if(!ref_h||lock_n!==0||write_count!=0)$fatal(1,"FIXTURE_RESET_ANCHOR_FAIL");
  reset_test_done=1;rig_reset=1;repeat(4)@(negedge clk);rig_reset=0;
 end
 if(negative==6)begin
  wait(ref_h&&!ref_a&&ref_phase==1);
  @(negedge clk);$display("ILLEGAL_SS_ANCHOR H=%b phase=%0d",ref_h,ref_phase);
  ss_addr=SSA_E_STAT;ss_wdata=0;ss_we=1;invalid_test_done=1;
 end
 if(negative==7)begin
  wait(ref_h&&!ref_a&&ref_phase==1);
  @(negedge clk);$display("ILLEGAL_PROFILE_ANCHOR H=%b phase=%0d",ref_h,ref_phase);
  profile_ok=0;invalid_test_done=1;
 end
 if(negative==8)begin
  wait(ref_h&&!ref_a&&ref_phase==1);
  @(negedge clk);$display("ILLEGAL_CADENCE_ANCHOR H=%b phase=%0d ce=%b",ref_h,ref_phase,ce);
  cadence_fault=1;invalid_test_done=1;
 end
end

task automatic bytes_at(input integer start,input string hexbytes);
 integer value;
 for(integer i=0;i<hexbytes.len();i+=2)begin
  if($sscanf(hexbytes.substr(i,i+1),"%2x",value)!=1)$fatal(1,"LITERAL_BYTES_FAIL");
  ram[start+i/2]=8'(value);mirror[start+i/2]=8'(value);
 end
endtask
// Generated solely from programs-v2.json, not execution/model/golden output.
`include "literal-programs-v2.svh"
initial begin
 if($value$plusargs("family=%d",family))begin end
 if($value$plusargs("waits=%d",waits))begin end
 if($value$plusargs("negative=%d",negative))begin end
 if($value$plusargs("withdraw=%d",withdraw_case))begin end
 if($value$plusargs("resetcase=%d",reset_case))begin end
 if(family<0||family>3||(waits!=0&&waits!=1&&waits!=3))$fatal(1,"FIXTURE_ARGUMENT_FAIL");
 for(integer i=0;i<1048576;i++)begin ram[i]=0;mirror[i]=0;end
 initialize_literal_program(family);
 repeat(4)@(negedge clk);rig_reset=0;
end
always @(negedge clk)begin
 if(cpu_running&&dut.u_eu.st==6'd30&&((family!=2)||(inta_count==2&&ram[20'h00600]==1)))finish_age=finish_age+1;else finish_age=0;
 if(finish_age==20)begin
  check_literal_result(family);
  if(write_count!=mirror_writes||write_bytes!=mirror_bytes)$fatal(1,"MIRROR_TRANSACTION_FAIL");
  for(integer i=0;i<1048576;i++)if(ram[i]!==mirror[i])$fatal(1,"MIRROR_RAM_FAIL at%05x",i);
  $display("FIXTURE_FINAL family=%0d waits=%0d writes=%0d bytes=%0d earlyH=%0d differences=%0d acquire=%0d priority=%0d rowwrites=%0d tail=%0d entry=%0d dry=%0d deadline=%0d inta=%0d IFrise=%0d IFfall=%0d readedge=%0d withdraw=%0d",family,waits,write_count,write_bytes,early_h_samples,aperture_differences,acquires,acquire_priority,row_writes,tail_pending,entry_seen,dry_ce0,deadline_seen,inta_count,if_rise,if_fall,readedge_seen,withdraw_seen);
  if(early_h_samples==0||acquires==0||deadline_seen==0)$fatal(1,"FIXTURE_REQUIRED_OWNERSHIP_COVERAGE_FAIL");
  if(family<2&&row_writes==0)$fatal(1,"FIXTURE_ROW_WRITE_COVERAGE_FAIL");
  if(family==2&&inta_count!=2)$fatal(1,"FIXTURE_INTA_COUNT_FAIL");
  if(family==3&&(inta_count!=0||if_rise==0||if_fall==0||readedge_seen==0))$fatal(1,"FIXTURE_POPF_COVERAGE_FAIL");
  if(withdraw_case!=0&&withdraw_seen!=1)$fatal(1,"FIXTURE_WITHDRAW_COVERAGE_FAIL");
  if(reset_case!=0&&!reset_test_done)$fatal(1,"FIXTURE_RESET_COVERAGE_FAIL");
  $display("STAGED_FULL_INTEGRATION_PASS family=%0d waits=%0d",family,waits);$finish;
 end
 if(sys>=100000)$fatal(1,"FIXTURE_BOUNDED_TIMEOUT");
end
endmodule
