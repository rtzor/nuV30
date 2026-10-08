// SPDX-License-Identifier: GPL-2.0-only
// Disjoint public-controller population; not CPU/native pin timing evidence.
module tb_mux_yield_handover;
    logic clk=0, reset=1, ce=0, half_ce=0, quiet=0, exclude=0;
    logic [1:0] request=0;
    wire [1:0] grant;
    wire bus_enable, core_ce, core_half;
    int profiles=0;
    v30_bus_ownership dut (.CLK(clk),.RESET(reset),.CE(ce),.CE_HALF(half_ce),
        .REQUEST(request),.CORE_QUIET(quiet),.EXCLUDE(exclude),.GRANT(grant),
        .CORE_CE(core_ce),.CORE_CE_HALF(core_half),.CORE_BUS_ENABLE(bus_enable));
    task automatic edge_check(input logic enable,input logic half_enable,
        input logic pre_permission,input logic post_permission,input logic [1:0] post_grant);
        logic [1:0] old_grant;
        ce=enable; half_ce=half_enable; #1; old_grant=grant;
        if(bus_enable!=pre_permission) $fatal(1,"handover pre-edge permission failure");
        if(core_ce!=(ce && bus_enable) || core_half!=(half_ce && bus_enable)) $fatal(1,"controller enable equation failure");
        clk=1; #1; clk=0; #1;
        if(bus_enable!=post_permission || grant!=post_grant) $fatal(1,"handover post-edge grant/permission failure");
        if(!ce && !reset && grant!=old_grant) $fatal(1,"GRANT changed on CE0");
        if(grant==3) $fatal(1,"non-onehot unit grant");
    endtask
    int divs[5]='{2,3,4,5,8};
    initial begin
        for(int d=0;d<5;d++) for(int order=0;order<2;order++) begin
            logic [1:0] first_owner, second_owner;
            int divisor;
            divisor=divs[d]; first_owner=order==0 ? 2'b01 : 2'b10;
            second_owner=order==0 ? 2'b10 : 2'b01;
            reset=1; quiet=0; exclude=0; request=0; edge_check(0,0,1,1,0); reset=0;
            // Neither nonquiet nor excluded pending requests reserve permission.
            request=first_owner; quiet=0; edge_check(0,1,1,1,0);
            quiet=1; exclude=1; edge_check(0,0,1,1,0);
            exclude=0;
            for(int f=1;f<divisor;f++) edge_check(0,f==divisor/2,0,0,0);
            edge_check(1,0,0,0,first_owner);
            // Existing owner is sticky despite later exclusion/nonquiet and
            // an additional requester. At least four eligible CE intervals.
            request=3; quiet=0; exclude=1;
            for(int n=0;n<4;n++) begin
                for(int f=1;f<divisor;f++) edge_check(0,f==divisor/2,0,0,first_owner);
                edge_check(1,0,0,0,first_owner);
            end
            request=second_owner; quiet=1; exclude=0;
            for(int f=1;f<divisor;f++) edge_check(0,f==divisor/2,0,0,first_owner);
            edge_check(1,0,0,0,0);
            // Queued release and later acquisition stay isolated on EVERY edge.
            for(int f=1;f<divisor;f++) edge_check(0,f==divisor/2,0,0,0);
            edge_check(1,0,0,0,second_owner);
            for(int n=0;n<4;n++) begin
                for(int f=1;f<divisor;f++) edge_check(0,f==divisor/2,0,0,second_owner);
                edge_check(1,0,0,0,second_owner);
            end
            request=0;
            for(int f=1;f<divisor;f++) edge_check(0,f==divisor/2,0,0,second_owner);
            edge_check(1,0,0,1,0);
            for(int f=1;f<divisor;f++) edge_check(0,f==divisor/2,1,1,0);
            // RESET cancels eligible pending acquisition before actual CE.
            request=first_owner; edge_check(0,1,0,0,0);
            reset=1; edge_check(0,0,1,1,0); request=0; reset=0;
            edge_check(1,0,1,1,0);
            profiles++; $display("PASS mux disjoint handover divisor=%0d first=%b second=%b ownerCE=4/4",divisor,first_owner,second_owner);
        end
        if(profiles!=10) $fatal(1,"exact ten disjoint handover profiles missing");
        $display("PASS mux disjoint public controller profiles=%0d",profiles); $finish;
    end
endmodule
