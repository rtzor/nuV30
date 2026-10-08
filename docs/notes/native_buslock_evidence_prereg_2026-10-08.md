# Native BUSLOCK evidence tooling — preregistration 2026-10-08

## Scope and custody

Reserved branch: `feature/native-buslock-evidence`, base
`75e65e58760448026ed6696575bf75bfa7fd4e64` (multiplexed BIU yield).
This stage implements offline evidence and comparison tools only. It does not
change RTL, save-state mappings, hardware captures or the legacy 11-column
golden schema. No board contact, flashing or firmware intake is authorized by
this registration. Source captures remain immutable in their existing locations.

SILICON MATCH remains the only native correctness bar. Tooling acceptance and
observations of archived chip rows do not constitute a new core silicon match.

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted. Complex or confusing observed behavior is likely simple systems interacting in ways not yet understood. A large fitted table, a many-cased rule, or a per-opcode special case is a signal of misunderstanding, not a deliverable.

## Survey findings, not new acceptance results

The current ucore assigns `BUSLOCK_N = 1'b1`. Its `BUS_EXCLUDE` protects
ownership as an engineering guard and explicitly disclaims native timing.
The archived FSM has separate lock-active/done state, but its documented
leading-edge and waited-release residuals prohibit accepting a blind port.
The clean `tests/v30/f0lock_tranche` contains 400 socket cases with 11-column
cycles; those columns omit BUSLOCK. They cannot prove that pin's waveform.

Raw socket captures in `sw/testdata/tf0f/board` and
`sw/testdata/iret-tf/board` retain bit 50, the max-mode active-low LOCK pin.
Their `v_lock` probe is `F0 01 D8` (register ADD), with TF experiments around it;
it is not a memory read-modify-write probe. Retained interrupt captures also
contain LOCK observations. These populations can audit pin availability and
falsify pin comparisons; they do not settle memory-RMW assertion, split-write
release, REP duration, external RQ/AK exclusion or physical timing.

## Closed audit population

Select by declared experimental axes, before implementation:

- `tf0f/board`: `v_lock`, `nop`, `addrr`; waits 0–3, alignments 0–3:
  exactly 48 cells.
- `iret-tf/board`: geometries `I0` and `P1`, probes `v_lock`, `nop`, `addrr`;
  waits 0–3, alignments 0–3: exactly 96 cells.

Audit all 144 selected cells, retaining any failures. Do not pick cells by their
LOCK values or by whether a candidate passes. Pin-low counts and spans are
descriptive observations of full capture rows, with reset rows identified
separately. The control programs contain interrupt handling; do not label every
low pin outside the LOCK-prefixed probe a false lock. Historical interrupt
examples may be documented separately with their exact custody chain; they
cannot silently enlarge or replace this registered population.

## Tool acceptance bars

1. Exactly 144 unique cells must be located and audited. Zero missing cells,
   duplicate cells, malformed words, wrong lengths or hash disagreements.
   Verify original compressed file hashes and the capture table's canonical
   per-cell word-stream SHA-256, word count and image SHA-256 against the
   manifest. Require explicit socket source (`use_core` is the boolean false),
   divider 8, recorded source timestamp and verified capture provenance.
   Emit a reproducible receipt naming every source and tool input.
2. Decode every retained word at its original absolute clock index. Preserve
   all rows; expose bit 50 as binary `lock_n`, and identify reset rows. Missing
   pin data stays unknown and is an error for a requested pin comparison;
   never infer it from an 11-column golden, opcode, bus status or a high default.
3. The separate pin comparator requires explicit binary values, equal complete
   row counts and identical clock indices. No offset search, stretching,
   alignment fitting or ignored edges. Zero mismatches is its pass bar. A
   mismatch, missing value, malformed input, shifted index or truncated capture
   must return a nonzero verdict. A self-comparison only validates the tool.
4. At least 16 meaningful offline falsifiers must pass, including bit-50 decode,
   missing pin, pin value errors, missing/duplicate/shifted indices, length
   errors, source ambiguity/core-vs-socket rejection and custody tampering.
   Synthetic rows are explicitly tool tests, not chip observations.
5. A constant-high diagnostic is reported against observed chip pin rows. It
   must retain all mismatches and cannot be called an RTL execution or a native
   core comparison: it is the prediction of the current literal pin assignment.
   No minimum or fitted count of observed low rows is an acceptance bar.
6. Verify all tracked RTL and original capture bytes are unchanged. Independently
   rerun the accepted tooling and falsifiers, inspect the receipt hashes and
   load-bearing source, and preserve any failed attempts before publication.

No Quartus timing claim is made in this tooling-only stage. A future RTL
registration must define native held-out populations, edge predictions and
state custody, and obtain a fresh default CONTROL G6 before landing.

## Required close-out

Publish exact tool commands, evidence identifiers, all failures, observed
coverage and remaining capture debts. Keep the stage's native implementation
status explicitly pending. Draft publication belongs to `rtzor/nuV30`, stacked
on `feature/muxed-biu-yield`; do not merge preceding experimental PRs.
