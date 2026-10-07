# FPGA native-state exclusion guard — validation results

Candidate branch: `feature/bus-exclusion-guard`, based on adapter tip
`ce82aa7b` and original fork base `ed50fb4e`. Preregistration commit:
`dca5a106`, [registered scope and checks](bus_exclusion_prereg_2026-10-07.md).
Intended PR destination is `rtzor/nuV30`, base `master`; upload is deferred.
No FPGA contact or stable PCS86 integration changes were performed.

## Implemented contract

The EU publishes a combinational `eu_bus_exclude` derived solely from existing
registered state:

```systemverilog
!mode8080 && (lock_pfx || st == S_IRQ_D ||
             (upc_page == 3'd7 && st >= S_ROW && st <= S_INSTR_END))
```

`S_ROW` through `S_INSTR_END` are contiguous states 22 through 29. Page 7 is
internal microcode, so this intentionally guards more than the INTA pair.
Its retained page value outside the active microsequence is not enough to
assert the guard. Existing LOCK-prefix lifetime includes repeated operations
and a LOCK-prefixed HALT. Native-state interrupt dispatch clears that prefix;
the active-entry term continues exclusion during the internal sequence.

The ucore top publishes `BUS_EXCLUDE` only under `V30_BUS_OWNERSHIP`. The
default public port list is unchanged. There is no new register, save-state
field, instruction-timing input or edit to the execution-step implementation.
`BUSLOCK_N` remains fixed inactive. This is an **FPGA integration contract**,
not a measured NEC LOCK waveform or a fabricated physical V30 pin.
8080 execution is outside the guard's stated protection scope.

An opt-in caller connects `BUS_EXCLUDE` to `v30_bus_ownership.EXCLUDE` and
`SS_BUS_QUIET` to `CORE_QUIET`. All earlier adapter obligations still apply:
synchronous request inputs, CPU bus isolation, event retention, no save-state
writes during arbitration, proper reset drive release, and enables used as
register enables rather than clock gates. The utility freezes the whole core
and does not promise a bounded grant latency or native EU-progress behavior.

## Fresh simulation gate

```text
python sw/bus_ownership_gate.py --compiler clang --native-guard
```

PASS: six executable-byte workloads crossed with waits 0, 1 and 3, giving
18 case/wait combinations. Each workload first compares adapted and raw cores
without a request for 1,500 CPU clocks: public bus, QS, architectural debug
registers, quiet and guard outputs match. Both cores use the same initialized
public memory and register state; the verification backdoor supplies initial
registers only, with its scripted consumer disabled.

Each workload is then repeated with a level request. Locked cases raise that
request only after genuine decoded exclusion has asserted. Every excluded
clock must preserve CPU enables and withhold a grant. Locked RMW and REP
cases also assert continuous exclusion from its first observation through
the final physical write. Eligible requests subsequently acquire at a quiet
boundary. Tests do not alter CPU scheduling to create those boundaries.

| Executed workload | Additional checks | Guarded quiet clocks for waits 0 / 1 / 3 |
|---|---|---|
| Unlocked `INC word [0200]` | No exclusion; request can acquire | 0 / 0 / 0 |
| `F0 INC word [0200]` | Word changes 0001 to 0002; exclusion through write | 1 / 2 / 2 |
| `F0 INC word [0201]` | Two physical writes; word changes 0001 to 0002; adjacent A5/5A sentinels preserved | 1 / 2 / 2 |
| `F0 F3 MOVSW`, CX=3 | All three iterations complete; destination words 1111/2222/3333; no grant before CX=0 | 2 / 2 / 0 |
| `F0 HALT` | Retained guard while halted; NMI wakes into handler and permits eventual grant; reset clears guard/grant | 1481 / 1474 / 1466 |
| Maskable IRQ followed by NOP and segment-prefix/NOP handler | Two INTA cycles; guard through four passive gap clocks; no grant before both acknowledgements; stale page-7 loader state permits guard clear | 14 / 14 / 13 |

All counts in this table are **simulation observations**, not NEC silicon
timing measurements. In the waited REP case, wait=3 produces 63 clocks with
guard asserted and **zero quiet opportunities** during that interval. The
test reports that coverage limitation; quiet/exclusion overlap is exercised
by the other waited workloads. It does not invent a quiet interval or weaken
the continuous-exclusion check.

The memory model reconstructs bus phases from BS/READY. It snapshots address
from the announcement, captures UBE on the following actual T1, and samples
DATA_O when the write completes. An independent hierarchical T-state
assertion corroborates that write lane capture occurs in actual T1. This
matters because UBE can retain the previous cycle on a zero-age announcement,
and existing paired-store forwarding can provide data after announcement.
The odd-word result and neighbor sentinels validate both byte lanes under
all three wait configurations.

The same harness is linted without `V30_BUS_OWNERSHIP`. It must fail with
`PINNOTFOUND` naming `BUS_EXCLUDE`; this expected rejection passes. Thus the
new port is available in the opt-in build and absent from the default build.

## Artifact receipt

The final fresh build is local under the thread's `work/bus-ownership/`:
`bus_ownership_o8z8s2ip`. Compiled/generated artifacts are not committed.

| Artifact | SHA-256 |
|---|---|
| `receipt.json` | `b5c132a0526982e344f590ac3ccd94d21dc03cb9a16ac4bfabee88990c87cd2a` |
| Fresh simulation binary | `03954730461c73aa90d0251368a6fbd904d4e6c31f20979c89d7a44e5d9bd73f` |
| `gate.log` including negative port probe | `05f4bdeebbbb4b47ba3411e00ffc8c0b876ed96ce0613b5f998599731c05f905` |
| `default-port-probe.log` | `3e3f1f3d223dc75b5c868d82dc434e6b5ec154ec2159c8d5b74aba86ba4b9f83` |
| `v30_core.sv` | `36e58dfae626e5c52c8307f36a33b8f8f4bed7e4138970c471abf26eadaa6063` |
| `v30u_eu.sv` | `e058d163302973ecc6c39deaeafa3275151ea1b507cfd677c1f3c351d6c685a2` |
| `tb_bus_exclusion.sv` | `d7901ce80391bc769d0e796aa663eb58915565239c1b7b2b55f647a1e6f4c7e9` |
| `bus_ownership_gate.py` | `650d504e2cbcda5f7eaede1f42b76bcc389606da3e2a345f7ee9fe5e6261c046` |

The receipt also declares all ucore SV/SVH sources and runtime HEX inputs,
their hashes, the build command, binary hash and log hash. The log identifies
Verilator 5.050 and clang64 clang 22.1.8. Windows uses the previously verified
clang64 workaround for the installed GCC library mismatch; tool warnings
from Verilator's C++ support files remain in the log. No new RTL functional
warning is waived to obtain these results.

## Preserved failed harness attempts

These failures were not core guard fixes. The guard RTL stayed unchanged
through the harness corrections and final matrix. Local logs remain retained.

| Local build directory | Registered failure and correction | `gate.log` SHA-256 |
|---|---|---|
| `bus_ownership_b_ch_098` | Extra per-workload assumption that each guard interval contains a quiet clock fails for REP/wait=3. Subsequent trace establishes 63 guarded clocks and zero quiet clocks; only that extra coverage assumption is removed, while exclusion/operation checks remain. | `fd28b9aa09b3c738d4f469832bb95b9b3434eae4208c40704633e573693277e9` |
| `bus_ownership_w7hx7_le` | Even-RMW result fails because the harness prematurely latches write data at announcement. Sample DATA_O at completion, preserving the existing paired-store forwarding contract. | `9ed7a0784593532e57a77af59b18bb45c10d17068ba41c078266dc76b14a6e39` |
| `bus_ownership_9smihkrl` | Odd-RMW neighbor sentinel fails after lane-aware stores are introduced. Investigate announcement-versus-T1 UBE sampling. | `252e23f7142abba68a4533d917f27063bf5f197a5db48fd5955d7c613fab9e03` |
| `bus_ownership_g7fp1z9_` | Diagnostic shows the second write at 0202 using stale UBE=0, corrupting neighbor 0203. Capture UBE in actual T1 rather than the zero-age announcement; corroborating T-state assertion and all-wait sentinel checks then pass. | `3440cdab9cd4b8d16af001de1c1fec03620d8c1b3bf27d69788d8c0f2ba81758` |

An intermediate complete matrix, `bus_ownership_bc2bb5j4`, passed before the
final continuous-write, actual-T1, stale-page and negative-port assertions
were added. Only the final receipt above supports the full final claim.

## Independent regression review

Parent independently reran the final native binary: all 18 cases pass, and
every declared input, binary and log hash matches the final receipt above.
Parent also completed fresh default-core and standalone-controller builds:

| Fresh local build | Result | `receipt.json` SHA-256 | Binary SHA-256 |
|---|---|---|---|
| `bus_ownership_ksoh_gcj` | Default core integration PASS | `4e1128cce9706ab7fe8d6f262e28036cb816b6fec5529b0005699365802b48dc` | `9f0add5283f9d342f3bcdf0796c81da8edae360de096260c52e29fde2002b286` |
| `bus_ownership_6w6bkhvu` | Controller 26 checks PASS | `d160aeed5ce1aa4f5ead57e8e46820ad415f70b3fa3e466d5ed7bf22e31ddfa5` | `7d02d22f9f415cf55022cfb264f25b405605906ee23b29ee6bec45f7b32127d7` |

Parent verified all declared input, binary and log hashes for both builds.
Their directories are under the same thread `work/bus-ownership/` root.
The final save-state/structural checks also pass: `ss_lint.py --core ucore`
reports 232 mapped symbols and 228 architectural flops, with no unmapped
state; `r7_lint.py` reports one declared READY carrier, 51 stop sites and zero
violations; `prefix_clear_lint.py` reports 20 FIRST sites and four PFX-KEEP
sites. The retained `work/bus-ownership/parent-structural-lints.log` SHA-256 is
`dac72816b226ab5c362161f107019281edc04820e426a1a2b0be993d9e50a2b9`.

G0 passes all three legs: independent ROM parsing, compiled tables versus
the C++ dump, and generator freshness, covering 9,988 byte-identical entries.
The inherited Linux binary recipe initially refused the Windows `.exe`
output; that failed staging directory is retained. A scratch bootstrap uses
the genuine artifact layer with an explicitly declared `.exe` output and
copies build inputs into staging. It does not change repository source or
bypass freshness checks. Parent independently rebuilt and reran the complete
gate. Its retained `work/g0-windows/parent-replay.log` SHA-256 is
`03f1f4c7a19f7a34a5af11f6e3394e57c41064c31c20d1cc1ffb481b60390eba`;
receipt ID is `2e1264901c9dea38c79bb00ae1849a16ec458675a88d95b9fb0ff0aea66800df`,
receipt file SHA-256 is
`3cb654f74e557a88c25fd867ddc950674a35755a95a824e1a1e213de32c247cd`,
and binary SHA-256 is
`c7c3113a5b52c4d319d1357684389537bdea2dc15330156fe80cc6d6e6ec8d2e`.
Both runs remain in the scratch receipt history; all 41 input contents
match, with external-path separators normalized only for that comparison.
This table check is not a silicon execution oracle.

A separate read-only review found no actionable defect in the bounded guard
or harness contract. Coverage remains directed: unconditional REP MOVSW is
tested, while conditional REPE/REPNE early exit and interrupt withdrawal are
not newly validated here. The paired-core comparison can share unrelated
core/model defects; explicit expected memory values mitigate that risk for
these workloads. These integration tests use the demultiplexed bus and do
not establish multiplexed CE_HALF or physical ownership pulse timing.

## Default CONTROL synthesis and timing

A single clean CONTROL/DEFAULT build in an isolated snapshot passes the
inherited G6 bars with Quartus 22.1std.2 Build 922 Lite: zero compile errors,
divclk Fmax 38.19 MHz (bar 32 MHz), worst setup slack +6.923 ns, and setup and
hold TNS 0.000 in every reported domain. Parent independently checked the raw
STA summary: four setup and four hold panels, worst hold slack +0.246 ns.
Input stability passes without moved inputs. No seed retry or timing tuning
was performed. No bitstream was uploaded or programmed.

This CONTROL has `V30_BUS_OWNERSHIP` **off**, as derived from its reports;
it establishes default-build compatibility, not retention/timing of the
optional guard. The scratch Windows adaptation supplies `.exe` tool paths,
uses the installed version selector, and copies the existing public
`pll_q17.qip` byte-for-byte as `pll_q22.qip`. It does not modify repository
sources, constraints or generated PLL internals. This is not a performance
comparison with Quartus 17.1.

Local receipt: `work/quartus-control/control_receipt.json`, SHA-256
`1b047d2e8bc0ab01b620fe99b2170e4e70505b38b4d10bd976cef68d074e5379`.
Input manifest SHA-256:
`a8e1406037695dcabd7818ed0aee24aa1584094efead6bf234d286704d6d7c7f`.
Parent verified all 126 declared input hashes, nine report/log hashes and
four output hashes against the retained snapshot. The tool executable and
scratch adaptation identity are separately recorded in the snapshot identity.
The 1,346 compile warnings remain in the raw log, including inherited
platform/IP and not-fully-constrained timing warnings. The bars refer to the
reported constrained domains; they do not certify unmodeled board paths.

## Opt-in synthesis and mapped retention

A separate core-top Analysis & Synthesis build enables `SYNTHESIS`,
`V30_MUXED_AD` and `V30_BUS_OWNERSHIP`, with `v30_core` itself as the top so
the output cannot be discarded by an unconnected production wrapper. It
passes with zero errors and 1,054 retained warnings. The existing microcode
depth warning (1,028 initialized rows in a 2,048-entry memory, remainder
zero-filled) is retained. There is no fitter or timing claim for this build.

Quartus exports the post-synthesis VQM successfully. Parent independently
inspected its output declaration and connection: `BUS_EXCLUDE` is driven by
`eu_bus_exclude~2`, a `cyclonev_lcell_comb` with variable state, mode and LOCK
inputs and LUT mask `00F0F0F080F0F0F0`. Thus the optional guard is retained
as real nonconstant combinational logic. This proves synthesis retention,
not NEC timing or hardware behavior.

| Local artifact in `work/quartus-control/` | SHA-256 |
|---|---|
| `guard_map_receipt.json` | `c7b810213610ae79c30576775688bcb4385eb6a863575bd38cd551b4c89a171b` |
| `guard_connectivity_receipt.json` | `b43046b4115cc007488ce3a82af186348149ab7a75e5c060a9b7b7fbbdea3fd4` |
| `guard_synthesis.vqm` | `02064fd75b14dc6ff51e03d819f32ee506653002a1a509daf0b0c26b70c704fe` |
| `snapshot_identity.json` | `c905f0449a4b36884ce4d53657e65c897b419e7c3b3a9c90cf4d33140a044ef9` |

Parent verified all 23 declared opt-in inputs and four reports, tool and log
hashes, the export receipt's linked map receipt, runner, tool and VQM hashes,
and the unchanged live core/EU source hashes against the snapshot. The
Windows CONTROL adapter/tool identities also match their declared hashes.

This candidate is ready for review as an optional FPGA utility. Native
BUSLOCK waveforms, RQ/AK yield/resume and physical pulse arbitration remain
unimplemented and unvalidated; no optional-integration timing or hardware
certification follows from the default CONTROL result. Upload remains
deferred and its destination remains `rtzor/nuV30`, base `master`.
