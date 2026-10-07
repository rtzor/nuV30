// SPDX-License-Identifier: GPL-2.0-only
// Executable-byte integration tests for the FPGA exclusion guard, not NEC
// physical LOCK/RQ/GT timing. Two identical cores compare without requests.
module tb_bus_exclusion;
    logic clk = 0, reset = 1, bkd_load = 0;
    logic [223:0] bkd_regs = 0;
    logic pin_int = 0, pin_nmi = 0;
    logic [1:0] request = 0;
    wire [1:0] grant;
    wire core_ce, core_half, bus_enable;
    wire [1:0] quiet, exclude, rd, ube, buslock;
    wire [19:0] addr [2];
    wire [15:0] data_o [2];
    logic [15:0] data_i [2];
    wire [3:0] status_o [2];
    wire [2:0] bs [2];
    wire [1:0] qs [2];
    wire [223:0] regs [2];
    wire [2:0] actual_phase [2];
    wire [2:0] actual_page [2];
    wire [5:0] actual_eu_state [2];
    logic [7:0] mem [2][65536];
    logic ready [2];
    int phase [2], waits_left [2], cycle_kind [2], cycle_addr [2];
    logic cycle_ube [2];
    int writes [2], intas [2];
    int wait_mode = 0, case_id = 0;
    wire [1:0] enables = {1'b1,core_ce};
    v30_bus_ownership arb (
        .CLK(clk), .RESET(reset), .CE(1'b1), .CE_HALF(1'b0),
        .REQUEST(request), .CORE_QUIET(quiet[0]), .EXCLUDE(exclude[0]),
        .GRANT(grant), .CORE_CE(core_ce), .CORE_CE_HALF(core_half),
        .CORE_BUS_ENABLE(bus_enable)
    );
    for (genvar g = 0; g < 2; g++) begin : cores
        v30_core cpu (
            .CLK(clk), .CE(enables[g]), .RESET(reset), .READY(ready[g]),
            .INT(pin_int), .NMI(pin_nmi), .POLL_N(1'b1),
            .DATA_I(data_i[g]), .ADDR_O(addr[g]), .DATA_O(data_o[g]),
            .STATUS_O(status_o[g]), .QS(qs[g]), .BS(bs[g]),
            .RD_N(rd[g]), .UBE_N(ube[g]), .BUSLOCK_N(buslock[g]),
            .BUS_EXCLUDE(exclude[g]), .SS_ADDR('0), .SS_WDATA('0),
            .SS_WE(1'b0), .SS_RDATA(), .SS_ERR(), .SS_BUS_QUIET(quiet[g]),
            .bkd_load(bkd_load), .bkd_regs(bkd_regs), .bkd_queue('0),
            .bkd_qlen('0), .bkd_fetch_ip('0), .scr_en(1'b0),
            .scr_qop('0), .dbg_regs(regs[g]), .dbg_first_pop(), .dbg_pend()
        );
        assign actual_phase[g] = cpu.u_biu.r_ts;
        assign actual_page[g] = cpu.u_eu.upc_page;
        assign actual_eu_state[g] = cpu.u_eu.st;
        always_comb begin
            ready[g] = waits_left[g] == 0;
            data_i[g] = cycle_kind[g] == 0 ? 16'h0020 :
                {mem[g][{addr[g][15:1],1'b1}],mem[g][{addr[g][15:1],1'b0}]};
        end
    end
    task automatic tick;
        logic [1:0] consume_wait;
        // Model T1/T2/T3/Tw/T4 from public BS and READY. Advance with the
        // same enable as its CPU, so ownership never commits a frozen cycle.
        #1;
        consume_wait = 0;
        for (int g = 0; g < 2; g++) begin
            if (reset) begin
                phase[g] = 0; waits_left[g] = 0;
                writes[g] = 0; intas[g] = 0; cycle_kind[g] = 7;
            end else if (enables[g]) begin
                if (phase[g] == 0 || phase[g] == 5) begin
                    if (bs[g] != 7) begin
                        phase[g] = 1; cycle_kind[g] = int'(bs[g]);
                        cycle_addr[g] = int'(addr[g][15:0]);
                        cycle_ube[g] = ube[g];
                        waits_left[g] = wait_mode;
                        if (bs[g] == 0) intas[g]++;
                    end else phase[g] = 0;
                end else if (phase[g] == 1 || phase[g] == 2) begin
                    // BS announces before T1; UBE_N can retain the previous
                    // cycle on a zero-age announcement. Capture lanes on the
                    // following real T1, not the announcement's stale value.
                    if (phase[g] == 1) begin
                        if (cycle_kind[g] == 6 && actual_phase[g] != 1)
                            $fatal(1,"write lane sample is not actual T1");
                        cycle_ube[g] = ube[g];
                    end
                    phase[g]++;
                end
                else if ((phase[g] == 3 || phase[g] == 4) && !ready[g]) begin
                    phase[g] = 4; consume_wait[g] = 1;
                end else begin
                    phase[g] = 5;
                    if (cycle_kind[g] == 6) begin
                        writes[g]++;
                        // Write data may arrive via the existing paired-store
                        // forwarding path after T1. Sample it at completion;
                        // address and lane selection remain the T1 snapshots.
                        if ((cycle_addr[g] & 1) != 0) begin
                            if (!cycle_ube[g]) mem[g][cycle_addr[g]] = data_o[g][15:8];
                        end else begin
                            mem[g][cycle_addr[g]] = data_o[g][7:0];
                            if (!cycle_ube[g]) mem[g][cycle_addr[g]+1] = data_o[g][15:8];
                        end
                    end
                end
            end
        end
        #1 clk = 1; #1 clk = 0;
        for (int g = 0; g < 2; g++) if (consume_wait[g]) waits_left[g]--;
    endtask
    task automatic load_case(input int kind, input int waits);
        reset = 1; bkd_load = 1; pin_int = 0; pin_nmi = 0; request = 0;
        case_id = kind; wait_mode = waits;
        bkd_regs = 0;
        bkd_regs[0 +: 16] = 16'h1234;
        bkd_regs[16 +: 16] = 3;
        bkd_regs[64 +: 16] = 16'h0800;
        bkd_regs[96 +: 16] = 16'h0300;
        bkd_regs[112 +: 16] = 16'h0400;
        bkd_regs[208 +: 16] = kind == 5 ? 16'h0202 : 16'h0002;
        for (int g = 0; g < 2; g++) begin
            for (int i = 0; i < 65536; i++) mem[g][i] = 8'h90;
            // All interrupt vectors used here point to 0000:0100.
            mem[g][8] = 0; mem[g][9] = 1; mem[g][10] = 0; mem[g][11] = 0;
            mem[g][128] = 0; mem[g][129] = 1; mem[g][130] = 0; mem[g][131] = 0;
            mem[g][256] = 8'h90; mem[g][257] = 8'h26;
            mem[g][258] = 8'h90; mem[g][259] = 8'hf4;
            mem[g][512] = 1; mem[g][513] = 0; mem[g][514] = 0;
            mem[g][768] = 8'h11; mem[g][769] = 8'h11;
            mem[g][770] = 8'h22; mem[g][771] = 8'h22;
            mem[g][772] = 8'h33; mem[g][773] = 8'h33;
            if (kind == 2) begin
                mem[g][512] = 8'ha5; mem[g][513] = 1;
                mem[g][514] = 0; mem[g][515] = 8'h5a;
            end
            if (kind == 0) begin
                mem[g][0] = 8'hff; mem[g][1] = 8'h06;
                mem[g][2] = 0; mem[g][3] = 2; mem[g][4] = 8'hf4;
            end else if (kind == 1 || kind == 2) begin
                mem[g][0] = 8'hf0; mem[g][1] = 8'hff; mem[g][2] = 8'h06;
                mem[g][3] = kind == 2 ? 1 : 0; mem[g][4] = 2;
                mem[g][5] = 8'h90; mem[g][6] = 8'h26;
                mem[g][7] = 8'h90; mem[g][8] = 8'hf4;
            end else if (kind == 3) begin
                mem[g][0] = 8'hf0; mem[g][1] = 8'hf3;
                mem[g][2] = 8'ha5; mem[g][3] = 8'h90; mem[g][4] = 8'hf4;
            end else if (kind == 4) begin
                mem[g][0] = 8'hf0; mem[g][1] = 8'hf4;
            end else begin
                mem[g][0] = 8'h90; mem[g][1] = 8'h90; mem[g][2] = 8'hf4;
            end
        end
        repeat (4) tick(); reset = 0; bkd_load = 0;
    endtask
    task automatic compare_raw;
        if (regs[0] !== regs[1] || quiet[0] !== quiet[1] || exclude[0] !== exclude[1] ||
            {addr[0],data_o[0],status_o[0],bs[0],qs[0],rd[0],ube[0],buslock[0]} !==
            {addr[1],data_o[1],status_o[1],bs[1],qs[1],rd[1],ube[1],buslock[1]})
            $fatal(1,"raw comparison failed case=%0d wait=%0d",case_id,wait_mode);
        if (!buslock[0]) $fatal(1,"native BUSLOCK_N unexpectedly changed");
    endtask
    int guarded_quiet, inta_gap, guard_cycles, stale_clear;
    int protected_writes;
    logic requested, saw_guard;
    initial begin
        for (int w = 0; w < 3; w++) begin
            for (int c = 0; c < 6; c++) begin
                load_case(c, w == 2 ? 3 : w);
                guarded_quiet = 0; inta_gap = 0; guard_cycles = 0; stale_clear = 0;
                protected_writes = c == 1 ? 1 : c == 2 ? 2 : c == 3 ? 3 : 0;
                saw_guard = 0;
                for (int n = 0; n < 1500; n++) begin
                    if (c == 5 && n == 30) pin_int = 1;
                    if (exclude[0]) begin guard_cycles++; saw_guard = 1; end
                    if (saw_guard && writes[0] < protected_writes && !exclude[0])
                        $fatal(1,"guard released before last protected write case=%0d wait=%0d",c,wait_mode);
                    if (exclude[0] && quiet[0]) guarded_quiet++;
                    if (c == 5 && intas[0] == 1 && bs[0] == 7) begin
                        inta_gap++;
                        if (!exclude[0]) $fatal(1,"IRQ gap exclusion dropped");
                    end
                    if (c == 5 && intas[0] == 2 && actual_page[0] == 7 &&
                        actual_eu_state[0] < 22 && !exclude[0]) stale_clear++;
                    tick(); compare_raw();
                end
                if (c == 0 && guard_cycles != 0) $fatal(1,"unlocked instruction guarded");
                if (c != 0 && guard_cycles == 0)
                    $fatal(1,"guard coverage absent case=%0d wait=%0d",c,wait_mode);
                // REP may maintain a continuously busy BIU under waits. Its
                // absence of a quiet opportunity is reported, not invented.
                if (c != 0 && c != 3 && guarded_quiet == 0)
                    $fatal(1,"quiet exclusion coverage absent case=%0d wait=%0d",c,wait_mode);
                if (c == 5 && (intas[0] != 2 || inta_gap == 0 || exclude[0] || stale_clear == 0))
                    $fatal(1,"IRQ pair/gap/successor coverage absent");
                if (c == 3 && (regs[0][16 +: 16] != 0 || writes[0] < 3))
                    $fatal(1,"REP did not complete multiple iterations");
                if (c == 1 && {mem[0][513],mem[0][512]} != 16'h0002)
                    $fatal(1,"even RMW result wrong: %04x",{mem[0][513],mem[0][512]});
                if (c == 2 && ({mem[0][514],mem[0][513]} != 16'h0002 ||
                    mem[0][512] != 8'ha5 || mem[0][515] != 8'h5a || writes[0] < 2))
                    $fatal(1,"odd split RMW/lane preservation wrong: bytes=%02x %02x %02x %02x writes=%0d",mem[0][512],mem[0][513],mem[0][514],mem[0][515],writes[0]);
                if (c == 3 && ({mem[0][1025],mem[0][1024]} != 16'h1111 ||
                    {mem[0][1027],mem[0][1026]} != 16'h2222 ||
                    {mem[0][1029],mem[0][1028]} != 16'h3333))
                    $fatal(1,"REP memory results wrong");
                if (c != 4 && exclude[0]) $fatal(1,"successor retained stale guard");
                if (c == 4 && !exclude[0]) $fatal(1,"locked HALT lost guard");
                // Repeat identical workload with a level request raised only
                // after genuine native guard has asserted.
                load_case(c, w == 2 ? 3 : w); requested = 0; saw_guard = 0;
                for (int n = 0; n < 1500; n++) begin
                    if (c == 5 && n == 30) pin_int = 1;
                    if (exclude[0]) begin
                        saw_guard = 1; request = 1; requested = 1;
                        #1;
                        if ((|grant) || !core_ce) $fatal(1,"grant during exclusion");
                    end
                    if (c == 0 && n == 30) begin request = 1; requested = 1; end
                    if (saw_guard && writes[0] < protected_writes && !exclude[0])
                        $fatal(1,"request run released guard before protected writes");
                    tick();
                    if ((|grant)) begin
                        if (exclude[0]) $fatal(1,"owned state excludes unexpectedly");
                        if (c == 3 && regs[0][16 +: 16] != 0)
                            $fatal(1,"REP granted before final iteration");
                        if (c == 5 && intas[0] != 2)
                            $fatal(1,"IRQ granted before both acknowledge cycles");
                        break;
                    end
                end
                if (!requested || (c != 0 && !saw_guard)) $fatal(1,"request coverage absent");
                if (c == 4) begin
                    if ((|grant) || !exclude[0]) $fatal(1,"locked HALT incorrectly granted");
                    // NMI wakes the retained locked HALT. Its internal entry
                    // remains excluded until the handler's ordinary successor.
                    pin_nmi = 1;
                    for (int n = 0; n < 1500; n++) begin
                        if (exclude[0] && (|grant)) $fatal(1,"NMI wake granted during entry");
                        tick();
                        if ((|grant)) break;
                    end
                    if (!(|grant) || exclude[0]) $fatal(1,"NMI wake did not release guard");
                    reset = 1; tick();
                    if ((|grant) || !core_ce || exclude[0]) $fatal(1,"reset did not clear exclusion");
                end else if (!(|grant)) $fatal(1,"eligible request never granted");
                $display("PASS native guard case=%0d waits=%0d guard_cycles=%0d quiet=%0d gap=%0d stale_clear=%0d",c,wait_mode,guard_cycles,guarded_quiet,inta_gap,stale_clear);
            end
        end
        $display("PASS FPGA native-state guard: 18 case/wait combinations");
        $finish;
    end
endmodule
