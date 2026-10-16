# Experimental BIU-level yield results — 2026-10-07

Preregistration `b7404507`, with the public-port BIU fixture clarification `a00e74b8`, precedes implementation and acceptance. Baseline is `defe5a00` on `feature/biu-yield-level`; the prior pulse utility keeps its scope.

This experimental opt-in mechanism inhibits new BIU scheduling/physical previews while EU, request storage, queue and completion machinery keep normal CE. It adds no core flop or SS address. The external level controller owns arbitration state. It is not validation of native NEC yield/resume, physical ACK, multiplexed bus timing, silicon behavior, 8080 instruction timing or minimum mode.

## Integration contract

Define `V30_BIU_YIELD` and `V30_BUS_OWNERSHIP`, without `V30_MUXED_AD`. Connect controller REQUEST OR to YIELD_PENDING, inverted CORE_BUS_ENABLE to BUS_OWNED (including acquisition), YIELD_READY to controller CORE_QUIET, and BUS_EXCLUDE to EXCLUDE. Keep the core's original CE; ignore the controller's CORE_CE/CORE_CE_HALF. External bus isolation is still required. SS/save/restore is forbidden during pending/owned arbitration; the core does not save external ownership.

Readiness uses registered idle/commit/split state and does not demand an empty EU request queue. Announced commitments drain normally. Exclusion or a started split keeps required CPU launches enabled until acquisition. Once owned, late LOCK/IRQ cannot revoke grant. Raw accepted-post intentions consume INTA debt; only eligible physical previews are suppressed. No opcode timing table or production QIP change is introduced.

## Simulation evidence

The final acceptance run passed **28 real-core profiles**, **six separately identified public-port BIU fixtures**, **two runtime misuse controls**, **three configuration controls** and **three lint scopes**. The no-request comparison uses two macro-ON cores, with reference yield inputs tied inactive; 200 eligible clocks per protected workload and the READY/full-queue workloads compare public buses, QS and architectural registers. Separate macro-OFF regression provides default compatibility evidence; this is not an ON/OFF twin comparison.

| Real-core coverage | Required result |
| --- | --- |
| 12 protected: LOCK even/odd INC, REP3 MOVSW, IRQ2INTA; waits 0/1/3 | Literal memory/frame results; odd sentinels; no acquisition during exclusion or before protected completion |
| READY + queued level owners | 16 actual Tw clocks, channel-0 priority then channel-1, continuous CPU bus isolation; live EU pops/post/delivery |
| Natural DIV prefetch fill | Six queue bytes at acquisition and at least two live queue pops while owned |
| Six started odd splits: read/write at waits 0/1/3 | No acquisition between halves; one composed literal read / two physical writes and intact adjacent bytes |
| Late LOCK, late IRQ, branch during ownership | Grant sticky; pending access; zero launch/previews; observable natural access stall; correct resumed literals/handler/branch target |
| Two PUSH acquisition/post coincidences | Actual pre-edge EU post plus registered readiness, real controller acquisition, retained unsplit/split payload, exactly one/two literal writes and sentinels |
| Announced CODE commitment | Exact pre-request cmt kind/address completes once before grant |
| Pending HALT | Actual HALT state and deferred status commitment retained while owned, consumed after return |
| RESET phases | Nonvacuous actual Tw drain, owned and release boundary reset priority |

The six BIU unit fixtures use ordinary public EU/READY/reset inputs without force or SS snapshot. They independently create first-INTA replacement provenance through CODE T4, then test both raw INTA-follow and vector-follow intentions while manually owned: raw=1, eligible=0, debt clears, queued payload survives and one delivery follows return. Vector address 0080 must return literal 0100. Other fixtures cover acquisition-edge unsplit/split posts, an actual read's remaining completion debt delivered exactly once while owned, and pending-only 8080 input behavior. These fixtures validate conservation consumers; they do not show that the real core acquires inside its guarded IRQ interval or replace the real controller acquisition/post tests.

Both pre-edge and post-edge checks reject any running/committed cycle, new announcement or eligible preview while owned. CPU completion counts include all modeled transactions. Runtime negative controls require explicit owned-mode and SS-mutation diagnostics. Compile controls require absent default ports, rejection of missing guard macro and rejection of yield-plus-mux. Unsuppressed UNOPTFLAT lints cover core OFF, core ON and the full integration; complete logs and report-unoptflat artifacts, when generated, remain available for independent path review.

## Artifacts and failures

Final agent run `7rvfjosf` receipt SHA-256: `840032f94f1cd17444079cd90845a2ceb7063209e300a38097a47de53a9bee1f`.
Executable SHA-256: `bfd66c2fe4e5f02ccf06f7c3d54e71262545be91fc64aa669a24cfc7d5002361`.
Full gate log SHA-256: `3b2ff288afcd38783b81073232ea5ca3d559716cf59a38fc7594b1c25e55cc7a`.
All 20 declared input hashes match the final tree. Started-write requests explicitly target the first WRITE half; started-read requests target the first READ half. Before grant, independent modeled completions prove two write halves plus literal 0002/sentinels, or one read completion at each address 0201/0202, at waits 0/1/3.

Earlier PASS runs `57n94p0s` and parent `97mah9ey` are coverage intermediates: their input hashes matched the tree before the final bar-5 phase correction. Review found that the started-write case requested during its earlier read half. Their retained receipts are respectively `1d5adc4c599e852104191c75f3419110a11b0290f1c1ff80b1507c89200614f3` and `67d0ca8d4b4ab26e62b2a3545a1d6cec6fecfcff88342a72822f2c6e91e72d18`; full logs are `e69871ed164f6a8c5d20b1a4ec1b11b59f73069a925dae6689613d23c1276d6b` and `9bc13a7dd075ed012660f8ef96a08cf1d7aab883e4470dea32362e273aee9e52`. RTL and runner did not change during this final TB correction.

Core OFF/ON UNOPTFLAT warning counts are 0/0; integration lint reports no UNOPTFLAT warning. With no such warning, report-unoptflat emits no SCC DOT graph. Complete unsuppressed logs remain retained for parent review.

Observed diagnostics close the harness assumptions: natural stall is `st=18` (S_PRERD), microcode `0/90/2`, slot=1, rq=1, row_blocked=0, stable for 16 clocks. Real acquisition-edge PUSH posts target 007FE (unsplit, one write) and 007FF (split, two writes). The independent source reviewer closes the prior real-post/vector coverage gaps; parent fresh-build/replay acceptance remains separately recorded below.

Retained intermediate directories under thread `work/bus-ownership/`:

- `4df4l664`: malformed generated unit port list; elaboration failed. Explicit named-port generation corrected it.
- `mzw1fkc0`: four WIDTHTRUNC ternary conditions used an int directly; fixed with `split!=0`, without adding waivers.
- `dod1u4_j`: 12 protected profiles passed; the extra assumption that the first READY workload also acquires with a full queue failed. The registered full-queue bar moved to a separate natural DIV workload; READY retained Tw/priorities/ownership requirements. No RTL change.
- `omcjy0ci`: READY, natural full queue and six started splits passed; late-LOCK coverage included an incorrect extra assumption that `row_blocked` represents every access stall. Source defines it specifically for the F micro-row interlock. The final test retains guard/post/slot/request bars and directly checks stable EU/register/queue-pop behavior for 16 clocks.
- `lggxw5ab`: 26 core profiles plus five unit fixtures passed; missing-guard negative probe failed because the TB's missing BUS_EXCLUDE port aborted before explicit configuration rejection. No receipt was issued. Review also identified that manual unit ownership did not close the real controller/EU-post bar and that vector intent was unused. Final tests add genuine PUSH/controller coincidences and the second raw consumer. Wrong-configuration probes now elaborate core alone.
- `6jgkl8q0`: intermediate 28 core/six unit PASS and negative controls PASS receipt retained; vector response/address checking and all three report-unoptflat invocations were subsequently strengthened. This is historical evidence, not the final-source receipt.

| Intermediate run | Full gate.log SHA-256 |
| --- | --- |
| `4df4l664` | `a0b884e8bfcf59d8c2ff7d0ec91b3243fe131c31327a81dbb5504186bca408dc` |
| `mzw1fkc0` | `0ef2b7660b745228af921cf6ed3bd1c1dae96a4b629993f40ab4613f76d843e8` |
| `dod1u4_j` | `3b016a2d6fd8754d43387cdd301f9415c632e749a3e7861aa3902a8e5fe94c6b` |
| `omcjy0ci` | `8028bb1e64fe545bea0a7a223ed2387ed5c16fcb7c8f2e67f0138b6c2fdac4c5` |
| `lggxw5ab` | `cbc5ecc391a0bdfb3dae9952d0877e1210c22b8876102041af556bd348800059` |
| `6jgkl8q0` | `92212e278e8c235b40f760fef00bab8b21cb17507a9b9f1362d1fadd868bfa93` |

All full build/simulation/control logs are retained. No timeout or preregistered conservation/exclusion bar was relaxed. Compiler flag/header warnings remain visible; zero-warning claims apply only to a separately recorded synthesis scope if supplied.

## Final-source regressions

Parent fresh builds, independent replays and input/binary/log hash verification passed for the following modes. They use the final runner and RTL; their declared inputs exclude the yield TB, so its final phase correction does not invalidate these receipts. These are regressions of their individual scopes, not additional live-EU yield integration tests. Full binaries and logs accompany each receipt in thread `work/bus-ownership/`.

| Scope | Run | Receipt SHA-256 |
| --- | --- | --- |
| Default core | `46oz_9sa` | `8e8ea072187d8680d1b0e5f4a9a6645926ad7e8c718682ab99cca21350e451ce` |
| BUS_EXCLUDE (18 profiles) | `n052_l9k` | `3556fff092df731e994458abfba3d686d0b31d2d3433d9efd5026de0281e7c1b` |
| Standalone pulse (66 distinct / 82 total) | `a3abszub` | `96d0f2fd2e0ef3ed418be378b659913858788da59ae39d6c46d1669f33de9bf5` |
| Level controller (26 checks) | `bb3qieue` | `72fd9a3b16d1aa63734a0f61b84656d292cc3258f84cbbe42e04a6abdce4cf0c` |
| Whole-core pulse integration (13 profiles) | `hagzbu1x` | `2a3a5371dc4978979a525b86f4744010eb45d83c04f10fd1b9e3103d11785b20` |

## Parent acceptance and synthesis

Parent independently built the final phase-corrected bench as `b1oj991s`, verified all 20 source inputs plus executable/full-log hashes for it and `7rvfjosf`, and replayed both executables. Both pass 28 real-core profiles, six BIU fixtures, two expected runtime diagnostics and three invalid-configuration controls. The six started-split profiles independently count completed public read/write halves before acquisition. All three unsuppressed core-OFF/core-ON/integration lints report zero UNOPTFLAT warnings; no SCC DOT graph is emitted. Source review found no further concrete objection within this bounded engineering contract.

| Final yield artifact | SHA-256 |
| --- | --- |
| Parent `b1oj991s/receipt.json` | `db3d2a3d91879ded75e146c400e7e2f81bd7608233898321558f4b2469e7315e` |
| Parent executable | `b5184d913710f9e79b1fb48c67d6f8c841dde0491d8c5b81a04f97e23ab82c7a` |
| Parent full gate.log | `ffefd0a38e85e5cf91a0300227460e07b41e6279c071872cb907075caaf08edf` |

Fresh structural checks retain SS version 8F, 232 mapped symbols and 228 architectural flops (91 BIU, 137 EU), with zero unmapped state and the three existing whitelist entries. R7 retains one READY carrier, 51 stop sites and zero violations. Parent logs under `work/biu-yield/`: `parent-ss-lint.log` SHA `2876902341b110b93bb98d2186a51892d1c759a7e37b1d0092c75194f83ed2c7`; `parent-r7-lint.log` SHA `521c74b209cf35ccc9651497abaa2a6d776049d75ae3a3642c7140ff1070f056`. Prefix/EA scripts also pass, but inspect the archived legacy EU rather than ucore; they are not new ucore evidence.

Parent artifact-layer tests pass 45/45 with UCRT Python3 on PATH (`parent-artifact.log`, SHA `d039e1982c9ab3831e5cc69a6c74b872d5d6cded02d1a2aa9fd74d10632ec98b`). Original invocation without Python3 failed and is retained. Parent fresh G0 rebuild/replay passes all three legs, 9,988 entries: current receipt ID `e02264457e34f7492eb5e04f34c7ee218d5da35b8c2dc3af5d769125dd00135f`, receipt-file SHA `2c1b5e9e2c6852ed34476888eae7b400b42e22e8832ba19731f5d35e77df0a29`, executable SHA `1eb64e26bf2792362f4ea9a5556d7f295132cdf86e093a99d7e8e89da66e56f7`, `parent-g0.log` SHA `0bc9c0be8951236a9f7992de73ab32a7995bb64e7b3dba5d5459792800aea3ef`. This table/model check does not validate BIU RTL or establish silicon execution correctness.

Original Quartus unit tests report **252/254**, with two Q9 display-path assertions expecting `/bin/quartus_` while Windows paths contain backslashes. Their source, quartus_gate.py and artifact.py are byte-identical to baseline defe5a00. A scratch path-display normalization gives 254/254 diagnostically; it does not replace the original result or modify assertions/source. Both logs remain in `work/quartus-biu-yield/static-gates/`. The original static receipt has success=false and is not quoted as a blanket PASS.

A single fresh CONTROL/default multiplexed build, with yield disabled, passes G6 under Quartus 22.1std.2 Build 922 Lite: Fmax **38.19 MHz**, worst setup **+6.923 ns**, worst hold **+0.246 ns**; all four setup and four hold domains have **TNS 0.000**. There are zero compile errors, zero latches and 1,346 retained warnings. The inherited design is not fully constrained for setup/hold; this is the registered default G6 compatibility gate, not complete I/O/native/hardware certification or a reproducibility distribution.

CONTROL receipt ID `bcb1c6eab47b47ca4e54d724d9897c38b704343e262e2858a68f275fce7f6a42`; `work/quartus-biu-yield/control/control_receipt.json` SHA `3910a3a8404d1a09861bd3d3344c95c086359b57a127c780d939d5e29f1e55ad`. Parent independently verified 119 declared input hashes, four outputs and nine reports and read the raw STA panels/Fmax. The 85-input production closure matches the live tree, using the declared q22-selector copy of public q17 bytes. Generated BUILD_DATE 261007 has separate derived custody; the original input receipt is not retroactively extended. Supplemental `post_control_custody.json` SHA `536565d02969ef2990f039baec0eb8b366ce5eccbff5317db5f90847df91c58a`, raw `sta_panel_receipt.json` SHA `f71584a44a4a23d6a554e3dc5b4d6955ff83c85df8b47cca5ab4fced553fd3a4`.

The separate demux ON analysis-and-synthesis/VQM run passes: map zero errors/1,053 retained warnings, export zero errors/zero warnings. Parent checked input/output/stage-log hashes and mapped logic: variable BUS_OWNED and YIELD_PENDING feed the inhibitor LUT; YIELD_READY and BUS_EXCLUDE remain nonconstant output LUTs. `work/quartus-biu-yield/demux-on/demux_on_receipt.json` SHA `2bb0a650c6eb30e3ad4b1237ae04b607721f0963063de73ebffe6c70c341dfd7`; VQM SHA `106780dee0027b21ca110eb7f33bc12aa107bb7cbe8fc6eda4a3864e931a0cf0`; connectivity receipt SHA `31a91d93bbd04d7a92668514dac977ae736ef4230ba34d831332f0bbd7b152c7`.

No ON fitted timing/32 MHz claim, Quartus17 timing equivalence, RQ/AK-plus-live-EU integration, native physical ownership or SILICON MATCH is established. Multiplexed half-clock/output isolation and silicon contrast remain separate next stages. No hardware programming or private/PCS86 integration occurred.
