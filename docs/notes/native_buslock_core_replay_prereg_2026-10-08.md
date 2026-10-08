# Native BUSLOCK core replay — preregistration 2026-10-08

Branch `feature/native-buslock-rmw-validation`, baseline
`06d03a6866a83be1b718bd9d51ce3e7f2d42e572`. Commit this registration and its
inventory before implementation acceptance or any heldout native pin scoring.

This is a test/tooling stage using retained files and simulated FPGA RTL only.
No real V30 rig, socket, network probe, device import, board contact, flash or
production RTL change is authorized. No Quartus promotion or new G6 claim is
made. SILICON MATCH remains the native correctness bar.

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted. Complex or confusing observed behavior is likely simple systems interacting in ways not yet understood. A large fitted table, a many-cased rule, or a per-opcode special case is a signal of misunderstanding, not a deliverable.

## Immutable population and custody

`native_buslock_core_replay_inventory_2026-10-08.json` seals 19 original
decoded-row captures, their corresponding bank entries and decoded-JSON hash
sidecars, online-era provenance/divider/hold-proof/probe/rebank logs, and the
original historical generator Git source objects. Original captures stay in
place, unchanged. Compressed and decoded hashes have different declared
meanings; neither substitutes for the other. Text checkout alternatives are
limited to the inventory's exact Git LF and exact LF-to-CRLF byte hashes, with
the actual chosen hash recorded in every receipt; gzip identities have one hash.

Discovery is exactly `mc1_soup` keys **1057, 1105, 1110**. Heldout is the first
16 existing `mc1_soup` filenames with numeric keys at least 1140, selected before
viewing their native pin outcomes: **1147, 1150, 1157, 1184, 1189, 1191, 1192,
1201, 1206, 1210, 1212, 1248, 1251, 1259, 1284, 1285**. No filtering by opcode,
LOCK value or replay verdict is permitted. Keep every registered failure.
Once scored, all 19 native outcomes are exposed for future mechanism selection;
the 16 heldout cases protect only this frozen baseline comparison, and any
replacement law must validate a separately registered disjoint population not
used to select it.

The complete discovery exposure also includes `fz2c` raw keys 406002, 406020,
406056 and `fz2e` raw 521075, raw 530000, soup 502050. All six are documentary
only and excluded from this population while INV-2 context remains unresolved.
INV-1's original archive and INV-3's discarded REP population are excluded.
SUP-1 retired the v1 bank's standing denominator without falsifying its native
observations. This registration reopens a bounded 19-observation comparison;
it does not restore the old standing fuzz gate.

## Image and actual production replay

Reconstruct each complete 64 KiB image from historical generator commit
`4386ff71c2bcb93b87827da8d53757ca11cb00d7`, using the sealed original pure
`derive_case` → `build` → `check_seq.compose` recipe and exact recorded overrides.
Require the reconstructed image SHA-256 to equal its original recorded hash.
Generator drift is a hard failure. Current v2 composition must not reinterpret
these v1 images. Generated test images stay under parent `work/`; do not commit
binary images or ROM assets.

Replay the image through the actual production `system_large`/ucore and
`tb_sys` capture path, default CONTROL build without `X1_AD_RETENTION` or any
experimental opt-in macro. Bind the executable to its complete actual source,
build command, tools and artifact receipt. Reproduce each original fixed or
seeded-random wait profile, divider 8 and widened 12-bit event directive at the
original image anchor. Do not add a software CPU oracle or a substitute memory
or LOCK waveform to the native comparison.

## Registered numeric bars

1. Custody: **19/19** unique originals, exact compressed/decoded/sidecar/image
   hashes, matching recorded configuration and source provenance. Zero missing
   cases, ambiguous source, malformed pin/index values or changed original bytes.
2. Candidate capture: **4096** retained raw 64-bit words per case. Decode bit 50
   directly, active-low `lock_n`, preserving each original absolute raw index.
   The predicted first nonreset index is **33**; require it exactly. Native
   rows have original indices **33–4095**, exactly **4063** per case. Native
   reset indices 0–32 are unknown and remain explicitly unscored. Do not invent
   their pin values. Any capture/reset/index drift is a registered failure;
   do not shift, search offsets, stretch, trim or fit it away.
3. Native pin match: **19/19 cases**, zero `lock_n` mismatches across all
   **77,197** registered native rows. Report discovery and heldout separately
   and retain every mismatch with exact absolute index and input identities.
   Instruction attribution may explain a failure but cannot alter its bar.
4. Tooling: all registered meaningful falsifiers pass, with at least **16**
   covering custody/image/source tampering, wrong profile/macro/binary receipt,
   missing/invalid pin, duplicate/missing/shifted indices, truncated/malformed
   raw words and attempted offset fitting. Synthetic tests validate the tool;
   they are not chip observations. Independently rerun the runner/comparator
   and inspect their source closure before accepting their results.
5. The constant-high diagnostic must **FAIL** on the disclosed native lows.
   Actual production replay and its pin failures are separately reported;
   the literal assignment is not an RTL execution. A valid tooling receipt
   does not turn a failed native pin comparison into silicon match.

## Close-out and deferred work

Freeze the replay bench/runner/source closure before heldout scoring; record
before/after hashes, preregistration commit, original source identities, actual
binary and complete raw captures. Preserve failed attempts. Verify all tracked
production RTL and original captures unchanged. Publish the actual native
verdict, including NO-GO if any case misses its registered bar.

The disclosed odd-address RMW and other memory examples justify this bounded
replay. They do not pre-accept a general assertion/release law, REP duration,
physical pin timing or external RQ/AK suppression. RTL modeling or promotion
requires a separate registration and the required fresh CONTROL G6.

After this baseline is scored, all 19 pin outcomes are exposed for future
mechanism selection. Any replacement native law must be preregistered and
validated on a separate disjoint population not used to select it.
