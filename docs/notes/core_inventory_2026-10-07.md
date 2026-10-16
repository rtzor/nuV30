# Incremental core inventory at ed50fb4e

Reviewed on 2026-10-07 against fork `rtzor/nuV30`, stable base
`ed50fb4e5222fb5567c01ff16d34cd8a08f584e2`. This is a source/documentation
inventory, not a newly measured instruction census. Historical measurements
below are attributed to upstream; their gates have not been rerun here.

## Work order

1. Bus ownership contract and a bounded external adapter, then native
   BUSLOCK/exclusion and correctly timed maximum-mode RQ/AK arbitration.
2. Confirmed functional omissions and independently reproduced remaining
   native-mode failures. Do not enumerate implemented instructions as missing
   simply because their timing differs in a whole-program trace.
3. Complete BRKEM handoff, 8080 decoding/execution, RETEM/CALLN and mode-dependent
   interrupt behavior with dedicated evidence and tests.

## Contrasted inventory

| Function | NEC documentation | Current source / upstream evidence | Assessment and next step |
|---|---|---|---|
| Bus ownership, minimum mode | HLDRQ request / HLDAK acknowledgement; bus drivers released during acknowledge | Current `v30_core.sv` explicitly implements maximum mode | No native minimum-mode personality. Keep any future pin adapter separate from generic ownership. |
| Bus ownership, maximum mode | RQ/AK0 and RQ/AK1 are bidirectional; channel 0 has priority; request/acknowledge/release pulses | No RQ/AK ports or protocol state in current core | Confirmed missing physical protocol. First utility is a conservative whole-core pause with a level handshake, explicitly narrower. |
| BUSLOCK / external exclusion | Prefix secures following instruction, including repeated block; also secures interrupt acknowledgement. Hold acceptance inhibited while locked | Prefix decode exists in `v30u_eu_step.svh:91`; clears at 876/922. `BUSLOCK_N` is constant inactive in `v30_core.sv:508–510`. `biu_model.md` documents socket RMW measurements and an archived-FSM implementation | Confirmed missing output/exclusion in ucore. Existing LOCK decode is not output support. Need native lock timing and an arbiter guard before enabling general DMA for arbitrary programs. |
| READY / waited transfers / prefetch | Documented bus phases and wait insertion | BIU implements READY and prefetch; upstream has extensive waited-program captures with residuals | Implemented mechanisms with incomplete fidelity, not missing instructions. Adapter must drain them and leave their timing unchanged. |
| Native NEC additions, block I/O and bit operations | Instruction definitions in the NEC manuals | Current ROM/PLA tables, EU and banked instruction suites render these families; dated gaps record block-I/O validation | No evidence that all NEC additions are absent. Audit specific forms and actual failures before choosing a fix. |
| BRKEM native entry | Documented frame/mode transition | `wrfuzz_provenance.md` §10 (W7) reports exact native prefix through the third frame-write T1 on retained captures, then a common QS handoff residual | Entry exists in part. Do not describe BRKEM as wholly absent or confuse native-entry validation with working 8080 execution. |
| 8080 / RETEM / CALLN | Documented emulation instruction set and mode transitions | Loader `v30u_eu_step.svh:77/279/437` selects native PLA/pages 0–4, never pages 5/6; `opc8080_n` only cleared at 884/923. Mode state, ALU permutation and ROM rows exist | Confirmed structural execution gap. Complete loader/decoder and test return paths last in this sequence; presence of tables does not prove support. |
| Interrupts, NMI, trap flag, HALT and REP withdrawal | Documented events; undocumented timing also measured upstream | Current source implements these mechanisms. Early `ucore_gaps` / `OPEN_QUESTIONS` snapshots list items subsequently fixed | Review latest results and reproduce specific failures. Historical missing trap-flag support was subsequently implemented, not a current omission. |
| REP termination versus INT | Native REP termination semantics | `rep_int_termination_race_results_2026-08-20.md` documents correction, 600/600 directed simulation and compatibility gates; current `v30u_eu_cond.svh` evaluates termination before withdrawal | Already fixed at this base. Do not reopen as a pending implementation. Results are upstream, not this session. |
| REP counter width / CL=0 evidence | Counter semantics require full word count | Current base contains `e61f2e09` width fix. `rep_cl0_silicon_recapture_results_2026-08-17.md` says 0/24 captures and explicitly no certification | Code correction exists; intended recapture remains an evidence gap. No hardware validation is authorized here. |

## Reading historical evidence correctly

`docs/notes/ucore_gaps_2026-08-04.md` is an append-only dated snapshot with
updates, not an authoritative current task list. Follow its ledger pointers,
the W7 follow-up and later fz2, CE-contract, demux and August 20 reports.
`docs/notes/standing_gates.md` records the current inherited validation set.
Do not convert a historical fuzz failure count into a count of missing opcodes.
Likewise a replay that reproduces retained results is not a count of
silicon-exact programs.

Remaining hypotheses include the mechanism behind unresolved whole-program
timing seats and precise native grant/release timing at LOCK, READY, split
accesses, INTA pairs and standby boundaries. A utility's simulated safety
contract cannot decide those silicon timing questions. Native arbitration must
be designed from NEC evidence and scored against applicable retained captures;
new hardware measurements need a separately authorized session.

The current PCS86 DOS/FDC/XTA reads pass with external arbitration, according
to the user's supplied observation. Missing native hold support is recorded
as a limitation, not asserted to cause a specific PCS86 failure. The diagnostic
PCS86_DBG_REGS local patch is outside this fork and is not published here.

## Custody and validation boundary

This independent clone contains the fork's existing public materials only.
No private PCS86 inputs, ROMs or integration files were imported. Existing
LICENSE and source acknowledgements are retained. The first utility is not
connected to production QIP files and is not promoted as a native-core landing.
Its checks and caller obligations are registered in
`bus_ownership_prereg_2026-10-07.md`; simulation receipts and final results are
reported separately. No FPGA programming or stable integration changes.
