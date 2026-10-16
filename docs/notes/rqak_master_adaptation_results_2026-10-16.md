# RQ/AK ownership on the 8080 master — 2026-10-16

The adaptation passes the directed and default simulation checks below, including
the no-selector 18-profile control. A fresh default CONTROL seed1 timing
measurement also passed; its scope and limits are recorded below.

PR1 is adapted to master `182ec09622bdef6cbc3b594a89a59c6c0e0026b1`,
which contains the finite 8080 extension. An IRQ entered from 8080 retains the
interrupted emulation MD in its saved frame while executing native internal
entry. Qualifying the entire exclusion guard with native MD could therefore
allow ownership during that entry. Only LOCK is now native-mode-qualified:

```text
(!mode8080 && lock_pfx) || st == S_IRQ_D ||
(upc_page == 7 && st >= S_ROW && st <= S_INSTR_END)
```

The optional `BUS_EXCLUDE` output is separate from `BUSLOCK_N`. The merge
preserves the staged-LOCK EU connections, active opcode namespace and saved MD.
The current save-state version/count/tag remain `0x90`/232/`0x90E8`; there is no
cross-version state compatibility claim. With ownership disabled, the original
core logic and state remain unchanged and the new output has no functional
consumer. The default source comparison and a fresh 12+12 smoke checked this
scope; the prior 9,672/14,800 populations were not replayed for this adaptation.

## Current checks

| Check | Observed result |
|---|---|
| Level ownership controller | PASS: 26 contract checks |
| Real-core ownership | PASS: READY drain, acquisition freeze and resumption |
| Native exclusion | PASS: 18 case/wait combinations; absent optional port rejected without its macro |
| RQ/AK pulse frontend | PASS: 66 distinct checks, 82 total |
| Demultiplexed frontend/core chain | PASS: 13 profiles |
| Forced-native IRQ from native and 8080 | PASS: all 18 separately reset selected-process profiles |
| Default 8080 smoke | PASS: 12 baseline + 12 holdout, same current build |
| Save-state lint/flop census; generated QSF consistency | PASS |
| Default IRQ matrix without `+profile` | PASS: all 18 profiles once in one process |
| Independent final legacy review | PASS |
| Fresh default CONTROL G6 | PASS: one seed1 measurement; details below |

The directed IRQ matrix is two literal programs × request at decision/entry/
INTA gap × READY waits `{0,1,3}`. It checks two INTA cycles, fixed stack frames,
IRET/RETEM return, ownership exclusion and resumption to a literal memory marker.
All selected processes returned zero and their complete outputs were reviewed.
The no-selector control also completed all 18 profiles once in one process on the
same compiled binary, checking reset between successive fixture profiles.

The initial complete batch and its instrument failures are retained. Its upper
address check incorrectly included HALT pseudo-cycles. The corrected check
applies to CODE/MEMR/MEMW, with a separate INTA contract and bounded HALT
observation; programs, READY phases, expected words and watchdogs are unchanged.
See the [execution addendum and address-domain erratum](rqak_master_adaptation_execution_addendum_2026-10-16.md).

## Fresh G6 measurement

| Field | Current value |
|---|---|
| Configuration | Fresh default CONTROL, staged LOCK OFF, seed1 |
| Fmax (fabric clock) | 38.71MHz |
| Worst setup slack | +6.596ns |
| Worst hold slack | +0.253ns |
| Setup / hold TNS, all four domains | 0.000ns for all eight setup/hold rows |
| Build diagnostics | 0 errors; 1,345 warnings retained and reviewed |
| Report/artifact identity | `657cc8290cd27ffad764c4bb6f7ebc8dbcc8a45e6ea68e8c8cce5938fa45f9d6` |

The registered timing bar is at least 32MHz for the fabric clock, positive setup
slack and zero setup/hold TNS on the four required domains. No prior C4 timing
number is inherited by this source. A single draw does not characterize fitter
variation or the timing of an ownership-enabled integration. C4 mapped-retention
proofs were not transferred to this fitted netlist; mapped retention remains
unqualified by this measurement.

The utility remains outside the production harness. These are finite engineering
checks of the optional synchronous adapter; they do not establish NEC physical
RQ/AK timing, silicon equivalence or a complete V30. Staged LOCK ON and
whole-design SYS50/div5 are outside this validation. Whole-core freezing remains
unsupported for staged LOCK's uninterrupted five-CE profile; the existing
multiplexed/staged rejection remains.
