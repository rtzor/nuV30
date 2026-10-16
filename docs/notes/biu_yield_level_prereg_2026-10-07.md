# Experimental BIU yield, level interface — design/preregistration

Baseline `defe5a00`; document-only proposal. Parent review and commit must precede RTL, testbench or acceptance runs. The existing whole-core ownership utility and RQ/AK protocol retain their present scope. No physical native yield/resume claim, minimum-mode change, production/private integration or board contact is authorized.

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted.
Complex or confusing observed behavior is likely simple systems interacting in ways not yet understood. A large fitted table, a many-cased rule, or a per-opcode special case is a signal of misunderstanding, not a deliverable.

## Mechanism proposed from source

Macro `V30_BIU_YIELD` requires `V30_BUS_OWNERSHIP` and rejects `V30_MUXED_AD` at compile/elaboration. Negative probes must fail explicitly for yield-without-guard and yield-plus-mux; silently ignoring either configuration is forbidden.

Opt-in core/BIU level inputs `YIELD_PENDING` and `BUS_OWNED`, output `YIELD_READY`. No new core flop, queue, counter or SS address. The existing external ownership controller stores the owner. Its REQUEST OR drives YIELD_PENDING; CORE_BUS_ENABLE inverted supplies BUS_OWNED, including the inhibited acquisition edge. Ignore the controller's CORE_CE/CORE_CE_HALF outputs: core CE remains live. External BUS_EXCLUDE uses the existing native-state conservative guard.

YIELD_READY depends only on existing registered state: no running cycle, no announced commitment, and no started split awaiting its partner. It does not require the EU request queue to be empty, nor a pending HALT status to be consumed. It is false in 8080 mode. Do not replace or reinterpret SS_BUS_QUIET.

New previews and scheduling commitments are inhibited by BUS_OWNED, or by YIELD_PENDING when native mode is active, exclusion is clear and no split is in flight. The ordinary arbitration block, separate HALT commitment and new physical previews all require this inhibitor. Existing registered cmt display and T1 drain are not blanket-masked. Existing cmt announcements continue their normal T1/drain/withdrawal behavior; do not gate T-state advancement, delivery, queue consumption, counters or SS-mapped state wholesale.

While exclusion or a started split requires CPU ownership, a pending external request does not inhibit the bus launches needed to finish that operation. Otherwise LOCK/INTA would deadlock. Once owned, exclusion arising from subsequent EU progress cannot revoke ownership or allow a new CPU launch. EU progress during ownership is an engineering expectation derived from existing interlocks, not a silicon fact.

## Registered boundary and split reasoning

The proposed split-started predicate is `!r_cur_rd_last && (r_run || r_cmt_valid || r_rq_n != 0)`. It uses the last cycle actually launched and actual outstanding backing state, not `r_rd_was_split` (which also carries an INTA debt). Acquisition independently requires !r_run and !r_cmt_valid, so the relevant idle-gap case is a retained non-last current cycle with its partner still queued. Before a split's first T1, the previous current cycle remains last and the entire queued split may wait for ownership to return. Once the second T1 replaces current metadata, its last bit is true, but the running-cycle exclusion prevents acquisition until drain. This predicate is a candidate invariant of reachable execution without SS mutation, to be falsified by directed traces, not declared a hardware rule.

Source anchors in `hdl/rtl/ucore/v30u_biu.sv`:

- 1967–2015: same-edge EU post, two-entry backing store and split last markers.
- 2302–2392: selection/consumption and cmt creation, including prefetch pointer/debt changes.
- 2494–2525: committed T1 launch, current last marker and final-cycle slot release.
- 2542–2557: separate HALT cmt creation.
- 2438–2475: existing expiry/requeue behavior; retain it unchanged.
- 1907, 2190–2299: completion counters, landing and split/INTA debts; retain advancement.
- 901–924: registered/next slot views and completion publication; retain the existing EU contract.
- 926: existing SS quiet requires rq_n=0 and is intentionally a different predicate.

## Preview hazard and required distinction

Scheduler/HALT gating alone is insufficient: `bs` selects `inta_preview`, `vector_follow_preview` and `flush_fast` ahead of registered display (`994–998`). Vector preview also selects address and bus-half (`1152–1166`); flush_fast affects address/output-enable and direct launch (`1211–1230`, `2496–2509`). A branch or late interrupt during ownership could otherwise manufacture a public announcement without a cmt.

Qualify the physical/new-launch preview rails with the registered-boundary yield inhibitor, preserving existing cmt display and running-cycle outputs. Do not substitute a constant for the whole public BS mux. No qualified preview feeds EU combinational decode: EU direct-fetch/tail lookahead remains derived from registered running/landing state. Arbitration/preview suppression may change the next-state view read by EU flops, consistent with the existing registered/next contract.

However, `inta_follow_preview` and `vector_follow_preview` also clear `rd_was_split` at 2295–2296. Globally qualifying their existing definitions would suppress that internal debt consumption on an accepted EU post while owned. After return, the post is already queued and does not repeat; the stale bit can enter later read composition. Therefore distinguish raw accepted-post intention from eligible physical preview: internal debt consumption retains the raw intention; pin selection and early-launch decoration use only the eligible preview. This is a mechanism-level split of semantic consumers, not a timing offset or opcode exception. Review must confirm no other preview consumer requires raw semantic intent before implementation is authorized. If debt conservation cannot be justified with this separation, stop this design stage instead of masking pins alone.

There is no combinational feedback path if YIELD_READY reads registered BIU metadata only and BUS_EXCLUDE reads existing registered EU state. The controller's combinational acquisition output may feed only the BIU new-commit inhibitor, never YIELD_READY or EU combinational act decode. EU posts on acquisition are captured before the inhibited scheduling block. Do not feed BIU next-state readiness back to acquisition. Verify this in elaboration/lint, not merely by module naming.

The existing slot_busy interlock (`v30u_biu.sv:901–902`, `v30u_eu.sv:2295`) naturally stalls further posts while retained requests occupy the slot. Queue pops and pending write-data pairing continue. Validate full-queue overflow assertions and exactly-once delivery rather than adding a second request buffer.

## Boundaries and custody

First substage is native-mode demux level arbitration only, without RQ/AK frontend. No claim about native physical ACK, T4 transfer, turnaround, pin mux or return timing. Preserve BUSLOCK_N constant behavior. RESET priority and external driver isolation remain the external controller contract.

The BIU already receives md8080 (`v30u_biu.sv:178`; EU assignment at 2642). In 8080 mode, pending-only inhibition and YIELD_READY are disabled. Valid callers must not hold external ownership across a mode transition; native test programs do not execute mode-switch instructions while owned. BUS_OWNED still forbids launches if such an invalid condition occurs, with a diagnostic; never silently resume driving against a remote owner. Minimum-mode implementation is outside this core's maximum-mode interface and remains untouched.

No new core state means the SS map/census remains unchanged. External ownership state is not restored by core SS; prohibit SS reads/writes/save/restore during pending/owned arbitration, including restoring either side independently. Existing SS-only isolated regression remains required.

Multiplexed mode is deferred. `v30u_biu.sv:1137–1288` and `v30_core.sv:218–277` require CE_HALF between successive CE edges. A live EU cannot justify global suppression of CE_HALF. A later preregistration must establish output isolation and the half-cycle contract separately.

## Proposed acceptance bars before implementation

At least 12 protected profiles: even LOCK RMW, odd LOCK RMW, REP three iterations and IRQ two INTA, each with modeled waits 0/1/3. Literal memory/frame results and adjacent odd-word sentinels are mandatory. No external acquisition while existing exclusion is asserted, between started split halves, or before both INTA complete. After acquisition the EU may decode LOCK or dispatch IRQ and assert exclusion; ownership remains sticky, the new EU access waits, and no launch is permitted. Directed late-LOCK and late-IRQ cases must establish this distinction. IRQ source withdraws only after its second completed INTA; PSW expectation uses existing normalization.

Additional directed level cases must establish all of:

1. At least 200 eligible clocks with YIELD_PENDING=0/BUS_OWNED=0: exact raw-vs-opt-in bus, QS and architectural comparison. Macro-off default retains existing port surface.
2. At least 16 eligible clocks in actual Tw with READY low and retained pending request: zero grant before drain.
3. At least 32 owned clocks: zero new cmt creation, bus announcement or T1. At least one program consumes two queue bytes while owned; another reaches its natural queue/access stall.
4. Acquisition simultaneous with an EU post retains its payload and launches it exactly once after return. Exercise unsplit and whole queued split before its first T1.
5. Request during the first odd read/write half cannot acquire between partners. Exactly-once composed read and literal write/sentinels after return.
6. An already-announced cmt drains naturally without cancellation introduced by yield. A completion/delivery or fetch-landing debt present at acquisition expires exactly once while owned.
7. A full six-byte queue, a retained EU access, a pending HALT display, queued channel-0/1 priority, release/resume and RESET in drain/owned/resume receive explicit nonvacuous coverage.
8. A branch/flush during ownership may change fetch pointer/queue state but creates zero physical preview, cmt or launch; fetch resumes at the literal branch target. An IRQ-debt preview intention accepted while owned produces zero physical announcement, preserves the required internal debt consumption, and resumes the queued request with correct vector/read composition exactly once.
9. Pending-only requests in 8080 mode do not inhibit or grant; no 8080 instruction-timing changes. Owned mode-transition misuse produces the declared diagnostic.

Per-case watchdog 4096 eligible CE; timeout failures are preserved and do not imply a NEC grant-latency guarantee. Fresh receipt builds declare all RTL/SVH/HEX/TB/runner inputs and binary/full-log hashes. Keep failed logs and independent replay/build checks. Simulations instrument conservation and interlocks; silicon match remains the only native correctness bar.

Before RTL promotion: default and opt-in lints/SS census, existing artifact and functional regressions, and a fresh default G6 receipt meeting its standing setup/hold/Fmax bars. The opt-in demux capability requires a separate analysis-and-synthesis/VQM receipt with no errors and reviewable mapped logic. No opt-in 32 MHz, placement/routing or timing claim is registered for that scope. No QIP or production integration change is implied by passing the experimental capability. Parent must review the split invariant, 8080 misuse boundary and gate scope before authorizing implementation.

## Pre-run instrumentation clarification (2026-10-07)

Bar 8 includes a separately labeled BIU unit conservation scenario for the raw IRQ-debt consumer. The integrated core's exclusion guard prevents granting ownership between the protected INTA operations, so that unit scenario does not claim a reachable native grant in that gap. Prefer generating the debt through BIU cycles and public EU inputs before ownership; no forced internal signal during arbitration. If SS initialization is necessary, preregister its complete consistent snapshot and load it before pending/owned with CE stopped. Such a fixture cannot establish the reachable split invariant, which remains a real-core directed obligation. The unit must still show a nonzero raw intention, zero eligible physical preview, debt consumption, and exactly-once queued delivery with literal composition. All numeric bars and native/silicon limitations above remain unchanged. This clarification precedes implementation and acceptance of the unit fixture.
