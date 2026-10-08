# Native BUSLOCK release-control discovery — 2026-10-08

Status: `READ_ONLY_DISCOVERY_COMPLETE_NATIVE_RELEASE_UNRESOLVED`.

This stage adds a simulation-only observer and retained diagnostics; it does not implement native BUSLOCK. Production baseline is `288af1b70b55973c88059e434ffa94bdae99f996` (the preceding change was documentation only), and the executable production design remains PR6. `v30_core.sv` still assigns the native pin HIGH. The previous strict 19-case baseline had 1,012 native BUSLOCK mismatches (PR6 parent replay receipt `replay_7hchntwq`, SHA-256 `a3c5f7376f19be256c33b151c99cd2bc6a6a3de6becd2d6e2af46c68c916b383`); that result is not revised here. The 24 reserved cases remain uninspected. No device contact, RTL/save-state modification, native acceptance run, synthesis or G6 claim occurred.

## Instrument and custody

`hdl/tb/native_buslock_release_observer.sv` is an exact byte copy of the work-owned observer that was built and run, SHA-256 `d3559908415c6a4fc04392ea141bacd18266fd64386668fdc17848865f6e1488`. It binds to `v30u_eu` only when explicitly added to a simulation command. It is not included by production files, default build recipes, QIP or QSF, and must not be included in synthesis. It adds no core port or machine state.

The fresh build used the existing actual `tb_sys` CONTROL recipe with `V30_MUXED_AD` and the observer as the sole added source. It retained production assertions and unsuppressed UNOPTFLAT checking. The build receipt is `work/native-buslock-release-control/observer_build_1t7qw8_w/receipt.json`, SHA-256 `8cb9aeca718fec68ee212dff74edca57d608d0b4c1bddb5f55356a3eb6edae47`; it seals production sources, includes, runtime ROM hex files, observer/scripts, tool executables and Verilator runtime headers, together with full build outputs and source snapshots. The initial observer-only build failure is retained in `observer_build_rqbq5h6i` (receipt SHA-256 `ca653985a9214433a1f5a00b7e226edf98dd4f785f6ac91afd7d564c9555066e`): it referenced nonexistent `sig_flags_n`. That reference was removed without a warning waiver.

Exactly 67 exposed profiles were executed: the previous 19 original images/events/wait profiles and the 48 simple `v_lock` profiles. All 67 produced capture bytes identical to their immutable earlier diagnostic baselines. The 67 targets are distinct, including `P1_` and `I0_` cell names. Full commands, captures and CTRL/EU/BIU logs are in `observer_replay_guwssms6`; its receipt SHA-256 is `2c88701c8bfc3221b2ee280d3db941955e972a559c7f1c21f640684c3ae2dc32`. These are observation-preservation checks, not native correctness or architecture checks. The parent independently verified all 211,344 original candidate raw rows, all 204 receipt inputs and 201 outputs, and the sequential observer counters: `parent-all67-observer-proof.json`, SHA-256 `d8eabecedbd4fdf65cedcd46249fc33e724612ef5f15913ea9b65679ee0a958b`. Independent source custody also verified 894 unchanged files, including the previous outputs/captures, source metadata and hash-only reserved-image identities: `preservation-check.json`, SHA-256 `af87ddb9ec64e5e5139082ff750efcedbcaa631086564fa7dae73fe27265433a`; the parent independently repeats this in `parent-preservation-proof.json`, SHA-256 `d6cc814d087bd0ee4c1a74ec6e2971ad1e52a0e53bfaa8343e9fd15dfc96b4f5`. No old capture or proof was overwritten.

The parent additionally replayed the two exposed DEC profiles with the accepted observer binary and obtained byte-identical raw and CPU/observer traces: `parent-observer_rhde94yg/proof.json`, SHA-256 `a27af61861127909ac3221ef6ac0ebb28458c31c544f3f977b23857d35d35e47`. The reviewer independently verified all 67 artifact closures, current/next ROM lookups and captured queue attribution (`review-observer-proof.json`, SHA-256 `2321fc1bf204c629d540e23013aed053c3aee6283590a804f1ff97c747006c11`), including the build closure of 105 inputs/88 outputs and 18,754 same-index captured queue/observer byte matches, and independently reproduced all four predicate distributions (`review-qualified-predicates-proof.json`, SHA-256 `81a7551abdb07a8a54ad99c69a091e57181b06e162d367abea79b4eea64eb42d`).

## Clock and signal meanings

The observer prints one `CTRL` line per actual core CE and resets its counter under `srst`. Decimal `c=0` is the first nonreset capture row; the fixed harness contract gives original capture index `c+33`. This mapping comes from reset/capture timing, independently corroborated by original-index QS byte consumption, not from fitting LOCK edges. `c` is decimal; all other printed values are hexadecimal. Observer logs continue through the harness drain: three postcapture lines for the old 19 and nine for the simple 48, as independently checked in the parent proof. This variable tail does not change the fixed +33 mapping inside the captured window. The initial independent assumption of a universal three-line tail was refuted and retained in `parent-counter-assumption-failure.json`.

Registered `st`, microaddress, bindings and operands describe the pre-commit view. Combinational `*_n` describe the actual next-state function available at that edge. They are not an already-executed future operation. ROM fields describe the current ROM output, which may remain stale outside S_ROW. Interpreting an act requires its actual step/resource qualification. `row_acts_ok` below names a particular public-act predicate, not a necessary condition for every step-side micro-row transfer: a step can consume its final Q operand and execute the row in the same CE even though pre-edge `rowq < row_qn`. For example, old mc1/1057 at index 2036 has `row_acts_ok=0`, `row_need_q=1`, `q_pop=1`, `q_ripe=1`, yet the step consumes the byte, changes tmpb from `0xCC43` to `0xFFDC` and hands to ROW_CHG. Source `v30u_eu_step.svh` lines 612–615 increments the working operand count and stops only if another byte is still needed; lines 655–668 then execute `v30u_eu_row.svh` when `stop` remains clear. The observer witness is retained in the full interval of `qualified-release-discovery.json`. In particular, readiness levels (`retire_ok_*`, `q_ripe_lead_n`) are not completion events.

`q_pop`/`q_first` are EU intent outputs and can assert while `q_ripe=0`. Actual consumption is established from captured QS and the reconstructed CODE queue, with image-byte corroboration. The observer uses `int unsigned` ports to widen scalar fields for printing only; packed pre/post GPR views retain their 128 bits. It does not change DUT widths or update any observed signal.

The analyzer's next-ROM word is an offline lookup in the exact declared `ucrom.hex`, using `dec_bank_next*4+(upc_loc_n&3)` and `dec_valid_next`. It is a decoder preview, not a qualified current act or an implemented hardware producer. DEC49 demonstrates the distinction: at row 211 the next bank still belongs to the previous instruction; the new bank/E row becomes visible in the next-state view at row 212, while current qualified E executes at 213.

## Direct native READY falsifier

Direct bit 51 decoding of the original simple raw64 captures finds 168 READY-HIGH and 120 READY-LOW rows at the 288 native releases. The preceding/final-ModRM rows are 132 HIGH and 156 LOW. During the LOW spans there are 780 READY-HIGH and 804 READY-LOW rows. This refutes a rule requiring sampled native READY-HIGH at release. It does not identify internal native EU gating: capture READY and BUSLOCK have different sampling rails. The old 19 decoded native rows lack READY, so candidate READY was not substituted for missing native evidence.

The complete per-span native table is `native-ready-discovery.json`, SHA-256 `2940a599bea2eb1c47fc511f657d6e12d6409f756d62d69e240fc2b9f95a2808`. Independent reviewer proof `review-native-ready-proof.json`, SHA-256 `30b50dfc1eeca490925c423b41e9fe53140ee57820655737ec647f36a38af987`, reproduces these counts.

## Qualified control falsifiers

Analysis covers the ten exposed nonwriting prefix spans and all 288 simple ADD spans. In the model instrument, `q_ripe_lead_n` is HIGH at all ten old releases, but only 216 of the 288 simple releases; it is LOW at 72. On the preceding simple rows it is HIGH at 192 and LOW at 96. Thus a proposed rule using the model's lead-ready signal as a necessary release condition misses native observations. Internal native queue readiness is not directly observed.

The following predicates were examined as discovery probes. No predicate below was registered or implemented as the native model:

- **Current E:** `row_acts_ok && e_e && retire_ok_e && q_ripe_lead_n`.
- **Current boundary:** `(bnd_row || bnd_epop || bnd_opc) && q_ripe_lead_n`.
- **Next-ROM with lead:** `st_n == 22 && next_rom_valid && next_rom_E && retire_ok_n && q_ripe_lead_n`.
- **Next-ROM without lead:** the preceding decoder-preview expression with the final lead term removed.

The table reports the first predicate event after the F0 onset. Phase delta is predicate index minus native first-HIGH index. Search is bounded to `start+1 .. release+3`; “absent” means absent in that window, not absent forever. A matched index is correlation in exposed discovery data, not proof of a native physical producer.

| Probe | Ten old nonwriting spans | 288 simple ADD spans |
|---|---|---|
| Current E | 1 delta 0; 5 delta +1; 4 absent | 228 delta +1; 60 absent |
| Current boundary | 1 delta 0; 6 delta +1; 2 delta −1; 1 absent | 228 delta +1; 60 absent |
| Next-ROM with lead | 6 delta 0; DC delta −1; 3 absent | 216 delta 0; 72 absent |
| Next-ROM without lead | 6 delta 0; DC delta −1; 67 delta −7; DEC4F delta −3; CMC absent | 288 delta 0 |

Complete locked intervals, pre/post signal windows and exact predicate definitions are retained in `qualified-release-discovery.json`, SHA-256 `fa0bf1304ab01a1b31a7919b8da333fe7d1299885c5dd5a3d14990d7ab985558`. In particular, DC has current E at its native release whereas DEC49/INC/AAA/OR/AND and MOV generally release before current E. DEC4F and 67 enter an EPOP wait; their first boundary+lead event occurs at 1107/1444 while native remains LOW, followed by HIGH at 1108/1445. CMC's lead transition similarly precedes its change phase. A CE-committed clear and a combinational level mask therefore cannot be interchanged.

The simple programs have TF trap context. Their next actual FIRST consumption is 44–64 rows after release, rather than immediately after release (reviewer `review-nextfirst-proof.json`, SHA-256 `97b99ba41e395d92fa91760058afa713ece9ba6921a34fdc15e45ea9ea42d524`). This refutes unconditional next-consumption causality; trap recognition may avoid taking a successor byte. Any future physical end/lead model must explain both the ordinary and interrupt paths, with qualified current/future sampling.

## Reproduction

Run from the repository with Python `C:/msys64/ucrt64/bin/python.exe`, MSYS2 clang64 and the declared runtime ROM tables present. The working `build_observer.py`, `run_observer.py` and `analyze_release_control.py` are retained under `work/native-buslock-release-control`, with their original bytes embedded in the closeout proof. The build and run receipts retain the complete actual argv and every runtime image/profile argument.

For a fresh diagnostic build, construct `native_buslock_core_replay.build_command(fresh_directory)` and append the absolute path of `hdl/tb/native_buslock_release_observer.sv`. This is the exact production CONTROL recipe plus the byte-identical public observer; do not change top, opt-in macros, wait/event settings or ROM inputs. Invoke it through the runner's existing MSYS bash/clang helper. The directory must be newly allocated. The historical script used the equivalent work-owned source path before publication.

```powershell
# Historical archived commands, from the workspace root:
C:/msys64/ucrt64/bin/python.exe -B work/native-buslock-release-control/build_observer.py
C:/msys64/ucrt64/bin/python.exe -B work/native-buslock-release-control/run_observer.py
C:/msys64/ucrt64/bin/python.exe -B work/native-buslock-release-control/analyze_release_control.py
```

These historical scripts record the original artifact paths: a new build emits a new unique directory and receipt. A new run must use that new accepted diagnostic binary path, allocate a new output directory and preserve every original image, `div`, fixed/random wait argument and event argument from each sealed command. Do not overwrite the archived analyzer output. Verify all source/runtime/tool/binary hashes and compare complete candidate captures with the declared immutable baselines before using new observer logs. Archived receipt identities above refer to the original executions, not to a later invocation.

## Pending mechanism

The working hypothesis is that the missing producer concerns native instruction-end/control publication and its pipeline. That is an inference from the observed edges and model diagnostics, not a verified native internal-pipeline fact or a selected equation. The current model's execution timing and ROM preview alone do not establish that physical producer. A future equation must explain operand consumption/entry, qualified E execution, queue-starved lead waits and trap recognition with the same causal sampling contract. Exporting a stale ROM bit, adding a per-opcode/state delay table or combining the probes merely to match these exposed rows is not an accepted mechanism.

No native candidate is selected. The existing 43-case inventory is preparation for a future preregistration, not authorization to inspect its reserved 24. A complete equation must be fixed and committed before acceptance or those outcomes are examined. Native zero mismatches, non-BUSLOCK preservation and fresh default CONTROL G6 remain obligations for any eventual RTL change.
