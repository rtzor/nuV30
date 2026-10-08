# RQ/AK plus live-EU BIU yield integration results — 2026-10-08

Engineering simulation evidence only. **SILICON MATCH remains the only native correctness bar.** No board contact or flashing occurred. No NEC pin timing, physical pad release, ACK edge alignment, minimum-mode, 8080, multiplexed half-clock isolation, production integration or fitted ON timing claim follows from these tests. The frontend HIGH-plus-two-CE return gap and conservative odd-split drain are engineering policies.

## Scope and source-derived contract

The preregistration was committed as `8953c3a3` before implementation and acceptance runs, on `feature/rqak-biu-yield-integration` from `1396afa0004e4f1ce2dc345a3684813cf4fcad24`, stacked on PR #2. Implementation changes only the new `hdl/tb/tb_rqak_biu_yield.sv`, the mutually exclusive `--rqak-biu-yield` runner mode, this report and the README. Existing frontend/controller/ucore RTL, older benches, production QIP and constraints are unchanged.

Source-derived: two actual macro-ON demultiplexed cores run with CE continuously live. Reference yield inputs are inactive. The actual frontend resolves each synchronous line as `~(remote_low | RQAK_DRIVE_LOW)`, feeds REQUEST to the level controller, and receives INTERNAL_GRANT. The controller uses YIELD_READY and genuine BUS_EXCLUDE. Inverted CORE_BUS_ENABLE feeds BUS_OWNED, including the combinational acquisition edge; REQUEST OR feeds YIELD_PENDING. Controller CORE_CE and CORE_CE_HALF do not feed the core. External isolation gates all modeled CPU transactions and read input. Peer writes require matching EXTERNAL_GRANT, isolation and inactive RESET; INTERNAL_GRANT or ACK alone grants no peer permission. RESET removes peer permission independently of registered grants.

The transaction instrument derives announcement and phase progression from public BS/READY, captures address at announcement and byte lanes on actual T1, and samples write data at completion. Registered BIU state corroborates phase; it is not the transaction oracle. All programs use public instruction bytes and initial register loading. Initial queue length and injected bytes are zero in every profile. No force or SS writes occur.

## Observed registered bars

Fresh final build `bus_ownership_4co50ll6` passes exactly **23 initialized profiles**, comprising 20 functional profiles and three RESET profiles. Each functional profile independently compares public bus, QS and architectural registers against the inactive-yield twin for at least 200 no-request CE intervals, followed by a fresh reset/load for arbitration. These are engineering conservation and interlock checks; twin agreement is not silicon evidence.

| Registered bar | Observed final result |
|---|---|
| Twelve protected profiles, LOCK even/odd INC, LOCK REP MOVSW CX=3, and IRQ/two INTA; waits 0/1/3 | 12 pass. Requests captured under real exclusion; no grant/ACK until exclusion and protected transactions finish. Each external owner has 35 live CE intervals including return arming. Even/odd result 0002, odd A5/5A neighbors, REP 1111/2222/3333 and CX=0 pass. |
| IRQ gap and frame | Each waits profile observes four excluded gap intervals. Exactly two INTA, vector 0020 to 0000:0100, terminal HALT IP=0104, CS=0000, SP=07FA and normalized stacked PSW=F202; stacked return IP equals the observed accepted boundary. |
| READY/dual-owner/DMA | Channel1 then channel0 real pulses retained with both resolved lines HIGH for 16 actual Tw intervals. No grant/ACK in the wait. Channel0 acquires first; queued channel1 follows with continuous isolation. Both external owners have 35 live CE intervals. Peer writes 3C5A then 6A35; after final return one fresh 0600 MEMR and one 0602 literal store are observed, AX=6A35 and memory[0602]=6A35. |
| Natural prefetch/DIV | Acquisition queue count is 6, without injected queue data. EXTERNAL_GRANT lasts 131 live CE intervals and contains two actual EU queue pops. Fresh public transaction completion resumes after accepted return within the registered 4096 interval watchdog. |
| Six started odd splits | Every stimulus occurs at public address0201, modeled phase1 and actual T1. WRITE stimuli have kind6, READ stimuli kind5; crossed with waits0/1/3. Both partners complete before INTERNAL_GRANT. INC writes yield0002 and preserve A5/5A; read completions0201/0202 occur exactly once each and terminal AX=0001. External ownership exceeds32 live CE intervals for each. |
| RESET drain/ACK/owned | 3 pass. Drain has captured pending pulse in actual Tw; ACK and established external ownership are nonvacuous. After reset REQUEST/GRANT/EXTERNAL_GRANT/drive/errors are zero, CPU bus enabled and peer permission false. Six actual stale peer write attempts, before and after each reset edge, are rejected with the0600 sentinel unchanged. At least16 live idle CE intervals follow with no stale request/grant/ACK. |
| Isolation, liveCE and protocol | Pre-edge and post-edge checks reject active/announced cycles and eligible INTA/vector/flush previews while isolated; modeled CPU completions are forbidden. Internal grant implies isolation through ACK and all return gaps, including final return. Core CE is explicitly2'b11 at every tick. One-hot internal/external grants, matching external/internal permission, no ACK/external overlap and exact unchanged REQUEST on sampled ACK echo all pass. EXCLUDE is prohibited at acquisition; later exclusion may legitimately rise as liveEU advances. |
| Full-chain unsuppressed UNOPTFLAT | 0 warnings. Dedicated lint removes the simulation build suppression, uses `--report-unoptflat`, retains its full log/artifacts and rejects any warning. |

Each functional target/drain/postreturn phase is bounded by4096 CE intervals; actual Tw by128 and return/queued transfer by128. These watchdogs make coverage failures visible and imply no hardware latency bound.

## Final receipts and retained failure

The runner declares 21 inputs for the new chain: new TB/runner, frontend/controller, all ucore SV/SVH and runtime HEX. Freshness checks before controls and after controls reject moved inputs. Tool versions and exact build command are retained with the full output; compiler warning output is not hidden.

| Artifact | SHA-256 |
|---|---|
| Final new TB | `514fa52d3456b29df8a520eaf1360b4c52f9b1c98da9074d0c214afed43949ab` |
| Final runner | `4779b0a1679561efbb7a6631e9c8d70271320ac20d46de7fbbf76112267529d9` |
| `4co50ll6/receipt.json` | `097572055ec4bef42d6a88ecdfafd4eaac7bd10103f16f12d826a0ada1c5db14` |
| Final executable | `8fa35874c90cea1cd840d4cb9f549e5c7aacf6ce73f4df1ab26c7a8dc4bc54a4` |
| Full final `gate.log` | `597dcd178b987da976907f06bfd1c963917eed95d97eff45169de296062a6a34` |
| Failed first `qwscf7ej/gate.log` | `62939de273cb4c08edff5ce0e027f8183ae4a7bde6dba55e49d723d3ce0ea90e` |

First build `qwscf7ej` completed21 profiles, then failed the RESET ACK watchdog. The reset frontend had not sampled idle HIGH before its initial LOW pulse, so armed remained0 and the pulse was not captured. The bench was corrected to sample idle HIGH in the ACK/owned RESET startup profiles. This is a test stimulus correction, with the failed log retained; no frontend/RTL rule or registered bar was changed. Review also strengthened final-return isolation, exact ACK echo checking and real stale write attempts, and replaced an unrelated DIV post-read delay with the registered fresh-completion watchdog. No result from the failed build is substituted for the final fresh evidence.

## Production synthesis custody

This milestone changes only tests/runner/docs. Parent verifies the last clean CONTROL receipt input/output/report custody (119 declared inputs, four outputs and nine reports) and all85 production closure bytes against the final tree, including the q22-selector alias and separate generated BUILD_DATE custody. The reuse proof is `work/rqak-biu-yield/test_only_synthesis_reuse.json`, SHA-256 `b150eefe3aec4a4d547be1ed643cf3d3c3a188097f3cbc1810b22bcc45cda120`.

The reused CONTROL artifact ID is `bcb1c6eab47b47ca4e54d724d9897c38b704343e262e2858a68f275fce7f6a42`, receipt SHA-256 `3910a3a8404d1a09861bd3d3344c95c086359b57a127c780d939d5e29f1e55ad`: Fmax38.19MHz, minimum setup+6.923ns, minimum hold+0.246ns and all four setup/four hold TNS panels0.000. Existing incomplete I/O constraints and1346 retained warnings remain recorded. This is test-only byte-preservation reuse of the earlier default/OFF compatibility draw, not a new Quartus build, a reproducibility claim or fitted ON timing. Previous ON demux analysis/synthesis/VQM evidence remains separately bounded by its original report.

## Fresh regression evidence

The final runner was frozen before all six fresh independent regression modes. Every receipt input, executable and full-log hash was checked against the final tree. Full metadata is retained in `work/rqak-biu-yield/agent-final-regressions.json`. These are engineering regressions; no C++ model was used as an oracle.

| Fresh build | Gate/result | Receipt SHA-256 |
|---|---|---|
| `bus_ownership_0zrtvxb7` | tb_bus_ownership_core contract simulation only | `dd27e52cb06958df2e36c02a9e3e0ec56c1a2582b15d0895c00c7b2c435f50c0` |
| `bus_ownership_29ws0cg8` | tb_biu_yield contract simulation only | `d271d7a5d6ecd5b97343b81da6ea148dad5f0339fbe50ba9964bf0c41b8cdfb4` |
| `bus_ownership_6ljroq_o` | tb_bus_exclusion contract simulation only | `b4ada30338a99fa1d418d7a35a1e92c61bd6bc17f6854218763170672a0cc4e2` |
| `bus_ownership_k5_z3qlh` | tb_bus_ownership contract simulation only | `7ec9aef73a326338a4e603b219575178313ef2eb7300734448f31236120715ce` |
| `bus_ownership_m9v7365k` | tb_rqak_core contract simulation only | `e249490711d1be45776cbf590d22db9da478e3a8280f76746d9ea94432f753b7` |
| `bus_ownership_ubktam1k` | tb_rqak_frontend contract simulation only | `fbeafeb22269f6ab6c0f95e901f3dc65c338d7cf6a7c07fbc03c3a9c202b0788` |

The existing yield gate passes28 actual core profiles plus six public-port BIU fixtures, two expected misuse diagnostics, three expected configuration rejections and all three unsuppressed UNOPTFLAT lint legs with0 warnings. The whole-core frozen pulse chain remains13 profiles; standalone frontend66 distinct/82 total checks, level controller26 checks, exclusion guard18 profiles plus default port absence, and default real-core integration pass. No old bench or acceptance bar changed.

Parent independently compiles and replays the new chain: `bus_ownership_614q9buz`, receipt SHA-256 `95c2bd01376341865126926cf901df188e33b889adeb4baee5b212b7825fa812`, executable `5a3c9d86634ce50f28cd5ff9cd055b0f2d48a8c66fdd6e002dabbf57cf0de54f`, full log `d1507df9b1066297861f95a1b8a4fb90ba7e96142475836cf5b4e6ee8b17a720`. Its21 inputs and both new-chain receipts were independently verified and both binaries replayed, with23 profiles passing. Parent acceptance metadata is retained in `work/rqak-biu-yield/parent-chain-acceptance.json`.

Parent also independently verified every declared input, executable and full gate log for all six fresh regression receipts, then replayed all six binaries successfully. Mode coverage and receipt uniqueness were checked; final metadata is retained in `work/rqak-biu-yield/parent-regression-acceptance.json`. Source review accepted this bounded engineering contract without further concrete objection.
