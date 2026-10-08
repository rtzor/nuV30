# Native BUSLOCK evidence tooling results — 2026-10-08

The offline evidence tool passes **144/144 custody audits and 40 meaningful falsifiers**. Native BUSLOCK implementation remains pending: the ucore still assigns the pin constant high. This stage changes no RTL or captures and establishes no new core silicon match. SILICON MATCH remains the only native correctness bar.

Base `75e65e58760448026ed6696575bf75bfa7fd4e64`, branch `feature/native-buslock-evidence`; preregistration `de2e41c6` and custody addendum `59a85985` were committed before their corresponding work. No board/network contact, flashing or firmware intake occurred. No Quartus timing claim is made.

## Closed population and observations

Selection follows declared experimental axes, never pin values: tf0f socket `v_lock`/`nop`/`addrr` × waits 0–3 × alignments 0–3 (48 cells), plus iret-tf geometries I0/P1 with the same probes/axes (96 cells). The LOCK probe is register-only `F0 01 D8`, not memory RMW.

Every original word retains its absolute clock index. Bit50 supplies binary `lock_n`; bit55 identifies reset. All 400560 exported rows independently match direct raw decoding.

| Retained socket source/probe | Cells | Rows | Pin LOW rows | LOW spans |
|---|---:|---:|---:|---:|
| tf0f/v_lock | 16 | 36000 | 384 | 96 |
| tf0f/nop | 16 | 36000 | 0 | 0 |
| tf0f/addrr | 16 | 36000 | 0 | 0 |
| iret-tf I0/P1 v_lock | 32 | 97520 | 1200 | 192 |
| iret-tf I0/P1 nop | 32 | 97520 | 0 | 0 |
| iret-tf I0/P1 addrr | 32 | 97520 | 0 | 0 |
| Total | **144** | **400560** | **1584** | **288** |

There are 4752 reset rows and zero reset-low rows. These are descriptive observations; no minimum/fitted LOW count is an acceptance bar. Controls contain interrupt handling, so their results do not define a universal no-prefix/interrupt waveform. Supplementary historical INTA observations are context outside this population; a first-INTA-pair table must not be read as the entire capture's LOW span, which can contain later pairs.

All 1584 constant-high mismatches are retained by source/cell/absolute index. This diagnostic is the prediction of the current literal pin assignment, **not executed RTL or a native core waveform comparison**.

## Custody failure and recovery

The latest merged iret-tf manifest omits image identities for 64 selected earlier nop/addrr controls. The latest-manifest-only interpretation remains **FAIL 80/144**, with 64 missing-image errors; originals were not rewritten.

The committed addendum fixes the acquisition source map for those 64 controls to the actual original manifest at commit `22151f64c7151120472c0be90591a18fa41964a1`, blob `facf358a9e434a86e1839b4013e922a3fe2de117`, path `sw/testdata/iret-tf/board/manifest.json`. Its 25182-byte snapshot SHA is `81e2f7f8dd1ced9848220e2e7c549f9d05b757b3f3eabb8f4e8182ec5a706462`. All 16 historical compressed control shards are byte-identical to current originals, and all 64 historical/current table tuples agree in canonical stream SHA/count and image identity. The other 80 cells keep their named current acquisition sources. No regenerated image recipe substitutes for provenance.

The public inventory seals 65 source inputs, recovered commit/blob identity and the fixed 144-cell source map: SHA `ebd351b947b791324d1fcefb54476ffc7e8087288aee581325c684870085b3cb`. Only pre-enumerated exact GitLF/CRLF text hashes are accepted; actual chosen bytes are recorded without runtime normalization. Compressed captures and canonical streams retain single identities. The tool checks boolean socket source, divider 8, recorded timestamps and flash verifyOK; those records do not prove unrecorded wait-rig cleanliness.

## Tool contract and reproduction

The pin comparator requires explicit integer binary values, complete equal nonempty row counts and identical dense original indices from 0. Missing/nonbinary pins, missing/duplicate/shifted indices, malformed input and truncation return nonzero with a receipt. Every mismatch, including reset rows, is retained. There is no alignment search or ignored edge. Legacy 11-column cycles remain pin unknown and cannot enter a requested pin comparison; check_core and the legacy schema are unchanged. Their 400 clean f0lock cycle/architecture cases do not verify BUSLOCK.

The 40 synthetic falsifiers cover decoding/adjacent bits/reset, strict pins/indices/counts, unknown legacy data, source ambiguity, custody tampering, historical seal/source-map omission and contradiction, exact checkout identities, and CLI failure receipts. Synthetic fixtures and self-comparisons validate tools only. A 1500-row native export self-compares with zero differences; its literal-high prediction rejects with 24 retained differences.

From the repository root, using Python3 and standard library only:

```powershell
C:\msys64\ucrt64\bin\python.exe sw/test_native_buslock_evidence.py
C:\msys64\ucrt64\bin\python.exe sw/native_buslock_evidence.py audit --latest-only
C:\msys64\ucrt64\bin\python.exe sw/native_buslock_evidence.py audit
C:\msys64\ucrt64\bin\python.exe sw/native_buslock_evidence.py compare expected.jsonl actual.jsonl
```

The latest-only command intentionally returns 1. Each command creates a unique attempt directory; full rows, mismatches, summaries, small input snapshots and receipts are retained. Accepted audit `audit_guww355m` declares 71 inputs and 151 outputs, all hashes verified. Receipt SHA `b09188d07cd50c25968be7c872246fbe6067a23783fa5010c446f4e6a24dd527`; full mismatch file SHA `d925b86a5b40cc6bc430eab6cf631b221598483bb09b8563c5e8e56938662794`.

Final latest-only failure `audit_8i7tzajl` receipt SHA `7516a4b5ae8cfc53d4eb0098506c22a1f827b998c0ed1d6c0003c6c8034a8456` preserves the refuted custody interpretation. Earlier `audit_f5wafhd_` preserves its superseded inputs before mandatory historical-seal hardening; it is not the accepted tool receipt.

Parent independently accepted fresh `audit_o00ytx2x`, all 71/151 hashes, 40 falsifiers and nine CLI controls: `parent-tool-acceptance.json` SHA `1263abeae74dc30e6d0e8eccbab327463a75d9e9fcd3e091aad9eed00faa0b55`. All 29 presealed alternate text checkout identities also pass 144 with identical observations: `parent-checkout-variants-proof.json` SHA `e407c5f6634b86b4f05ce86d30b762b3b2f6bf48214cbbbecbdfb3d5007156b0`. Reviewer source/full-row proof SHA `a05f71f6789d349c6148e9de74de269687c8a46e912d41a74836104a2b4240fe` independently verifies the closure. Tracked RTL and original captures/goldens remain unchanged against the registered base.

## Remaining native debt

The saved ucore LOCK-prefix lifetime currently serves an explicitly conservative FPGA ownership guard. The archived FSM lock-active/done mechanism admits leading-edge and waited-release residuals; transplantation cannot establish native correctness. This register-only population does not settle memory-RMW assertion, final odd split-write release, full REP duration, chained prefixes, locked HALT, external RQ/AK suppression or physical timing. Future RTL requires committed mechanisms/edge predictions, native held-out populations, state custody and a fresh clean default CONTROL G6 before landing.
