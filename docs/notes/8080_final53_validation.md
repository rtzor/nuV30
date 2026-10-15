# Final53 finite engineering fixture

These checks cover the remaining 53 instruction forms in the 8080 emulation work:
4,824 baseline cases, 4,824 disjoint cases and two sets of 12 interaction programs.
They preserve native setup, BRKEM/RETEM state, public bus observations, memory,
interrupts, wait states and full per-clock output. This fixture alone does not
cover the earlier 191 forms or qualify the full V30, NEC silicon timing, or the
staged-LOCK macro ON profile. Invalid-BCD DAA inputs and the indicated word-boundary
cases are explicitly finite engineering assumptions in the case data.

Use Python 3.10+ and an installed Verilator/host C++ toolchain. Assertions remain
enabled and RTL warnings fail the build. `--verilator` and `--verilator-root`
select an explicit installation; `--make-flags` supplies platform make variables.
Tools and runtime DLLs must be available in the invoking environment's PATH.

```sh
python sw/check_8080_final53.py --project . --out ../final53-run prepare
python sw/check_8080_final53.py --project . --out ../final53-run prepare --verify
python sw/check_8080_final53.py --project . --out ../final53-run lint
python sw/check_8080_final53.py --project . --out ../final53-run build
python sw/check_8080_final53.py --project . --out ../final53-run run --suite baseline --workers 2 --build ../final53-run/build/receipt.json
```

The runner prints the new receipt path. Supply that baseline receipt with
`--baseline` when running `--suite holdout` on the same build. The other suites
are `smoke-baseline` and `smoke-holdout`. Every selected population runs fully;
functional failures are retained and classified, with no automatic repair/retry.
Each process reads one selected 2 KiB literal record.

Lossless gzip retains the entire original stdout/stderr, observed exit code,
EOF, line/byte counts and compressed/uncompressed SHA-256. Budgets remain 180 s,
100,000 SYS ticks, 256 MiB raw/64 MiB gzip per case, 4 GiB gzip per producer,
8 GiB initial free space and a 4 GiB free-space reserve. One or two workers are
supported. Keep previous outputs; use a new directory for a different build.
Runtime receipts describe only the population actually executed. No board access
or flashing is performed.

The interrupt checks retain the observed native IVT-before-frame ordering,
then verify the saved frame and IRET result. EI/DI programs use a fixed
sixteen-NOP observation window before RETEM, with the frozen ownership cursor
providing the instruction return boundary.

The portable CLI has passed strict compilation and both 12-case smoke suites
on the current C4 candidate. Its 24 smoke executions are separate from the
private full Final53 validation: 4,824 baseline cases, 4,824 disjoint cases and
two 12-case interaction sets, totaling 9,672. The earlier 14,800 regression
vectors also passed. The public case data and oracles retain the same literal
records and rules; the 9,672 private executions are not a full portable-CLI run.

The HLT observer distinguishes the fresh HALT bus announcement (BS=3) from
standby (BS=7, RD and UBE inactive). It waits until the owned HALT transaction
ends, then checks every system clock during a complete 32/48 CPU-clock standby
window. Masked INT remains asserted through the first successor's completion,
at least 15 CPU clocks plus inserted wait clocks, and the existing 75-system-clock
minimum. The sixteen-NOP program and every literal frame/PC/flag oracle remain.
The conservative completion witness is ownership of the third NOP after the
frozen HLT position, including programs with instructions before HLT.

The reference C4 source selects forced interrupt microsequences using the active
opcode namespace while preserving the interrupted MD flag for the saved frame.
This replaces a decode selection tied to MD, which chose the wrong sequence
after the first INT acknowledge. The interpretation remains an engineering
inference; no claim about a physical NEC selector is made.

The save-state stream uses SS_VERSION 0x90 and SS_COUNT 232, giving SS_TAG
0x90E8. The earlier F stream uses tag 0x8FE8. This does not establish state-file
compatibility across those versions. Native preservation comparisons permit
only the typed header-version difference; the remaining state words retain
their existing comparison requirements.

Native preservation also passed 122 paired comparisons / 244 fresh execution
legs against the reference profile, with full-output review. The only permitted
save-state comparison difference is the typed version header described above.

The final C4 G6 measurement used one CONTROL build with default seed 1. Main
fabric Fmax was 38.2 MHz, worst setup slack +8.205 ns and worst hold slack
+0.247 ns; all four setup and four hold TNS results were zero. The measured
artifact is `4e76e7855801abd4b2f1463c2ae8573f5c91390bbd926149a7eca954f5c7602c`.
The reviewed log retains 1,345 warnings: 1,344 ordinary warnings and one Critical
Warning 127005 for the 1,028 initialized microcode words in a 2,048-word physical
ROM. The documented remaining tail is zero-filled; the warning is retained.

The copied-database post-fit Verilog export passed transport and custody
review. The final C4 mapped checks now pass their stated finite scope:

- The low 10-bit decoder function covers all 8,192 native and 8,192 8080 lookup
  entries. Commit, hold and conditional induction are checked separately.
- Finite BASE/STEP, reset, opcode-namespace and T1 checks establish the modeled
  phase bridge. The domain is after a modeled reset/common rising edge, with
  217 proved physical-register coherence equalities; it is not arbitrary power-up.
- Eight frozen source microcode rows have used-consumer checks: DATA66 checks
  66 selected transfer/hold bits (24 queries: 9 UNSAT equivalence/hold and
  15 SAT activity/stall witnesses). CONTROL40 checks the queue, OPR/valid head,
  suspend, used BIU state, INTA width/slot, UPC/state, publication and hold
  (40 queries: 17 UNSAT equivalence/hold and 23 SAT nonvacuity/stall witnesses).

These are final C4 checks, not inherited C2 results. The first CONTROL observation
was rejected because two physical publication links were bound incorrectly.
Only those checker bindings were corrected; RTL, reference laws, guards and
populations were unchanged, and the rejected observation remains recorded.

Together with the functional and native-preservation results, these close the
agreed 244-instruction-form finite scope. The mapped result is limited to the decoder and eight selected
rows above. It does not prove every 29-bit ROM word, all reachable core states,
or whole-core retention.

These are finite engineering checks, including the stated DAA and boundary
assumptions. They do not establish full V30 coverage, NEC silicon fidelity or
hardware cycle matching, physical power-up behavior or reset-pulse delivery.
The G6 target is at least 32 MHz for FPGA fabric; the
CPU reference is 10 MHz. This result does not certify a 50 MHz system clock
divided by five or the staged-LOCK macro ON profile. Historical rejected
observers and instrument failures remain preserved separately.
