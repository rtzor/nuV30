# Native BUSLOCK mechanism survey — 2026-10-08

Status: **READ_ONLY_DISCOVERY_COMPLETE_NATIVE_RELEASE_UNRESOLVED**. Read-only discovery is complete; no finalized mechanism or acceptance preregistration exists. Baseline is `b358e4cda0a6b48480c622e1623a604af0ea753d`, branch `feature/native-buslock-implementation`. This dated worklog preserves read-only findings from the already exposed nineteen cases. The unchanged PR6 binary was used only for authorized diagnostics; no production RTL change, new 43-case runner, hardware contact, new native capture or candidate acceptance is claimed. The separately reserved twenty-four remain unseen for pins, opcodes, timing and outcomes. The inventory prereg_path names a planned future document; the incomplete draft is retained only under work and does not authorize implementation or scoring. [E1,E5,E6,C1,C3,C4]

## Current conclusion and source reservation

Actual consumed F0 and actual INTA T1 events align between the retained native observations and the current core in the exposed population. The eight write-containing release examples support a clear committed at final-access evaluation, becoming visible in the following capture row. A generic non-writing release predicate remains unresolved. These observations justify further mechanism discovery; they do not establish a complete native BUSLOCK implementation. [E1–E9]

The public implementation inventory is a **source reservation**, not a frozen model or committed acceptance preregistration. It seals nineteen exposed discovery cases and the first twenty-four available `mc1_soup` filename keys >=1292, numerically ordered, with no outcome-based selection. The 139 source inputs have exact byte identities, 53 text paths permit only declared GitLF/exactGitLF-to-CRLF identities, and eleven historical generator objects reconstruct exact 64 KiB image/config identities. All 24 images are unique and disjoint by SHA-256 from the previous 19. Source-image separation is a custody property; it is not native outcome acceptance. [C1–C3,C6]

Retained native input for the nineteen mc1 cases is decoded JSON rows with explicit binary `lock_n`. Original native raw64 words and reset indices 0..32 are unavailable. The previous replay uses direct original indices 33..4095; its candidate 4096-word/reset mapping is preserved. INV-1 originals with truncated 8-bit hold300→44 remain excluded; selected repaired recaptures record12-bit hold300, native socket `use_core=False` and divider8 readback provenance. SUP-1's old standing population remains retired, with observations retained for this bounded discovery. INV-2 fz2 observations and INV-3 reroll-biased archives remain excluded. No absence of other native evidence is asserted beyond this declared population. [C1–C3]

## Observed event and capture phase evidence

The exposed 19 contain 93 closed native LOW spans: 75 INTA intervals delimited by 150 actual T1 events, plus 18 prefix spans. All 18 prefix onsets consume literal F0 at the same original index/address in native and current-core queue reconstruction, matching exact source image bytes. Twenty-one FIRST F0 consumptions include repeated prefixes inside existing spans. Both queue reconstructions have zero underflows. All 93 release-phase tuples agree;91/93 onset tuples agree, with the two differences confined to late status at mc1/1189 rather than T/QS/early status. These are bounded bus/event observations, not architectural validation. [E1–E3]

The trace phase is independently supported by **4810/4810** consumed candidate QS bytes agreeing with EU `q_byte` at `EUline=rawidx-33`. All 4715 consumed addresses inside the low 64 KiB match trace PC; the 95 boot-address pops outside that range are not claimed as direct PC identity. Neighboring offsets32 and34 fail (271 and3507 byte matches respectively). This alignment was checked using candidate byte/PC evidence rather than fitting native LOCK edges. All 19 +eutrace captures and all 19 combined +eutrace/+utrace captures preserve the original PR6 raw bytes exactly; the parent independently confirms the phase and both diagnostic identities. The diagnostic capture identity establishes non-invasive tracing, not pin acceptance. [E4–E6,E10]

The parent also freshly replayed the unchanged binary on all 19 exposed programs: each raw capture and its 8132 CPU trace lines are byte-identical. Complete logs are retained. An earlier whole-log identity assertion failed solely on the variable Verilator walltime/speed footer, while its raw capture identity passed; that failed attempt is preserved. Reproducible CPU trace comparison does not erase the failure or change a native acceptance bar. [E11,D1]

## Hypotheses and refutations retained

| Hypothesis | Current finding | Evidence |
|---|---|---|
| Assert from delayed semantic prefix decode | Source scheduling predicts a late leading sample; this delayed-pin candidate was not implemented or scored. Actual FIRST F0 consumption supplies the observed available event. Repeated consumption stays inside one span. F1-as-prefix is not validated by these 19. | E1,E3 |
| Release immediately by combinationally masking final-write eval | Refuted for the eight observed write-containing releases: the eval row remains LOW and HIGH appears one row later. | E4,E6,E8 |
| Release at every final-write T4 | Refuted by waited mc1/1110: T4 at1054 remains LOW, HIGH begins1055. The odd mc1/1105 first write half must not release; HIGH begins1665 after second-half eval1664. | E1,E2,E8 |
| Clear non-writing instructions at ordinary S_INSTR_END | Refuted as a common release key: observed release occurs in different prechain phases before the ordinary prologue clear. A state/opcode lookup is not a demonstrated mechanism. | E4,E5,E7 |
| A previous MEMW/IOW completion explains those non-write releases | Refuted in checked windows: the relevant preceding access is CODE, not a leftover write; CODE eval-to-release delays also vary. | E8,E9 |
| Export conservative bus exclusion as the native pin lifetime | No such equivalence is established; ownership exclusion has separate, broader semantics and must remain intact in any later candidate. | E1,E2,C4 |

The eight retained final-write eval→release pairs are1136→1137,1956→1957,1664→1665,1054→1055,2111→2112,1158→1159,1071→1072 and1231→1232. They support CE-committed clear timing in these cases. Existing last-cycle metadata distinguishes the two halves of one odd access; it does not prove the final write of a multi-write instruction or REP sequence. Eleven prefix spans contain no MEMR/MEMW T1, including an OUT. Seven memory-write spans plus that one IOW span give eight write-containing contexts; the remaining ten prefix spans have no MEMR/MEMW/IOW T1. Absence of memory activity cannot be equated with register-only execution. [E1,E3,E6,E8]

Non-write examples currently release at DEC212/S_NORM_CHG, DEC1108/S_EPOP, CMC322/S_1BL_CHG, MOV-immediate2037/S_ROW_CHG and ordinary micro-rows for OR1500 and immediate16 operation2420. Neither a single demonstrated retirement event nor a fixed CODE-eval delay accounts for them. Operand/next-byte availability remains a hypothesis. The precise generic predicate and its publication phase must be understood before freezing a candidate. [E4,E7–E9]

## Already exposed simple-register discovery

The broader source audit covers 144 previously exposed cells, with exact custody/image reconstruction. Only 48 `v_lock` programs were executed using the unchanged actual PR6 core; the 96 control cells were included in custody, not new core execution. The 48 diagnostics retain 133,520 native raw words,288 closed LOW spans and 1,584 LOW rows. All 288 starts consume FIRST F0; all 288 releases are one row after consuming the final D8 ModRM byte, with native/candidate/image byte attribution equal and zero queue underflows. These exact observations concern the fixed simple ADD program with its retained TF-generated trap/stack/vector context. They do not promote a general opcode timing rule. [E12,E13,E14,E15,T1]

All 288 release snapshots are S_ROW/upc0.01.0. At 108 of them the successor queue is unripe, refuting release only when a successor is ready. There is no memory/IO T1 inside those 288 spans and no INTA T1 in the inspected ±8-row neighborhood; this bounded local check does not remove the program's surrounding trap context. The full native/core nonLOCK raw comparison has 99,014 diagnostic difference rows, retained separately from event attribution. No full architectural or native pin match is inferred. A serialization-only TypeError in the first analysis attempt is preserved with its original instrument; the correction changed a summary dictionary key to a string, without rerunning or altering captured core/native data. [E12,E13,E14,E15,D2,T1,T2]

The parent independently rechecks all 48 full native/candidate frames, exact images, both shadow queues, every F0/01/D8 consumption/release context and 108 unripe releases. Its totals agree exactly. [E14]

## Pending work and preserved boundaries

The source audit, exposed diagnostics and independent review are complete. The reviewer verifies all 144 original native raw64 captures, with RESET records available: 400,560 words and 1,584 LOW rows. The 96 noLOCK control cells have zero native LOW rows in this fixed retained corpus; those controls were not newly executed on the candidate and do not establish a global false-LOCK result. This original raw64/RESET custody is separate from the nineteen mc1 decoded observations whose original raw64/reset prefix are unavailable. [E12,E15] The twenty-four source-reserved cases remain protected until a concrete candidate and numeric preregistration are committed and the actual production candidate plus replay scope are frozen. Once scored, those 24 become exposed; a law selected using their outcomes would require a separately registered disjoint validation population. [C1; pending follow-up]

No new flop, save-state mapping, gate PASS, synthesis promotion, FPGA timing or hardware correctness follows from this survey. Native F1 alias, multi-write/REP lifetime, segment wrap and other undocumented axes remain outside this bounded demonstrated scope. Existing PR6 runner/docs are unchanged; all 27 prior output files and all 5 PR6 files pass preservation checks. The next step is to resolve the generic non-write event from exposed evidence, retain refutations, and then preregister one simple falsifiable mechanism. [E1–E9,C1,C4,C5]

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted. Complex or confusing observed behavior is likely simple systems interacting in ways not yet understood. A large fitted table, a many-cased rule, or a per-opcode special case is a signal of misunderstanding, not a deliverable.

Source interpretation in the hypothesis table is independently recorded by the implementation and review surveys; their mechanisms remain proposed or refuted, rather than promoted. [S1,S2]

## Retained artifact identities

Paths below are relative to the parent workspace. These local retained proofs are source evidence; this document does not relabel them as new native acceptance.

| ID | Retained artifact | SHA256 |
|---|---|---|
| E1 | `work/native-buslock-implementation/exposed-mechanism-observations.json` | `cca17332c167a8e5d7a15ee2486d2b8349c1b27e2791ec6d02b2dd8b99d4eeeb` |
| E2 | `work/native-buslock-implementation/review-exposed-edge-proof.json` | `8c4bd70f55339916987d4754d9a6bb77399c062b50371c67dd5f1cfde32a8c37` |
| E3 | `work/native-buslock-implementation/review-prefix-events-proof.json` | `df3193a3af478a2c9152a8b230add2c9611c0b4b25afd34944df7d786458e471` |
| E4 | `work/native-buslock-implementation/review-trace-phase-proof.json` | `1c946c8f411bf6f89f851291171aad7bf8fdc8681213a16878c35a621b722f64` |
| E5 | `work/native-buslock-implementation/diagnostic-eutrace_rvoonx73/proof.json` | `4db162a2d895db91671b852f6a1d6c187f2fd8f8e56f2298e5185afe9946b0ce` |
| E6 | `work/native-buslock-implementation/diagnostic-bothtrace_o1mlzbu0/proof.json` | `2cfcd8aed10a82a0afd5938a5a9762f2ebcd086f69734e703c70a73860b5744e` |
| E7 | `work/native-buslock-implementation/prefix-release-trace-discovery.json` | `2ec87218b901ca0bb1918ab9bb44f118132ad3b249f716298c9a4e305c741fa8` |
| E8 | `work/native-buslock-implementation/combined-trace-release-discovery.json` | `ff119f7c8269c48149767b8fd742837aa226f689400b28b9e5fabecb06f1b93e` |
| E9 | `work/native-buslock-implementation/review-previous-write-proof.json` | `c7843fec8e687f03e36b51e2433d7e6f090a5045217f170fc789a8d8b33366b5` |
| C2 | `work/native-buslock-implementation/parent-inventory-metadata-check.json` | `093802fa71a2830732043880733853723291fdf2494d778e00226ef2901b9707` |
| C3 | `work/native-buslock-implementation/parent-final-custody-check.json` | `613f25cb505fe81390317dadc5e2263ebc07149c7ba148ce5b6a4f5cc5cb821d` |
| C4 | `work/native-buslock-implementation/pr6-preservation-check.json` | `3714dd0c18dd88665bb5c46f03341ceef2752756faea4f310e781d5ca1635ebb` |
| C5 | `work/native-buslock-implementation/previous27-outputs-baseline.json` | `740eafab7a9693b7029a4a25d6de8ea5b167e704e4eaa826f1630ea432de43b1` |
| C6 | `work/native-buslock-implementation/review-inventory-final-reference-proof.json` | `592ca23023f5f6bf66e4ba74e46d31acf2bc777fcf4708a5cad7ef306c97c4e5` |
| C1 | `nuV30/docs/notes/native_buslock_implementation_inventory_2026-10-08.json` | `f676854eed588565a221da7d1c2480a3963ebd99f0ba0e55c3aa2939ad0c45a4` |
| E10 | `work/native-buslock-implementation/parent-diagnostic-phase-check.json` | `546c929b194c69f1c1b75a7ae79de1b62b6a45f15590deda97ab50fa40fe5fde` |
| E11 | `work/native-buslock-implementation/parent-diagnostic_nhw6d_8_/proof.json` | `96ef80fd2bd490234dd43b2bf60fab77b10b0a711b71418d9dd82849ec5e309c` |
| D1 | `work/native-buslock-implementation/parent-diagnostic_sc1qbbum/failure.json` | `4811cb77a9d5d7496b21767ba937edde742897a15b369ebde05d9a0ba6b80191` |
| S1 | `work/native-buslock-implementation/mechanism-survey.md` | `8dbfb94552786f8e075734ee42dc5d1f6aff8f292466976d4a0ef05677a40107` |
| S2 | `work/native-buslock-implementation/review-survey.md` | `e0e3af8cbf16bb1e0ae6d2019570c7898d6aff49ebe0a45299e1eb5732fda663` |
| E12 | `work/native-buslock-implementation/diagnostic-simple144_kt0zxdjv/proof.json` | `1b28b449add1c7fb5e6b5422b393e9a3d2caaee44f995e4538cb3b2c41d5c806` |
| E13 | `work/native-buslock-implementation/diagnostic-simple144_kt0zxdjv/release-findings.json` | `8286c5e842ad3c003d797e1c661d5609f437b82b4e00b9fb7e6901f9e2fe8f76` |
| D2 | `work/native-buslock-implementation/analysis_initial_failure.txt` | `f81215a14a47ce7c02cf29a3b5c0227a8d4409d5dda7f30ff9e7a21818944647` |
| T1 | `work/native-buslock-implementation/analyze_simple_discovery.py` | `c728d758458d3269a5697d9313c084cdd833d32fbeaf6a75071a713ee900043a` |
| T2 | `work/native-buslock-implementation/analyze_simple_discovery_initial_typeerror.py` | `8d32ecef9aa707285c53be0b82242ae6f6f8252c71568faadd18b928801209cd` |
| E14 | `work/native-buslock-implementation/parent-simple48-discovery-check.json` | `b6eab32abca4794e6e98d945c04cbbcf63da72d810dc9408dfa332dea8c13a27` |
| E15 | `work/native-buslock-implementation/review-simple144-proof.json` | `d7276399598d5369cb98ffdc0d6cfbdcc753b408c6e56fa2851344effaa4e7e1` |
