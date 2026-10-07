// SPDX-License-Identifier: GPL-2.0-only
// Standalone closed-contract checks, not physical NEC pin timing measurements.
module tb_rqak_frontend;
    logic CLK = 0, RESET = 1, CE = 1, CE_HALF = 1;
    logic CORE_QUIET = 1, EXCLUDE = 0;
    logic [1:0] remote_low = 0;
    wire [1:0] RQAK_I_N = ~(remote_low | RQAK_DRIVE_LOW);
    wire [1:0] REQUEST, INTERNAL_GRANT, RQAK_DRIVE_LOW, EXTERNAL_GRANT, PROTOCOL_ERROR;
    wire CORE_CE, CORE_CE_HALF, CORE_BUS_ENABLE;
    v30_rqak_frontend front (.*);
    v30_bus_ownership level_adapter (
        .CLK(CLK), .RESET(RESET), .CE(CE), .CE_HALF(CE_HALF),
        .REQUEST(REQUEST), .CORE_QUIET(CORE_QUIET), .EXCLUDE(EXCLUDE),
        .GRANT(INTERNAL_GRANT), .CORE_CE(CORE_CE), .CORE_CE_HALF(CORE_CE_HALF),
        .CORE_BUS_ENABLE(CORE_BUS_ENABLE)
    );
    int checks = 0;
    string checked_labels[$];
    task automatic tick;
        #1 CLK = 1; #1 CLK = 0; #1;
        if ((INTERNAL_GRANT == 3) || (EXTERNAL_GRANT == 3) || (RQAK_DRIVE_LOW == 3))
            $fatal(1,"one-hot contract violated");
    endtask
    task automatic check(input string label_text, input logic [1:0] req,
                         input logic [1:0] drive, input logic [1:0] external_owner,
                         input logic [1:0] internal_owner, input logic [1:0] errors,
                         input logic enabled);
        bit seen;
        #1; checks++;
        seen = 0;
        foreach (checked_labels[i]) if (checked_labels[i] == label_text) seen = 1;
        if (!seen) checked_labels.push_back(label_text);
        if (REQUEST !== req || RQAK_DRIVE_LOW !== drive ||
            EXTERNAL_GRANT !== external_owner || INTERNAL_GRANT !== internal_owner ||
            PROTOCOL_ERROR !== errors || CORE_BUS_ENABLE !== enabled ||
            CORE_CE !== (CE && enabled) || CORE_CE_HALF !== (CE_HALF && enabled))
            $fatal(1,"%s: req=%b drive=%b ext=%b int=%b err=%b enable=%b",label_text,
                   REQUEST,RQAK_DRIVE_LOW,EXTERNAL_GRANT,INTERNAL_GRANT,PROTOCOL_ERROR,CORE_BUS_ENABLE);
    endtask
    task automatic reset_all;
        RESET = 1; CE = 0; tick();
        check("reset wins CE=0",0,0,0,0,0,1);
        RESET = 0; CE = 1; remote_low = 0; CORE_QUIET = 1; EXCLUDE = 0;
        tick(); // sampled high arms both channels
    endtask
    task automatic acquire(input logic [1:0] channel);
        remote_low = channel; tick();
        remote_low = 0; tick(); tick(); tick();
        // Now ACK has ended (E); E+1 HIGH arms owner.
        tick();
    endtask
    task automatic check_phase(input string label_text, input int expected);
        #1;
        if (int'(front.phase) != expected)
            $fatal(1,"%s: actual phase=%0d expected=%0d",label_text,int'(front.phase),expected);
    endtask
    initial begin
        tick(); check("power reset",0,0,0,0,0,1);
        RESET = 0; tick();
        remote_low = 1; tick(); check("channel0 request retained",1,0,0,0,0,0);
        remote_low = 0; tick(); check("internal ownership precedes ACK",1,0,0,1,0,0);
        tick(); check("ACK0 starts on high",1,1,0,1,0,0);
        CE = 0; tick(); check("ACK CE0 stretch",1,1,0,1,0,0);
        tick(); check("ACK keeps HALF frozen",1,1,0,1,0,0);
        CE = 1; tick(); check("ACK0 end publishes external grant",1,0,1,1,0,0);
        tick(); check("Eplus1 high arms valid owner",1,0,1,1,0,0);
        remote_low = 1; tick(); check("Eplus2 falling accepts return",1,0,0,1,0,0);
        tick(); check("return held low blocks CPU",1,0,0,1,0,0);
        CE = 0; tick(); check("return low CE0 holds",1,0,0,1,0,0);
        CE = 1; remote_low = 0; tick(); check("return high starts gap",1,0,0,1,0,0);
        tick(); check("gap interval one retains REQUEST",1,0,0,1,0,0);
        CE = 0; tick(); check("gap CE0 does not consume interval",1,0,0,1,0,0);
        CE = 1; tick(); check("gap interval two drops REQUEST",0,0,0,1,0,0);
        if (CORE_CE || CORE_CE_HALF) $fatal(1,"release edge must enter frozen");
        tick(); check("level adapter release enables following edge",0,0,0,0,0,1);
        tick(); remote_low = 1; tick();
        check("same owner fresh request after completed return",1,0,0,0,0,0);

        reset_all();
        remote_low = 2; tick(); check("channel1 request",2,0,0,0,0,0);
        tick(); check("held low internal owner without ACK",2,0,0,2,0,0);
        tick(); check("held low cannot start indistinguishable ACK",2,0,0,2,0,0);
        tick(); check("held low creates only one request",2,0,0,2,0,0);
        remote_low = 0; tick(); check("channel1 high starts ACK",2,2,0,2,0,0);
        tick(); check("channel1 own echo masked at ACK end",2,0,2,2,0,0);
        tick(); remote_low = 2; tick();
        check("channel1 valid return",2,0,0,2,0,0);
        remote_low = 0; tick(); tick(); tick(); tick(); tick();
        check("channel1 completed return resumes CPU",0,0,0,0,0,1);

        reset_all(); CORE_QUIET = 0;
        remote_low = 2; tick(); remote_low = 0; tick();
        check("request high cannot cancel busy pending",2,0,0,0,0,1);
        remote_low = 1; tick(); remote_low = 0; tick();
        check("other priority request latched during backlog",3,0,0,0,0,1);
        EXCLUDE = 1; CORE_QUIET = 1; tick();
        check("quiet exclusion retains both requests",3,0,0,0,0,1);
        EXCLUDE = 0; CE = 0; tick();
        check("CE0 cannot acquire pending quiet requests",3,0,0,0,0,1);
        CE = 1; tick(); check("pending channel0 priority at internal grant",3,0,0,1,0,0);
        tick(); check("pending priority before ACK",3,1,0,1,0,0);
        tick(); check("ACK echo cannot create pending owner event",3,0,1,1,0,0);
        tick(); remote_low = 2; tick();
        check("redundant nonowner pulse cannot release owner",3,0,1,1,2,0);
        remote_low = 0; tick(); remote_low = 1; tick();
        check("owner return preserves other pending request",3,0,0,1,2,0);
        remote_low = 0; tick(); tick(); tick();
        check("return only drops owning channel request",2,0,0,1,2,0);
        tick(); tick(); tick();
        check("pending channel1 selected after return",2,2,0,2,2,0);
        tick(); check("pending channel1 ACK end",2,0,2,2,2,0);

        reset_all(); acquire(1);
        check("fresh valid flow no diagnostics",1,0,1,1,0,0);
        // Reset acquire() supplied E+1 HIGH, so reacquire to test malformed E+1.
        reset_all(); remote_low = 1; tick(); remote_low = 0; tick(); tick(); tick();
        check("malformed test ACK end E",1,0,1,1,0,0);
        remote_low = 1; tick(); check("Eplus1 LOW flags before high rearm",1,0,1,1,1,0);
        tick(); check("Eplus2 invalid held low cannot mature",1,0,1,1,1,0);
        tick(); check("Eplus3 invalid held low retains owner",1,0,1,1,1,0);
        remote_low = 0; tick(); check("fresh high rearms rejected return",1,0,1,1,1,0);
        remote_low = 1; tick(); check("fresh later falling returns despite sticky error",1,0,0,1,1,0);
        remote_low = 0; tick(); remote_low = 1; tick();
        check("same-owner gap request rejected",1,0,0,1,1,0);
        tick(); tick(); tick(); tick();
        check("invalid gap low not converted after return",0,0,0,0,1,1);
        remote_low = 0; tick(); remote_low = 1; tick();
        check("fresh high fall after invalid return accepted",1,0,0,0,1,0);

        reset_all(); acquire(1); remote_low = 1; tick();
        remote_low = 0; tick(); check_phase("clean gap entered",5);
        check("clean return gap starts without diagnostic",1,0,0,1,0,0);
        remote_low = 1; tick();
        check("fresh same-owner gap request raises diagnostic",1,0,0,1,1,0);

        // Channel1 arrival during local ACK0 is independently captured.
        reset_all(); remote_low = 1; tick(); remote_low = 0; tick(); tick();
        remote_low = 2; tick(); check("other channel request during ACK echo",3,0,1,1,0,0);
        tick(); check("held other low cannot preempt owner",3,0,1,1,0,0);

        // Both independent-capture coincidences at first observation of an
        // internal owner: a whole-vector armed assignment would erase either.
        reset_all(); remote_low = 1; tick(); remote_low = 0; tick();
        remote_low = 2; tick();
        check("other falling coincides internal owner observation",3,1,0,1,0,0);
        tick(); check("coincident falling consumed once while held low",3,0,1,1,0,0);
        reset_all(); CORE_QUIET = 0;
        remote_low = 3; tick(); remote_low = 2; CORE_QUIET = 1; tick();
        remote_low = 0; tick();
        check("other high rearm coincides internal owner observation",3,1,0,1,0,0);
        remote_low = 2; tick();
        check("coincident high rearm preserves next falling event",3,0,1,1,2,0);

        // Reset in every transaction phase. Low held through reset cannot
        // become a stale request; only sampled high plus a new fall rearms.
        reset_all(); check_phase("pre reset idle",0); reset_all();
        check("reset idle verified predecessor",0,0,0,0,0,1);
        CORE_QUIET = 0; remote_low = 1; tick();
        check_phase("pre reset pending",0);
        if (REQUEST != 1 || (|INTERNAL_GRANT)) $fatal(1,"pending reset precondition absent");
        reset_all();
        check("reset pending",0,0,0,0,0,1);
        remote_low = 1; tick(); tick(); tick(); check_phase("pre reset wait-high",1); reset_all();
        check("reset wait-high",0,0,0,0,0,1);
        remote_low = 1; tick(); remote_low = 0; tick(); tick();
        check_phase("pre reset ACK",2); reset_all();
        check("reset during ACK",0,0,0,0,0,1);
        acquire(2); check_phase("pre reset externally owned",3); reset_all();
        check("reset externally owned",0,0,0,0,0,1);
        acquire(1); remote_low = 1; tick(); check_phase("pre reset return-low",4); reset_all();
        check("reset return-low",0,0,0,0,0,1);
        acquire(1); remote_low = 1; tick(); remote_low = 0; tick();
        check_phase("pre reset return-gap",5); reset_all();
        check("reset return-gap",0,0,0,0,0,1);
        acquire(1); remote_low = 1; tick(); remote_low = 0; tick(); tick(); tick();
        check_phase("pre reset internal release wait",6); reset_all();
        check("reset release-wait",0,0,0,0,0,1);
        remote_low = 3; RESET = 1; tick(); RESET = 0; tick(); tick();
        check("reset low-held inputs do not manufacture requests",0,0,0,0,0,1);
        remote_low = 0; tick(); remote_low = 2; tick();
        check("postreset high then fall rearmed",2,0,0,0,0,0);
        if (checked_labels.size() < 32)
            $fatal(1,"registered distinct check bar missed: %0d",checked_labels.size());
        $display("PASS RQAK frontend contract: %0d distinct checks, %0d total (bar >=32 distinct)",checked_labels.size(),checks);
        $finish;
    end
endmodule
