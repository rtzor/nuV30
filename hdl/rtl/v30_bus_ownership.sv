// SPDX-License-Identifier: GPL-2.0-only
// External integration utility, not a model of NEC HOLD/HLDA or RQ/GT pins.
// All inputs are synchronous to CLK. Connect CORE_QUIET to SS_BUS_QUIET.
// SS state writes are prohibited during arbitration. CE_HALF is optional at
// the core; tie it low when the selected core has no half-clock enable.
// EXCLUDE must come from a genuine external atomic-operation guard: the
// BUSLOCK_N is constant inactive only with V30_STAGED_LOCK_DIV5 disabled.
// Use the separate BUS_EXCLUDE guard; this whole-core freeze adapter does not
// support the staged controller's uninterrupted five-CE profile.
// Set EXCLUDE only while the CPU owns the bus. It cannot revoke a grant.
// The system must use CORE_BUS_ENABLE to isolate/mux all CPU bus drivers.
// This freezes the entire core at a registered quiet boundary, with no bound
// on grant latency (ongoing requests/prefetch may delay CORE_QUIET).
// INT/NMI pulses occurring wholly while frozen are not sampled by the core;
// integration must retain events externally until the core can sample them.
// CORE_CE/CORE_CE_HALF are register enables; never use them to gate CLK.
// CORE_BUS_ENABLE is combinational, not a glitch-free output-enable signal:
// use it in synchronous external bus mux/isolation logic. RESET ungates the
// CPU bus before stale GRANT clears; external masters must stop driving on
// RESET independently of GRANT.
module v30_bus_ownership (
    input  logic       CLK,
    input  logic       RESET,
    input  logic       CE,
    input  logic       CE_HALF,
    input  logic [1:0] REQUEST,
    input  logic       CORE_QUIET,
    input  logic       EXCLUDE,
    output logic [1:0] GRANT,
    output logic       CORE_CE,
    output logic       CORE_CE_HALF,
    output logic       CORE_BUS_ENABLE
);
    logic acquire;
    // Gate the acquisition edge itself: the EU must not post a new request
    // on the same clock that transfers bus ownership.
    assign acquire = CE && !(|GRANT) && CORE_QUIET && !EXCLUDE && (|REQUEST);
    assign CORE_BUS_ENABLE = RESET || (!(|GRANT) && !acquire);
    assign CORE_CE = CE && CORE_BUS_ENABLE;
    assign CORE_CE_HALF = CE_HALF && CORE_BUS_ENABLE;

    always_ff @(posedge CLK) begin
        if (RESET)
            GRANT <= 2'b00;
        else if (CE) begin
            if (|GRANT) begin
                // No preemption. Release edge remains frozen; resume next
                // eligible clock unless a new ownership request wins it.
                if (!(|(GRANT & REQUEST))) GRANT <= 2'b00;
            end else if (acquire)
                GRANT <= REQUEST[0] ? 2'b01 : 2'b10;
        end
    end
endmodule
