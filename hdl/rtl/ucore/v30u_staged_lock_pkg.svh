`ifndef V30U_STAGED_LOCK_PKG_SVH
`define V30U_STAGED_LOCK_PKG_SVH
package v30u_staged_lock_pkg;
// Experimental current-source profile; no prospective-EU/native equivalence.
typedef struct packed {
 logic is_row,is_defer,is_tail,is_opc,ending,opc_valid,pend_new,fresh;
 logic writes_opr,blocked,row_q_ok,pre_wait,slot_wait;
 logic [1:0] wr_out,wr_add;
 logic wr_done,wait_read,free_opr,armed,flush;
} primitive_t;
function automatic logic [3:0] compose(input primitive_t p);
 logic [2:0] after_write;
 logic retire_e,retire_n,pending;
 after_write={1'b0,p.wr_out}+{1'b0,p.wr_add};
 retire_e=(after_write==3'd0)||((after_write==3'd1)&&p.wr_done);
 retire_n=(p.wr_out==2'd0)||((p.wr_out==2'd1)&&p.wr_done);
 pending=p.pend_new&&!(p.fresh||p.writes_opr);
 compose[3]=p.is_row&&p.ending&&!pending&&!p.opc_valid&&!p.blocked&&p.row_q_ok&&!p.pre_wait&&!p.slot_wait&&retire_e;
 compose[2]=p.is_defer&&retire_n;
 compose[1]=p.is_tail&&!p.opc_valid&&(p.fresh||!(p.wait_read||!p.free_opr))&&retire_n;
 compose[0]=p.is_opc&&p.armed;
endfunction
endpackage
`endif
