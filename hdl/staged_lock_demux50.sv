// Public abstract-host physical measurement wrapper; no board or native timing claim.
module staged_lock_demux50 (
 input logic SYS, RESET_I, READY_I, IRQ_I, NMI_I, POLL_N_I,
 input logic [15:0] DATA_I,
 output wire [19:0] ADDR_O,
 output wire [15:0] DATA_O,
 output wire [3:0] STATUS_O,
 output wire [2:0] BS,
 output wire [1:0] QS,
 output wire RD_N, UBE_N, LOCK_N,
 output logic LOCK_SYS_Q, LOCK_CE_Q,
 output logic [3:0] STATUS_SYS_Q,
 output wire CE_O, QUIET_O, SS_ERR_O
);
logic r_reset=1'b1, r_ready=1'b0, r_irq=1'b0, r_nmi=1'b0, r_poll_n=1'b1;
logic [15:0] r_data='0;
logic [2:0] r_div='0;
wire ce=(r_div==3'd4);
wire [15:0] unused_ss_rdata;
always_ff @(posedge SYS) begin
 r_reset<=RESET_I; r_ready<=READY_I; r_irq<=IRQ_I; r_nmi<=NMI_I;
 r_poll_n<=POLL_N_I; r_data<=DATA_I;
 if(r_reset) r_div<=0;
 else if(ce) r_div<=0;
 else r_div<=r_div+3'd1;
 // Continuous consumer exercises +60 publish -> +80 capture without CE gating.
 LOCK_SYS_Q<=LOCK_N;
 STATUS_SYS_Q<=STATUS_O;
 // At CPU CE sample the old continuous SYS sample (+80), before its CE-edge NBA refresh.
 if(r_reset) LOCK_CE_Q<=1'b1;
 else if(ce) LOCK_CE_Q<=LOCK_SYS_Q;
end
assign CE_O=ce;
v30_core dut (
 .STAGED_PROFILE_OK(1'b1), .CLK(SYS), .CE(ce), .RESET(r_reset),
 .READY(r_ready), .INT(r_irq), .NMI(r_nmi), .POLL_N(r_poll_n), .DATA_I(r_data),
 .ADDR_O(ADDR_O), .DATA_O(DATA_O), .STATUS_O(STATUS_O), .BS(BS), .QS(QS),
 .RD_N(RD_N), .UBE_N(UBE_N), .BUSLOCK_N(LOCK_N),
 .SS_ADDR('0), .SS_WDATA('0), .SS_WE(1'b0), .SS_RDATA(unused_ss_rdata),
 .SS_ERR(SS_ERR_O), .SS_BUS_QUIET(QUIET_O)
);
endmodule
