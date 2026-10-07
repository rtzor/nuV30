// SPDX-License-Identifier: GPL-2.0-only
// Integration simulation of the opt-in utility and the unmodified ucore.
module tb_bus_ownership_core;
    logic CLK = 0, RESET = 1, CE = 1, CE_HALF = 0;
    logic [1:0] REQUEST = 0;
    logic EXCLUDE = 0, READY = 1;
    wire CORE_QUIET, CORE_CE, CORE_CE_HALF, CORE_BUS_ENABLE;
    wire [1:0] GRANT, QS;
    wire [19:0] ADDR_O;
    wire [15:0] DATA_O, SS_RDATA;
    wire [3:0] STATUS_O;
    wire [2:0] BS;
    wire RD_N, UBE_N, BUSLOCK_N, SS_ERR;
    logic [15:0] DATA_I;
    wire [223:0] dbg_regs, ref_regs;
    wire [19:0] ref_addr;
    wire [15:0] ref_data;
    wire [3:0] ref_status;
    wire [2:0] ref_bs;
    wire [1:0] ref_qs;
    wire ref_rd, ref_ube, ref_lock;
    v30_bus_ownership arb (.*);
    v30_core dut (
        .CLK(CLK), .CE(CORE_CE), .RESET(RESET), .READY(READY),
        .INT(1'b0), .NMI(1'b0), .POLL_N(1'b1),
        .DATA_I(DATA_I), .ADDR_O(ADDR_O), .DATA_O(DATA_O),
        .STATUS_O(STATUS_O), .QS(QS), .BS(BS), .RD_N(RD_N),
        .UBE_N(UBE_N), .BUSLOCK_N(BUSLOCK_N),
        .SS_ADDR('0), .SS_WDATA('0), .SS_WE(1'b0),
        .SS_RDATA(SS_RDATA), .SS_ERR(SS_ERR), .SS_BUS_QUIET(CORE_QUIET),
        .bkd_load(1'b0), .bkd_regs('0), .bkd_queue('0), .bkd_qlen('0),
        .bkd_fetch_ip('0), .scr_en(1'b0), .scr_qop('0),
        .dbg_regs(dbg_regs), .dbg_first_pop(), .dbg_pend()
    );
    v30_core reference_core (
        .CLK(CLK), .CE(CE), .RESET(RESET), .READY(READY),
        .INT(1'b0), .NMI(1'b0), .POLL_N(1'b1),
        .DATA_I({byte_at({ref_addr[19:1],1'b1}),byte_at({ref_addr[19:1],1'b0})}),
        .ADDR_O(ref_addr), .DATA_O(ref_data), .STATUS_O(ref_status),
        .QS(ref_qs), .BS(ref_bs), .RD_N(ref_rd), .UBE_N(ref_ube), .BUSLOCK_N(ref_lock),
        .SS_ADDR('0), .SS_WDATA('0), .SS_WE(1'b0),
        .SS_RDATA(), .SS_ERR(), .SS_BUS_QUIET(),
        .bkd_load(1'b0), .bkd_regs('0), .bkd_queue('0), .bkd_qlen('0),
        .bkd_fetch_ip('0), .scr_en(1'b0), .scr_qop('0),
        .dbg_regs(ref_regs), .dbg_first_pop(), .dbg_pend()
    );
    // Public instruction bytes, no firmware: DIV CX gives prefetch time to fill.
    // MOV AX,1; MOV CX,1; XOR DX,DX; DIV CX; JMP back to XOR.
    function automatic logic [7:0] byte_at(input logic [19:0] address);
        case (address)
            20'hffff0: byte_at = 8'hb8;
            20'hffff1: byte_at = 8'h01;
            20'hffff2: byte_at = 8'h00;
            20'hffff3: byte_at = 8'hb9;
            20'hffff4: byte_at = 8'h01;
            20'hffff5: byte_at = 8'h00;
            20'hffff6: byte_at = 8'h31;
            20'hffff7: byte_at = 8'hd2;
            20'hffff8: byte_at = 8'hf7;
            20'hffff9: byte_at = 8'hf1;
            20'hffffa: byte_at = 8'heb;
            20'hffffb: byte_at = 8'hfa;
            default: byte_at = 8'h90;
        endcase
    endfunction
    always_comb DATA_I = {byte_at({ADDR_O[19:1],1'b1}),
                          byte_at({ADDR_O[19:1],1'b0})};
    task automatic tick;
        #1 CLK = 1; #1 CLK = 0;
    endtask
    logic [47:0] frozen;
    logic [223:0] frozen_regs;
    logic [19:0] frozen_queue;
    logic [7:0] frozen_bytes [0:5];
    int clocks;
    initial begin
        repeat (24) tick(); RESET = 0;
        repeat (200) begin
            tick();
            if (dbg_regs !== ref_regs ||
                {ADDR_O, DATA_O, STATUS_O, BS, RD_N, UBE_N, QS, BUSLOCK_N} !==
                {ref_addr, ref_data, ref_status, ref_bs, ref_rd, ref_ube, ref_qs, ref_lock})
                $fatal(1, "no-request adapter changed raw core behavior");
        end
        // Wait until the real core is in a bus read, then hold READY low.
        clocks = 0;
        while (RD_N && clocks < 2000) begin tick(); clocks++; end
        if (RD_N) $fatal(1, "core did not begin instruction fetch");
        READY = 0; REQUEST = 1;
        repeat (16) begin
            tick();
            if ((|GRANT) || !CORE_CE || CORE_QUIET)
                $fatal(1, "ownership transferred during READY wait");
        end
        READY = 1;
        clocks = 0;
        while (!(|GRANT) && clocks < 5000) begin
            // If quiet is reached, acquisition must inhibit this very edge.
            #1;
            if (CORE_QUIET && CORE_CE) $fatal(1, "acquisition edge ungated");
            tick(); clocks++;
        end
        if (GRANT != 1) $fatal(1, "core did not reach quiet boundary");
        frozen = {ADDR_O, DATA_O, STATUS_O, BS, RD_N, UBE_N, QS, BUSLOCK_N};
        frozen_regs = dbg_regs;
        frozen_queue = {dut.u_biu.r_q_cnt, dut.u_biu.r_fetch_ptr};
        for (int i = 0; i < 6; i++) frozen_bytes[i] = dut.u_biu.r_q_mem[i];
        repeat (32) begin
            tick();
            if (CORE_CE || CORE_BUS_ENABLE || dbg_regs !== frozen_regs ||
                {dut.u_biu.r_q_cnt, dut.u_biu.r_fetch_ptr} !== frozen_queue ||
                frozen !== {ADDR_O, DATA_O, STATUS_O, BS, RD_N, UBE_N, QS, BUSLOCK_N})
                $fatal(1, "core changed while granted");
            for (int i = 0; i < 6; i++)
                if (frozen_bytes[i] !== dut.u_biu.r_q_mem[i])
                    $fatal(1, "prefetch bytes changed while granted");
        end
        REQUEST = 0; #1;
        if (CORE_CE) $fatal(1, "release edge ungated");
        tick();
        if (!CORE_CE) $fatal(1, "core did not resume");
        clocks = 0;
        while ({ADDR_O, DATA_O, STATUS_O, BS, RD_N, UBE_N, QS, BUSLOCK_N} === frozen &&
               clocks < 5000) begin tick(); clocks++; end
        if (clocks == 5000) $fatal(1, "core made no progress after resume");
        // Distinct grant with a full six-byte prefetch queue, not an empty
        // post-reset bus: the slow division lets prefetch fill naturally.
        clocks = 0;
        while (!(CORE_QUIET && dut.u_biu.r_q_cnt == 6) && clocks < 10000) begin
            tick(); clocks++;
        end
        if (clocks == 10000) $fatal(1, "full prefetch quiet boundary not reached");
        REQUEST = 1; #1;
        if (CORE_CE) $fatal(1, "full queue acquisition edge ungated");
        tick();
        if (GRANT != 1 || dut.u_biu.r_q_cnt != 6)
            $fatal(1, "full queue acquisition failed");
        $display("PASS real ucore READY drain, acquisition, frozen bus, resume");
        $finish;
    end
endmodule
