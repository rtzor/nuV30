// SPDX-License-Identifier: GPL-2.0-only
// Contract tests for the external utility; no NEC silicon timing claim.
module tb_bus_ownership;
    logic CLK = 0, RESET = 1, CE = 1, CE_HALF = 1;
    logic [1:0] REQUEST = 0;
    logic CORE_QUIET = 1, EXCLUDE = 0;
    wire [1:0] GRANT;
    wire CORE_CE, CORE_CE_HALF, CORE_BUS_ENABLE;
    v30_bus_ownership dut (.*);
    int checks = 0;
    task automatic expect_outputs(input logic [1:0] owner,
                                  input logic enabled,
                                  input string label_text);
        #1;
        checks++;
        if (GRANT !== owner || CORE_BUS_ENABLE !== enabled ||
            CORE_CE !== (CE && enabled) ||
            CORE_CE_HALF !== (CE_HALF && enabled))
            $fatal(1, "%s: grant=%b enabled=%b CE=%b HALF=%b",
                   label_text, GRANT, CORE_BUS_ENABLE, CORE_CE, CORE_CE_HALF);
    endtask
    task automatic tick;
        #1 CLK = 1;
        #1 CLK = 0;
    endtask
    initial begin
        tick(); expect_outputs(0, 1, "reset"); RESET = 0;
        CE = 0; REQUEST = 3;
        expect_outputs(0, 1, "CE off retains HALF"); tick();
        expect_outputs(0, 1, "CE off cannot acquire");
        CE = 1; CORE_QUIET = 0;
        repeat (5) begin
            expect_outputs(0, 1, "READY wait / prefetch backlog drains"); tick();
        end
        REQUEST = 0; CORE_QUIET = 1;
        tick(); expect_outputs(0, 1, "withdrawn request canceled");
        REQUEST = 3; EXCLUDE = 1;
        tick(); expect_outputs(0, 1, "atomic guard excludes acquisition");
        EXCLUDE = 0;
        expect_outputs(0, 0, "acquisition edge gates both enables");
        tick(); expect_outputs(1, 0, "simultaneous channel zero priority");
        EXCLUDE = 1; tick(); expect_outputs(1, 0, "guard cannot revoke owner");
        EXCLUDE = 0; CE = 0; REQUEST = 2;
        tick(); expect_outputs(1, 0, "release waits for CE");
        CE = 1; expect_outputs(1, 0, "release edge frozen");
        tick(); expect_outputs(0, 0, "next acquisition edge frozen");
        tick(); expect_outputs(2, 0, "channel one granted after release");
        REQUEST = 3; tick(); expect_outputs(2, 0, "priority cannot preempt owner");
        REQUEST = 0; expect_outputs(2, 0, "final release edge frozen");
        tick(); expect_outputs(0, 1, "resume following clock");
        REQUEST = 2; tick(); expect_outputs(2, 0, "reacquire");
        RESET = 1; REQUEST = 3;
        expect_outputs(2, 1, "reset delivered even while owned");
        tick(); expect_outputs(0, 1, "reset beats simultaneous requests");
        RESET = 0; CE_HALF = 0;
        expect_outputs(0, 0, "demultiplexed core acquisition");
        tick(); expect_outputs(1, 0, "demultiplexed owner");
        REQUEST = 0; tick(); expect_outputs(0, 1, "demultiplexed resume");
        $display("PASS bus ownership contract: %0d output checks", checks);
        $finish;
    end
endmodule
