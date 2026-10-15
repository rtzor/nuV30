`ifndef V30U_STAGED_LOCK_UNIT_SVH
`define V30U_STAGED_LOCK_UNIT_SVH
`include "v30u_staged_lock_pkg.svh"
module v30u_staged_lock (
 input logic clk,ce,reset,ss_active_i,profile_ok_i,mode8080_i,scripted_i,
 input v30u_staged_lock_pkg::primitive_t primitive_i,
 input logic [3:0] ref_boundary_i,
 input logic recognition_i,mature_i,pop_first_i,acquire_i,inta_t1_i,
 output logic buslock_n_o
);
import v30u_staged_lock_pkg::*;
primitive_t r_primitive;
logic [3:0] r_boundary;
logic r_row_flush,r_epoch,r_s1_valid,r_s1_tag,r_s2_valid,r_s2_tag;
logic r_started,r_fault;
logic [2:0] r_phase;
logic [1:0] r_h;
wire illegal_now=!profile_ok_i||mode8080_i||scripted_i||
 (r_started&&ss_active_i)||(r_started&&ce&&(r_phase!=3'd4))||
 (r_started&&!ce&&(r_phase==3'd4));
wire [2:0] stage2_wr_after={1'b0,r_primitive.wr_out}+{1'b0,r_primitive.wr_add};
wire stage2_retire_e=(stage2_wr_after==3'd0)||((stage2_wr_after==3'd1)&&r_primitive.wr_done);
wire cache_valid=r_s2_valid&&(r_s2_tag==r_epoch);
wire publish=r_started&&(r_phase>=3'd3)&&cache_valid&&!r_fault&&!illegal_now;
wire grant=publish&&((r_boundary[3]&&(recognition_i||(!r_row_flush&&mature_i)))||
 ((r_boundary[2]||r_boundary[1])&&(recognition_i||mature_i))||
 (r_boundary[0]&&(recognition_i||(pop_first_i&&mature_i))));
wire prefix_low=acquire_i||(r_h[0]&&!grant);
wire inta_low=inta_t1_i ? !r_h[1] : r_h[1];
// Invalidating a profile must never silently surrender an owned exclusion.
wire fault_owned_low=(r_fault||illegal_now)&&(|r_h);
assign buslock_n_o=reset ? 1'b1 : !(prefix_low||inta_low||fault_owned_low);
always_ff @(posedge clk) begin
 if(reset) begin
  r_primitive<='0; r_boundary<='0; r_row_flush<=0;
  r_epoch<=0; r_s1_valid<=0; r_s1_tag<=0; r_s2_valid<=0; r_s2_tag<=0;
  r_started<=0; r_fault<=0; r_phase<=0; r_h<=0;
 end else if(illegal_now||r_fault) begin
  r_fault<=1; r_s1_valid<=0; r_s2_valid<=0;
  if(ce&&acquire_i) r_h[0]<=1;
 end else if(ce) begin
  r_started<=1; r_phase<=0; r_epoch<=!r_epoch;
  r_s1_valid<=0; r_s2_valid<=0;
  if(acquire_i) r_h[0]<=1;
  else if(grant) r_h[0]<=0;
  if(inta_t1_i) r_h[1]<=!r_h[1];
 end else if(r_started) begin
  r_phase<=r_phase+3'd1;
  case(r_phase)
   3'd0: begin r_primitive<=primitive_i; r_s1_valid<=1; r_s1_tag<=r_epoch; end
   3'd1: begin
    r_boundary<=compose(r_primitive); r_row_flush<=r_primitive.flush;
    r_s2_valid<=r_s1_valid; r_s2_tag<=r_s1_tag;
   end
   default: ;
  endcase
 end
end
`ifndef SYNTHESIS
wire current_reference_grant=(ref_boundary_i[3]&&(recognition_i||(!primitive_i.flush&&mature_i)))||
 ((ref_boundary_i[2]||ref_boundary_i[1])&&(recognition_i||mature_i))||
 (ref_boundary_i[0]&&(recognition_i||(pop_first_i&&mature_i)));
// Read-only references diagnose stability; they do not supply candidate logic.
always @(posedge clk or negedge clk) if(!reset&&r_started&&!r_fault&&!illegal_now) begin
 if(r_s1_valid&&(r_s1_tag==r_epoch))
  assert(r_primitive===primitive_i) else $fatal(1,"STAGED_LOCK_PRIMITIVE_STABILITY_FAIL");
 if(cache_valid) begin
  assert(r_boundary===ref_boundary_i && r_row_flush===primitive_i.flush)
   else $fatal(1,"STAGED_LOCK_BOUNDARY_CACHE_FAIL");
 end
 if(r_phase>=3'd3)
  assert(cache_valid) else $fatal(1,"STAGED_LOCK_PHASE_CONTEXT_FAIL");
end
always @(posedge clk) if(!reset)
 assert(!illegal_now&&!r_fault) else $fatal(1,"STAGED_LOCK_PROTOCOL_FAIL");
`endif
endmodule
`endif
