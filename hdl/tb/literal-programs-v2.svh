// Literal inputs and numeric checks only; generated without DUT/model execution.
task automatic initialize_literal_program(input integer f);
case(f)
0: begin
bytes_at('hffff0,"EA00010000");
bytes_at('h00080,"00040000");
bytes_at('h00400,"8BF4BF0005B9030036F3A5FE060006CF");
bytes_at('h00100,"FAB800008ED88EC08ED0BC0008BB0102B83412F08907F1894702F4");
end
1: begin
bytes_at('hffff0,"EA00010000");
bytes_at('h00080,"00040000");
bytes_at('h00400,"8BF4BF0005B9030036F3A5FE060006CF");
bytes_at('h00100,"FAB800008ED88EC08ED0BC0008BF0103B90300B8A55AFCF0F3ABF4");
end
2: begin
bytes_at('hffff0,"EA00010000");
bytes_at('h00080,"00040000");
bytes_at('h00400,"8BF4BF0005B9030036F3A5FE060006CF");
bytes_at('h00100,"FAB800008ED88EC08ED0BC0008FBF0F4F4");
end
3: begin
bytes_at('hffff0,"EA00010000");
bytes_at('h00080,"00040000");
bytes_at('h00400,"8BF4BF0005B9030036F3A5FE060006CF");
bytes_at('h00100,"FAB800008ED88EC08ED0BC0008B8020250F09DB80200509D9C58F4");
end
default:$fatal(1,"LITERAL_FAMILY_FAIL");
endcase
endtask
task automatic check_literal_result(input integer f);
case(f)
0: begin
if(write_count!=4||write_bytes!=4)$fatal(1,"LITERAL_TRANSACTION_FAIL");
if(ram[20'h00201]!==8'h34)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00202]!==8'h12)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00203]!==8'h34)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00204]!==8'h12)$fatal(1,"LITERAL_RAM_FAIL");
if(dut.u_eu.gpr[0]!==16'h1234)$fatal(1,"LITERAL_REGISTER_FAIL_AX");
if(dut.u_eu.gpr[3]!==16'h0201)$fatal(1,"LITERAL_REGISTER_FAIL_BX");
if(dut.u_eu.gpr[4]!==16'h0800)$fatal(1,"LITERAL_REGISTER_FAIL_SP");
if(dut.u_eu.sreg[3]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_DS");
if(dut.u_eu.sreg[0]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_ES");
if(dut.u_eu.sreg[2]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_SS");
end
1: begin
if(write_count!=6||write_bytes!=6)$fatal(1,"LITERAL_TRANSACTION_FAIL");
if(ram[20'h00301]!==8'ha5)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00302]!==8'h5a)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00303]!==8'ha5)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00304]!==8'h5a)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00305]!==8'ha5)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00306]!==8'h5a)$fatal(1,"LITERAL_RAM_FAIL");
if(dut.u_eu.gpr[0]!==16'h5AA5)$fatal(1,"LITERAL_REGISTER_FAIL_AX");
if(dut.u_eu.gpr[1]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_CX");
if(dut.u_eu.gpr[7]!==16'h0307)$fatal(1,"LITERAL_REGISTER_FAIL_DI");
if(dut.u_eu.gpr[4]!==16'h0800)$fatal(1,"LITERAL_REGISTER_FAIL_SP");
if(dut.u_eu.sreg[0]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_ES");
end
2: begin
if(write_count!=7||write_bytes!=13)$fatal(1,"LITERAL_TRANSACTION_FAIL");
if(ram[20'h00600]!==8'h01)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00500]!==8'h10)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00501]!==8'h01)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00502]!==8'h00)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00503]!==8'h00)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00504]!==8'h02)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h00505]!==8'hf2)$fatal(1,"LITERAL_RAM_FAIL");
if(dut.u_eu.gpr[0]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_AX");
if(dut.u_eu.gpr[1]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_CX");
if(dut.u_eu.gpr[7]!==16'h0506)$fatal(1,"LITERAL_REGISTER_FAIL_DI");
if(dut.u_eu.gpr[6]!==16'h0800)$fatal(1,"LITERAL_REGISTER_FAIL_SI");
if(dut.u_eu.gpr[4]!==16'h0800)$fatal(1,"LITERAL_REGISTER_FAIL_SP");
if(dut.u_eu.sreg[1]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_CS");
end
3: begin
if(write_count!=3||write_bytes!=6)$fatal(1,"LITERAL_TRANSACTION_FAIL");
if(ram[20'h007fe]!==8'h02)$fatal(1,"LITERAL_RAM_FAIL");
if(ram[20'h007ff]!==8'hf0)$fatal(1,"LITERAL_RAM_FAIL");
if(dut.u_eu.gpr[0]!==16'hF002)$fatal(1,"LITERAL_REGISTER_FAIL_AX");
if(dut.u_eu.gpr[4]!==16'h0800)$fatal(1,"LITERAL_REGISTER_FAIL_SP");
if(dut.u_eu.sreg[2]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_SS");
if(dut.u_eu.sreg[3]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_DS");
if(dut.u_eu.sreg[0]!==16'h0000)$fatal(1,"LITERAL_REGISTER_FAIL_ES");
end
default:$fatal(1,"LITERAL_FAMILY_FAIL");
endcase
endtask
