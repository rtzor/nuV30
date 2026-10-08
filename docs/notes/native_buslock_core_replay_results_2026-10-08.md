# Native BUSLOCK actual-core replay results — 2026-10-08

The registered native comparison is **NO-GO: 0/19 cases match**, with **1,012 BUSLOCK mismatches across all 77,197 native rows**. The tool and capture checks pass 19/19, and 53 tests, including meaningful falsifiers, pass. This distinction matters: the fresh executable runs the actual production ucore, whose BUSLOCK output remains constant high. A valid replay receipt does not establish native correctness.

Branch `feature/native-buslock-rmw-validation`, baseline `06d03a6866a83be1b718bd9d51ce3e7f2d42e572`; preregistration and source inventory were committed as `e383a5b930331ad5f6423120863624b3a431b631` before implementation and heldout scoring. No production RTL, existing testbench or original capture changed. No board/device contact, flashing, firmware intake or Quartus/G6 claim occurred. SILICON MATCH remains the native correctness bar.

## Closed population and actual execution

Discovery is exactly mc1_soup keys 1057, 1105 and 1110. Heldout is the 16 keys fixed by filename before their pin outcomes were inspected: 1147, 1150, 1157, 1184, 1189, 1191, 1192, 1201, 1206, 1210, 1212, 1248, 1251, 1259, 1284 and 1285. All cases remain in the denominator. The fz2c/fz2e documentary discoveries are outside this population.

Every complete 64 KiB image was reconstructed from the sealed historical generator `4386ff71c2bcb93b87827da8d53757ca11cb00d7`, using the original pure `derive_case` → `build` → `check_seq.compose` recipe. Every image and configuration hash equals its original record. Hardware-capable modules were excluded from historical execution. The historical generator's absent hold-width constant is preserved as an inert stub; runtime event packing independently reproduces the repaired 12-bit hold of 300 cycles.

A fresh Windows/Clang CONTROL binary uses unchanged `tb_sys`, `system_large`, the production ucore, its actual bus capture path and runtime microcode/decode tables. `V30_MUXED_AD` is enabled; `X1_AD_RETENTION` and experimental ownership/yield macros are absent. The AXI harness selects `use_core=1`, loads the complete image, runs normal reset and supplies the original event at the image anchor. Divider 8, all 13 fixed-wait profiles and all six seeded-random profiles are retained exactly. Event and random-wait register readbacks match the original packed values.

Each case produced exactly 4,096 candidate raw capture words. RESET is high at indices 0–32 and low at every index 33–4095, so the registered direct index mapping holds without adjustment. Native inputs are retained **decoded native rows with explicit `lock_n`**, not preserved original 64-bit payloads. Native reset-prefix pin values are unavailable and remain unknown/unscored. Candidate `lock_n` is decoded directly from bit 50 of each actual raw word.

| Cohort | Captures passing custody/frame checks | Native pin matches | Compared rows | Pin mismatches |
|---|---:|---:|---:|---:|
| Discovery | 3/3 | 0/3 | 12,189 | 251 |
| Heldout | 16/16 | 0/16 | 65,008 | 761 |
| Total | 19/19 | 0/19 | 77,197 | 1,012 |

Every mismatch retains its original absolute index and both pin values. The actual candidate pin stays high; the native LOW observations therefore fail. Separately named literal-high prediction files also fail on the disclosed LOW observations; they are diagnostics of the source assignment, not substitute RTL executions.

All-row busgrid diagnostics retain 67,517 rows with at least one differing transaction/address/data/status/queue field. These include unmasked electrically floating address/data samples and are not a scored architectural or transaction-match gate. Their count cannot establish a functional failure rate or excuse any pin mismatch. No offsets, stretching, fitted alignment or edge exclusions were applied.

## Reproducible commands and artifacts

Run from the repository root, using `C:\msys64\ucrt64\bin\python.exe`. Each build/replay creates a unique attempt and prints its new receipt path; use that new path for the next command. The archived receipt IDs below identify the reported experiment, not a replacement for a fresh build.

```powershell
C:\msys64\ucrt64\bin\python.exe sw/test_native_buslock_core_replay.py
$taskBuildLines = & C:\msys64\ucrt64\bin\python.exe sw/native_buslock_core_replay.py build --compiler clang
$taskBuildLines
$taskBuildReceipt = ($taskBuildLines | Select-Object -Last 1) -replace '^tool=PASS native=NOT_RUN ', ''
$taskReplayLines = & C:\msys64\ucrt64\bin\python.exe sw/native_buslock_core_replay.py replay --build-receipt $taskBuildReceipt
$taskReplayLines
$taskReplayReceipt = ($taskReplayLines | Select-Object -Last 1) -replace '^tool=PASS native=(PASS|FAIL) ', ''
C:\msys64\ucrt64\bin\python.exe sw/native_buslock_core_replay.py verify $taskReplayReceipt
```

Build receipt `build_aw3yb2jp/receipt.json` SHA-256: `67788912fdb5aedc13a2c8ebd0f2356c169476b5ce6e5af582a65eab95c8cda1`; executable SHA-256: `f35752580a74c18d20fcdcd436be728372c1c8703c8b600aaf02170c48a81b8a`. Compile logs contain no warnings/errors after the explicitly recorded baseline warning suppressions; UNOPTFLAT is unsuppressed.

Replay receipt `replay_0aw9au_z/receipt.json` SHA-256: `6e25c8566775e1399333d05cf61b3a7f2ad9c800ad41ef585d57ac00b5106b99`; summary SHA-256: `2964322405e3e2800aa3905332a4271d689b4d07f04fcad4f8d1c3cef7bccc78`. Verification passes all **171 input and 252 output identities**, including source/tool/test/registration bytes, tools and Verilator runtime includes, the fresh binary, original sources, generated images, full raw captures, exports, logs and all mismatch files. Replay exits **1** for the native failure; `verify` checks artifact integrity and does not change that verdict.

Independent parent acceptance repeated all 53 tests (`parent-acceptance/unit__76e0g39/receipt.json`, SHA-256 `3c2ff8c2c6267d8a674ba6bbb07dd504b671ddddfd75e0ba9908f511c0bac322`) and all 19 captures, with byte-identical raw outputs and the same 1,012 native mismatches. Its replay receipt SHA-256 is `a3c5f7376f19be256c33b151c99cd2bc6a6a3de6becd2d6e2af46c68c916b383` (`parent-acceptance/replay_7hchntwq`, 171 inputs/245 outputs; `-B` omits cache files). Full-row verification is sealed as `parent-full-row-verification.json`, SHA-256 `15ea43fc97761cf0459521c2df6d917bd35bc5fc22ad10f7fd41bb6eee560953`. Reviewer inspection independently confirms every row and seven CLI rejection controls; its control proof SHA-256 is `1abd21cc42372fea83c37732841f2669d3d937830016c37f73917f5b7624f57c`.

Frozen runner SHA-256: `a0f19ff072a59702cb544b9f57091ea15381b81dfdf651e322eb7dde173d9482`; tests SHA-256: `e98f4d97f262c0cb045ae987430b9c901e64814a8b4f26c6092739f9497b2327`. Sources remained unchanged through build and all 19 captures. Tests cover strict absolute indices/reset framing, raw width/count, pin types/adjacent bits, shifted edges, source/image/generator tampering, wait/event integrity, recipe/top/macro errors and stale/vacuous artifact closures. Synthetic tests establish tooling behavior, not chip observations.

Failed attempts remain retained: `attempts/tests-first` preserves the initial 43-test source snapshot and historical constant lookup failure; `attempts/build_jyh8d3qs` preserves its receipt, source snapshots and eight existing PROCASSINIT warnings. The subsequent runner adds the same compatibility suppression used by the earlier ownership runner. No RTL warning was repaired by altering production code.

## Pending native implementation

This stage establishes a reproducible actual-core baseline against retained native memory observations. It accepts no general BUSLOCK assertion/release law, no REP duration, no physical pin timing and no external RQ/AK behavior. All 19 outcomes are now exposed. A successor selected from them must be preregistered and validated on a separate disjoint population; any RTL promotion also requires the fresh registered default CONTROL G6.
