`timescale 1ns/1ps
module tb_boundary_origin_observer;
import v30_ss_pkg::*;
logic clk=0,ce=0,srst=1,ss_we=0;
logic [8:0] ss_addr=0;logic [15:0] ss_wdata=0;wire q_pop;logic ripe=0;logic observe=0;logic naive_token=0,correct_token=0;integer negative=0;integer mature_count=2;logic[5:0] expected_state;
always #10 clk=~clk;
v30u_eu u_eu(
.clk(clk),
.ce(ce),
.srst(srst),
.q_byte(8'hFA),
.q_ripe(ripe),
.q_ripe_lead_n(ripe && mature_count==2),
.q_cnt(ripe ? (mature_count==2 ? 4'd2 : 4'd1) : 4'd0),
.q_pop(q_pop),
.q_first(),
.q_flush(),
.flush_pre(),
.flush_rep(),
.flush_stage(),
.flush_pend(),
.flush_nmi(),
.flush_int_live(),
.flush_cs(),
.flush_cs_old(),
.flush_cs_we(),
.flush_ip(),
.eu_post(),
.eu_post_hold(),
.eu_halt_irq(),
.eu_vector_post(),
.eu_bs(),
.eu_addr(),
.eu_addr2(),
.eu_split(),
.eu_seg(),
.eu_seg2(),
.eu_word(),
.eu_ghost_row(),
.eu_ghost_acc(),
.eu_ghost_sp(),
.eu_ghost_bare(),
.eu_slot_busy('0),
.eu_slot_busy_n('0),
.eu_access_active('0),
.eu_direct_fetch('0),
.eu_fetch_tail('0),
.eu_ghost_full('0),
.eu_ghost_idle('0),
.eu_ghost_stack_first('0),
.eu_pair(),
.eu_pair2(),
.eu_wdata(),
.eu_rdata_n('0),
.eu_rd_done_n('0),
.eu_rd_edge('0),
.eu_rd_edge_d('0),
.eu_wr_done_n('0),
.eu_wr_eval('0),
.eu_opr_free(1'b1),
.eu_susp(),
.eu_resume(),
.eu_halt(),
.eu_unhalt(),
.eu_unhalt_disp(),
.halted('0),
.eu_bnd_take(),
.eu_bnd_post(),
.psw_ie(),
.md8080(),
.pin_int('0),
.pin_nmi('0),
.pin_poll_n(1'b1),
.bkd_load('0),
.bkd_regs('0),
.dbg_regs(),
.dbg_first_pop(),
.dbg_pend(),
.ss_addr(ss_addr),
.ss_wdata(ss_wdata),
.ss_we(ss_we),
.ss_rdata());
wire origin_offer=(u_eu.st==6'd25)&&u_eu.retire_ok_n;
wire accepted_consume=observe&&ce&&!ss_we&&!srst&&q_pop&&ripe;
wire accepted_recognition=observe&&ce&&!ss_we&&!srst&&u_eu.bnd_take;
always @(posedge clk) begin
 if(srst||ss_we) begin naive_token<=0;correct_token<=0;end
 else if(observe) begin
  if(origin_offer) naive_token<=1;
  if(accepted_consume||accepted_recognition) correct_token<=0;
  else if(origin_offer) correct_token<=1;
 end
end
integer sys=0;
always @(posedge clk) begin
 $display("SYS_PRE n=%0d ce=%0b reset=%0b ss=%0b st=%0d next=%0d opc=%0b nextopc=%0b bnd=%0b epop=%0b retire=%0b pop_offer=%0b accepted=%0b poste=%0b owed=%0b chain=%0d",sys,ce,srst,ss_we,u_eu.st,u_eu.st_n,u_eu.opc_valid,u_eu.opc_valid_n,u_eu.at_bnd,u_eu.bnd_epop,u_eu.retire_ok_n,q_pop,accepted_consume,u_eu.poste,u_eu.iend_owed,u_eu.chain_used);
 #1;
 $display("SYS_POST n=%0d st=%0d next=%0d bnd=%0b pop_offer=%0b poste=%0b owed=%0b",sys,u_eu.st,u_eu.st_n,u_eu.at_bnd,q_pop,u_eu.poste,u_eu.iend_owed);sys=sys+1;
end
task automatic put(input logic[8:0] a,input logic[15:0] d);
 @(negedge clk);ss_we=1;ss_addr=a;ss_wdata=d;
 @(posedge clk);#2;
endtask
initial begin
 if($value$plusargs("negative=%d",negative)) begin end
 if($value$plusargs("count=%d",mature_count)) begin end
 if(mature_count!=1&&mature_count!=2) $fatal(1,"PROFILE_COUNT_FAIL");
 expected_state=mature_count==1 ? 6'd7 : 6'd33;
 repeat(2) @(posedge clk);
 @(negedge clk);srst=0;
 put(SSA_E_ST,16'd30);
 put(SSA_E_PSW,16'hF002);
 put(SSA_E_INTR_PEND,0);put(SSA_E_PIN_PIPE,0);put(SSA_E_IRQ_LATCH,0);put(SSA_E_BRK,0);
 put(SSA_E_WR_OUT,0);put(SSA_E_PEND_ACT,0);put(SSA_E_OPC_VALID,0);put(SSA_E_POSTE,0);
 put(SSA_E_ST,16'd25);
 @(negedge clk);ss_we=0;ss_addr=0;ss_wdata=0;
 #1;observe=1;
 $display("DRY_ANCHOR st=%0d next=%0d offer=%0b ripe=%0b pop=%0b",u_eu.st,u_eu.st_n,origin_offer,ripe,q_pop);
 if(u_eu.st!==6'd25||u_eu.st_n!==6'd25||origin_offer!==1||q_pop!==1||accepted_consume!==0) $fatal(1,"DRY_ANCHOR_FAIL");
 @(posedge clk);#2;
 if(correct_token!==1||naive_token!==1||u_eu.st!==6'd25) $fatal(1,"DRY_TOKEN_HOLD_FAIL");
 @(negedge clk);ce=1;
 @(posedge clk);#2;
 if(u_eu.st!==6'd25||correct_token!==1) $fatal(1,"DRY_ACCEPT_NO_CONSUME_FAIL");
 @(negedge clk);ce=0;ripe=1;
 #1;
 $display("ORIGINAL_ANCHOR st=%0d next=%0d epop=%0b retire=%0b pop=%0b nextopc=%0b",u_eu.st,u_eu.st_n,u_eu.bnd_epop,u_eu.retire_ok_n,q_pop,u_eu.opc_valid_n);
 if(u_eu.st!==6'd25||u_eu.st_n!==expected_state||u_eu.bnd_epop!==1||u_eu.retire_ok_n!==1||q_pop!==1||u_eu.opc_valid_n!==0) $fatal(1,"ORIGIN_ANCHOR_FAIL");
 repeat(4) begin
 @(posedge clk);#2;
 if(u_eu.st!==6'd25||u_eu.bnd_epop!==1||q_pop!==1||correct_token!==1||naive_token!==1) $fatal(1,"CE0_RETENTION_FAIL");
 end
 @(negedge clk);ce=1;
 @(posedge clk);#2;
 if(u_eu.st!==expected_state||u_eu.at_bnd!==0) $fatal(1,"ACCEPTED_CANCEL_FAIL");
 $display("TOKEN_SENSITIVE_ANCHOR correct=%0b naive=%0b actualst=%0d",correct_token,naive_token,u_eu.st);
 if(correct_token!==0||naive_token!==1) $fatal(1,"TOKEN_CONTROL_FAIL");
 if(negative!=0&&naive_token!==correct_token) $fatal(1,"EXPECTED_STALE_TOKEN_FAIL");
 $display("ORIGIN_CANCEL_PASS accepted_once=1 ce0_samples=4 old_offer=1 final_boundary=0");
 $finish;
end
initial begin #2000;$fatal(1,"OBSERVER_TIMEOUT");end
endmodule
