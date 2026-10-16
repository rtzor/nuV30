// New fixed bytes, from hand-derived public instruction semantics.
task automatic initialize_literal_program(input integer f);
 if(f==2)bytes_at('hffff0,"EA00020000");else bytes_at('hffff0,"EA00010000");bytes_at('h00080,"00040000");bytes_at('h00400,"FE060006CF");
 case(f)
 0:bytes_at('h00100,"FAB800008ED88EC08ED0BC0008F09C58F4");
 1:bytes_at('h00100,"FAB800008ED88EC08ED0BC0008B8020250F09DF8F8F8F8F8F8F8F8BB7856F4");
 2:bytes_at('h00200,"FAB800008ED88EC08ED0BC000AFBF8F8F8F8F8F8F8F8B8020050F09DF8F8F8F8F8F8F8F8BB6824F4");
 default:$fatal(1,"LVC_ARGUMENT_FAIL");
 endcase
endtask
task automatic check_literal_result(input integer f);
 case(f)
 0:begin
  if(write_count!=1||write_bytes!=2||inta_count!=0)$fatal(1,"LVC_LITERAL_TRANSACTION_FAIL");
  if(dut.u_eu.gpr[0]!==16'hf002||dut.u_eu.gpr[4]!==16'h0800||dut.u_eu.psw!==16'hf002)$fatal(1,"LVC_LITERAL_REGISTER_FAIL");
  if({ram[20'h007ff],ram[20'h007fe]}!==16'hf002)$fatal(1,"LVC_LITERAL_RAM_FAIL");
 end
 1:begin
  if(write_count!=5||write_bytes!=9||inta_count!=2)$fatal(1,"LVC_LITERAL_TRANSACTION_FAIL");
  if(dut.u_eu.gpr[0]!==16'h0202||dut.u_eu.gpr[4]!==16'h0800||dut.u_eu.psw!==16'hf202)$fatal(1,"LVC_LITERAL_REGISTER_FAIL");
  if(dut.u_eu.gpr[3]!==16'h5678)$fatal(1,"LVC_LITERAL_REGISTER_FAIL");
  if(ram[20'h00600]!==8'h01||{ram[20'h007ff],ram[20'h007fe]}!==16'hf202||{ram[20'h007fd],ram[20'h007fc]}!==16'h0000||{ram[20'h007fb],ram[20'h007fa]}!==irq_saved_ip)$fatal(1,"LVC_LITERAL_FRAME_FAIL");
  if(!((irq_saved_ip>=16'h0113&&irq_saved_ip<=16'h011b)||irq_saved_ip==16'h011e||irq_saved_ip==16'h011f))$fatal(1,"LVC_LITERAL_IP_DOMAIN_FAIL");
  if(dut.u_eu.sreg[1]!==16'h0000||irq_entries!=1||iret_returns!=1)$fatal(1,"LVC_IRQ_RETURN_FAIL");
 end
 2:begin
  if(write_count!=1||write_bytes!=2||inta_count!=0)$fatal(1,"LVC_LITERAL_TRANSACTION_FAIL");
  if(dut.u_eu.gpr[0]!==16'h0002||dut.u_eu.gpr[4]!==16'h0a00||dut.u_eu.psw!==16'hf002)$fatal(1,"LVC_LITERAL_REGISTER_FAIL");
  if(dut.u_eu.gpr[3]!==16'h2468)$fatal(1,"LVC_LITERAL_REGISTER_FAIL");
  if(ram[20'h00600]!==8'h00||{ram[20'h009ff],ram[20'h009fe]}!==16'h0002||irq_entries!=0)$fatal(1,"LVC_MASKED_FRAME_FAIL");
 end
 default:$fatal(1,"LVC_ARGUMENT_FAIL");
 endcase
endtask
