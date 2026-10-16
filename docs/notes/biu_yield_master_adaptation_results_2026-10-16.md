# BIU yield on the 8080 master — 2026-10-16

Local functional checks and independent artifact review passed. One fresh
default CONTROL seed1 timing measurement also passed, within the scope below.

PR2 is adapted by ordinary merge to published PR1 `049da698`, including the
8080 master. The original optional BIU-yield production changes are preserved;
this adaptation adds no new production mechanism. It combines the gate-driver
options and connects 29 unused testbench outputs to typed wires, preserving
programs, expected results and watchdogs. The committed opcode namespace,
forced-native IRQ exclusion guard and staged-LOCK port union remain intact.

## Integration and local checks

`V30_BIU_YIELD` requires `V30_BUS_OWNERSHIP` and a demultiplexed bus. It inhibits
new bus launches while the EU and existing BIU debts keep normal CE. Connect
request to `YIELD_PENDING`, `!CORE_BUS_ENABLE` to `BUS_OWNED`, `YIELD_READY` to
`CORE_QUIET`, and `BUS_EXCLUDE` to `EXCLUDE`. External bus isolation and event
retention remain required.

| Check | Observed result |
|---|---|
| Level controller | PASS: 26 contract checks |
| Real-core whole-core ownership | PASS: READY drain, freeze and resumption |
| Native exclusion | PASS: 18 profiles |
| RQ/AK frontend | PASS: 66 distinct checks, 82 total |
| Demultiplexed frontend/core chain | PASS: 13 profiles |
| Forced-native IRQ from native and 8080 | PASS: 18 fixed profiles |
| BIU yield | PASS: 28 real-core profiles and six separate BIU fixtures |
| Misuse / configuration controls | PASS: two runtime diagnostics and four invalid configurations rejected |
| Default 8080 smoke | PASS: 12 baseline + 12 holdout on the same current build |
| Strict lint / compiled review | PASS: eight scopes; assertions and fatal sites checked without suppressing UNOPTFLAT |
| Save-state / QSF checks | PASS: version `0x90`, 232 mapped slots, 229 architectural flops; generated QSF consistency |

The yield profiles cover protected operations, READY drain, queued ownership,
started odd splits, live-EU activity and request/completion conservation. Pending
requests defer in 8080 MD. That pending-only test is a separate BIU fixture;
it does not demonstrate real-core ownership in 8080. Owned 8080 and save-state
mutation during arbitration remain unsupported, with explicit diagnostics.

The save-state tag is `0x90E8`; no cross-version stream compatibility is claimed.
The prior 9,672/14,800 C4 populations were not replayed for this adaptation.

## Fresh default G6 measurement

| Field | Observed value |
|---|---|
| Configuration | Default CONTROL, staged LOCK OFF, one seed1 draw |
| Fabric Fmax | 38.71MHz |
| Worst setup / hold slack | +6.596ns / +0.253ns |
| Setup / hold TNS, four domains | 0.000ns in all eight rows |
| Resources | 11,412 ALMs; 6,082 registers; zero latches or `lpm_divide` |
| Diagnostics | 0 errors; 1,345 warnings, including one Critical Warning 127005 |

Artifact ID:
`9e80a14804e3e2f564380b19020ba2685f9a21571889943c1f23808650463b52`.
Control receipt SHA-256:
`a0181ca1778ea7e3f1dc8dca103a76f59c754fea4eb3395488369e75fd4eaafe`.

The registered bar is fabric Fmax at least 32MHz, positive setup slack and zero
setup/hold TNS on all four domains. Warning 127005 reports a 2048-word ROM design
depth versus 1028 initialized words, with the remaining words zero-initialized;
the three generated ROM populations were checked. This checks initialization,
not mapped consumer/selector retention. The measurement is fresh for this RTL;
it does not establish optional-yield ON timing or fitter reproducibility.

The supervisor retains `FAIL_CONTROL_OWNER` and exit code 1 because the snapshot
QSF mtime changed. Independent recovery verified identical bytes and sizes for
all 369 inputs and unchanged mtimes for the other 368 before accepting the
measurement. The three producer actions returned zero, their full outputs and
process closure were verified, and no fit was repeated. An auxiliary
`prepare --verify` timeout at 120 seconds also remains FAIL; separate review
closed the complete fixture inventory and equality to qualified literal records.
Neither instrument failure led to a CPU or oracle change.

These finite engineering checks do not establish NEC physical RQ/AK or
HLDRQ/HLDAK timing, silicon equivalence, a complete V30, staged LOCK ON,
optional-yield mapped retention or whole-design SYS50/divide-by-five timing.
The optional interface remains outside the production harness. See the
[adaptation preregistration](biu_yield_master_adaptation_prereg_2026-10-16.md)
and [integration contract](biu_yield_level_prereg_2026-10-07.md).
