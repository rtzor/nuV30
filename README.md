# nuV30

A cycle-accurate FPGA recreation of the **NEC V30 (μPD70116)**, developed and
verified against a real chip running in the same FPGA, behind the same harness,
on the same clock.

The core is not written from a datasheet and then spot-checked. It is
regenerated from the part's own extracted microcode ROM, and every behavioural
claim in this repository is scored cell-for-cell against captures taken from a
socketed μPD70116C-8. Where the core and the silicon disagree, that is a work
item — not accepted residue.

**Status:** the core boots, runs, and is cycle-exact against silicon on the full
zero-wait golden wall (169,000/169,000 cases). On the last bitstream flashed to
the board it was exact on 97.2 % of a 3,838-seed whole-program random-wait
corpus, **measured in fabric against the chip in the same socket**. It does not
implement 8080 emulation mode, and the tree is currently one bitstream ahead of
the board. Section [Where the accuracy falls
short](#where-the-accuracy-falls-short) is the honest inventory.

---

## Contents

- [The hardware](#the-hardware)
- [The process](#the-process)
- [Repository layout](#repository-layout)
- [Sources and attribution](#sources-and-attribution)
- [Accuracy of the resulting core](#accuracy-of-the-resulting-core)
- [Where the accuracy falls short](#where-the-accuracy-falls-short)
- [Building and running](#building-and-running)
- [License](#license)

---

## The hardware

### The rig

The measurement rig is a **Terasic DE10-Nano** (Intel Cyclone V SE
`5CSEBA6U23I7`) running a MiSTer-framework Quartus project, with a real V30
socketed on a custom adapter board that plugs into both GPIO headers.

The single most important property of the rig is that **the socketed chip and
the FPGA core sit behind the identical observation path.** A configuration bit
(`use_core`) selects which one drives the bus; the memory, the wait-state
generator, the interrupt scheduler, the sampling logic and the capture buffer
are the same hardware either way. A core-vs-chip comparison is therefore not a
comparison of two instruments — it is the same instrument, twice.

### The adapter board (`de10_pcb/`, KiCad)

| Designator | Part | Purpose |
|---|---|---|
| U1 | DIP-40 socket | the μPD70116C-8 (V30) under test |
| U9 | PLCC-84 socket | V35 (μPD70330) position — schematic present, not part of the verified path |
| U3–U7, U10 | 6 × **74ALVC164245** | 16-bit level shifters, 3.3 V FPGA ↔ 5 V CPU, every signal both directions |
| U2, U8 | 2 × DE10-Nano GPIO header | both 2×20 headers are used; the pin budget needs them |
| — | 2 × SI2301CDS PMOS, 28 × 10 k, 18 × decoupling | rail switching, pull-ups, bypass |

Electrical constraints the design is built around (`docs/facts/pins_timing.md`,
from the 1991 NEC data book):

- **The installed part is not static.** μPD70116C-8: clock 2–8 MHz, `tCYK`
  125–500 ns. There is no single-stepping and no clock stretching — every
  capture is free-running. This is the constraint that shapes the whole
  measurement approach.
- The **clock input is special**: `VKH` min 3.9 V, `VKL` max 0.6 V, so the clock
  is driven at 5 V while everything else is shifted.
- **~5 ns propagation delay per level shifter, per direction**, budgeted into
  every AC number; an FPGA→CPU→FPGA round trip carries 10 ns.
- `AD[19:16]` are **input-only** at the FPGA (fixed-direction shifters); they
  carry PS3–PS0 status during T2–T4. Only `AD[15:0]` are driven.

The CPU runs in **maximum mode**. The harness decodes the max-mode status lines
directly rather than using an 8288.

### The harness FPGA core (`hdl/`)

```
sys_top                       (MiSTer framework)
 └── emu                      (nec_test.sv)
      └── system_large        (rtl/system_large.sv)   harness top
           ├── nec_bus        CPU clock/reset, T-state tracker, AD drive,
           │                  READY/wait-state generation, pin-event scheduler,
           │                  capture record assembly
           ├── test_mem       64 KB BRAM, byte lanes, mirrored across 1 MB
           ├── capture_buf    4096 × 64-bit trace ring
           └── v30_core       the recreated CPU (rtl/ucore/), selected by use_core
```

**One capture record per CPU clock, 64 bits wide.** CPU outputs are sampled
*twice* per CPU clock — address-phase signals at the falling CLK edge, data-phase
signals at the end of the cycle — because a single sample per clock cannot
distinguish an address phase from the status nibble that replaces it. The record
carries both AD samples, both BS samples, QS, RD/UBE/BUSLOCK, the driven
READY/INT/NMI/POLL/RESET levels, and the decoded T-state. Full field table in
`hdl/README.md`.

The buffer arms when the CPU leaves reset and stops when full (4096 cycles ≈ 1 ms
at 4 MHz), so reset release and first fetch are always in the trace.

Host control is over the **HPS lightweight bridge** at `0xFF200000` from MiSTer
Linux (`sw/v30ctl.py`): a 64 KB memory window, the capture buffer, and a small
register file. A JTAG path (In-System Memory Content Editor) exists as a
fallback needing no HPS.

---

## The process

### 1. Characterise the part on real silicon

Two measurement campaigns established what no documentation records: BIU queue
depth and refill threshold, fetch/EU bus arbitration, flush-to-refetch penalty,
wait-state interaction, odd-address fetch behaviour, self-modifying-code
distance; then a per-opcode timing database (306 measured forms), the undefined
flag behaviour proven bit-exact, and the undocumented `0F` space mapped.

Findings live in `docs/facts/` with **provenance on every claim** — each tagged
ROM / PLA / LAW / MEASURED / ASSUMPTION with its evidence and its falsifier.

### 2. Emit golden test suites from the chip

`sw/emit_suite.py` drives the socketed V30 and emits suites in the
**SingleStepTests V20 schema, extended for the V30's 16-bit bus** following the
8086 suite's precedent, plus extensions this project needed: pin events
(`evt`), static pin levels (`pins`), I/O read data (`iord`), and a
handler-address window close for vectored cases.

Every case carries initial state, final state, **and the full per-cycle bus
trace**. Suites are in `tests/v30/`.

### 3. Build a microcode-driven reference model

`sim/` is a C++ V30 whose execution unit is not hand-written: it is **driven
directly by the extracted microcode ROM** (`docs/V20BITS.TXT`, read at run time
and a declared input of the binary). The BIU, prefetch queue, loader, effective-
address unit, interrupt sampling and ALU flag circuits are *not* in the ROM —
the microcode analysis proved that — so those are hardware models informed by
the measured laws.

This answered the question the whole project turns on: **is the microcode we
hold sufficient to build a functionally correct EU?** It is. The model is exact
on 7,341,126 architectural cases.

### 4. Regenerate the RTL core from the same mechanism

`hdl/rtl/ucore/` is the shipping core (~11.4 k lines of SystemVerilog). It
carries the microcode as memory contents — `ucrom.hex` (1028 × 29) and
`ucdecode.hex` (8192 × 12), both in M10K block RAM in fabric — and renders the
same mechanisms the C++ model does, rather than fitting a state machine to
traces.

An earlier trace-fitted FSM core (`hdl/rtl/core/`) was **archived** in favour of
this one; it is retained and still builds, but nothing gates on it.

### 5. Score it, in four places, against the same silicon

| instrument | what it is |
|---|---|
| `check_core` | the bare core in Verilator vs the golden suites |
| `ulockstep` | the RTL core vs the C++ model, cycle for cycle |
| `tb_sys` | the **Verilated `system_large`** — the core inside the real integration, loaded and armed through the AXI bridge exactly as the ARM does it |
| fabric | the core in the FPGA, scored against the chip in the same socket |

These do not always agree, and the disagreements are themselves findings. The
standing rule, measured over 1,654 cells: **where `tb_v30_core` and `tb_sys`
disagree, fabric sides with `tb_sys`.**

### The discipline

This repository is run as a measurement project, and the process rules are
load-bearing:

- **Silicon match is the only correctness bar.** Matching the model is not
  acceptable. A divergence from silicon is a work item regardless of whether
  the model shares it.
- **Pre-registration.** Predictions and numeric bars are committed *before* the
  build or the board contact they govern. A missed bar is reported as missed,
  never restated.
- **Ratchets are monotone.** No figure is quietly re-scored downward.
- **Receipts.** Every testbench binary on a gate's path names the bytes it was
  built from, and the gate refuses to run if the declared inputs no longer hash
  to the tree (`sw/artifact.py`).
- **A four-register ledger** — `INV` (invalidation: a named rig defect), `SUP`
  (supersession), `EXC` (per-seed exclusion), `ERR` (a defective derived
  column). Every drop from a scored population is printed, never silent
  (`docs/notes/invalidation_ledger.md`).
- **Simplicity.** This is 1980s silicon; nothing on the die is wasted. A large
  fitted table or a per-opcode special case is treated as a signal of
  misunderstanding, not as a deliverable.

---

## Repository layout

| path | what |
|---|---|
| `de10_pcb/` | KiCad adapter board — schematic, PCB, fabrication outputs |
| `hdl/` | Quartus project: MiSTer harness, `rtl/ucore/` (the core), `rtl/core/` (archived FSM core), `tb/` (Verilator benches) |
| `sim/` | the microcode-driven C++ reference model (`v30sim`) |
| `sw/` | capture tools, suite emitter, scorers, and every standing gate |
| `tests/v30/` | golden suites captured from silicon |
| `docs/raw/`, `docs/converted/` | vendor manuals (scans + text) |
| `docs/facts/` | structured measured facts, each with provenance and a falsifier |
| `docs/notes/` | campaign ledgers, pre-registrations, results, verdicts |
| `docs/V20BITS.TXT`, `V20UC.TXT`, `V20UCDIS.PAS`, `pla_*.txt` | third-party microcode/PLA dumps — see attribution below |

Two documents carry the authoritative state: `docs/notes/standing_gates.md`
(every gate and its current figure) and `ROADMAP.md` (goal and campaign order).
`CLAUDE.md` is the working brief.

---

## Sources and attribution

This project stands on other people's published work. The following are not
incidental references — the project would not exist without them.

### The microcode ROM and PLA extraction

`docs/V20BITS.TXT` (1028 × 29-bit micro-words, 257 match patterns),
`docs/V20UC.TXT` (its 1,285-line disassembly), `docs/V20UCDIS.PAS` (the
normative encoding spec, as an executable Pascal disassembler),
`docs/v20_microcode_04.xlsx`, and the PLA transcriptions
(`docs/pla_2.txt`, `pla_3.txt`, `pla3_outputs.txt`, `pla4.txt`) with their die
photographs (`docs/pla_1.jpg` … `pla_5.jpg`) are **third-party die
transcriptions**, not this project's work.

The public origin of that extraction is the VCFed thread
[**"The NEC V20 Microcode ROM"**](https://forum.vcfed.org/index.php?threads/the-nec-v20-microcode-rom.1254770/):

- **GloriousCow** — started the thread, extracted the
  microcode bit array from the ROM photographs using a convolutional neural
  network, and published the corrected word extraction and the
  field-decoding spreadsheet.
- **InfoSecDJ** — decap and high-resolution die imaging, through their
  commissioning service at [siliconpr0n.org](https://siliconpr0n.org).
- **dreNorteR** — opcode-mapping analysis and the initial decoding of the
  activation PLA and the microcode fields.

Additional die-level and functional context:

- **dev-zzo**, [*"NEC V20 PLA"*](https://dev-zzo.github.io/blarg/2025/10/06/nec-v20-pla.html)
  (2025-10-06) — the electrical analysis of the nine on-die PLA structures.
  Used for implementation context only; it assigns no functional meaning and
  publishes no dimension table.
- **Ken Shirriff**, [*"The Group Decode ROM in the Intel 8086"*](https://www.righto.com/2023/05/8086-processor-group-decode-rom.html) —
  used as a **hypothesis source only** for `pla_3`'s column semantics. Ten of
  `pla_3`'s fourteen columns are recognisably the same signals, but every V20
  column is proven against V20 metadata, never asserted by analogy. Also
  [*"Silicon reverse engineering: the 8086 flag circuitry"*](http://www.righto.com/2023/02/silicon-reverse-engineering-intel-8086.html)
  and [*"Reverse-engineering the 8086's ALU"*](http://www.righto.com/2020/08/reverse-engineering-8086s.html),
  used as structural analogy for the flag-race work.

### The test-suite format and the V20 golden suite

- **SingleStepTests / V20** — [github.com/SingleStepTests/v20](https://github.com/SingleStepTests/v20),
  by **Daniel Balsom**. Generated with the Arduino8088 v1.1 hardware interface
  and the MartyPC emulator, from a *"NEC JAPAN V20 8902NX D70108C-8 1984"* in
  maximum mode with an Intel 8288. **Version 1.0.2/1.0.3, `syntax_version` 2.**

  This project uses it two ways: its **schema** is the format every suite here
  is emitted in (extended for the V30's 16-bit bus per the 8086 suite's
  precedent), and the **suite itself** is vendored at `tests/v30/v20suite/` and
  run as a 3,125,000-case functional gate. Format notes and the full schema
  analysis are in `docs/notes/singlesteptests_v20.md`; the vendored
  `metadata.toml` retains its upstream authorship.

- **SingleStepTests / 8086** — [github.com/SingleStepTests/8086](https://github.com/SingleStepTests/8086) —
  the precedent for extending the schema to a 16-bit bus.

- **arduinoX86 / Arduino8088** — [github.com/dbalsom/arduinox86](https://github.com/dbalsom/arduinox86),
  by **Daniel Balsom**. Its register load/store stub methodology — how you get a
  CPU with no debug port into and out of a known architectural state — is the
  direct ancestor of this project's state injection/extraction. Analysed in
  `docs/notes/arduinox86.md`; background at
  [martypc.blogspot.com](https://martypc.blogspot.com/2023/06/hardware-validating-emulator.html).

- **VirtualXT / pi8088** — [github.com/andreas-jonsson/virtualxt](https://github.com/andreas-jonsson/virtualxt/tree/develop/tools/validator/pi8088) —
  prior art for hardware CPU validation.

> **Note.** The upstream V20 suite is a **μPD70108** (V20, 8-bit bus) suite.
> This project targets the **μPD70116** (V30, 16-bit bus). Where the two parts
> differ on the bus, the V20 suite's cycle traces do not apply and only its
> architectural results are used.

### Emulation and documentation references

- **MAME** — [github.com/mamedev/mame](https://github.com/mamedev/mame),
  `src/devices/cpu/nec` — mined as a behavioural reference
  (`docs/notes/mame_necv.md`).
- **MartyPC** — [github.com/dbalsom/martypc](https://github.com/dbalsom/martypc) —
  the emulator behind the V20 suite's generation.
- **bitsavers.org** — the vendor documentation in `docs/raw/`: the 1991 NEC
  16-bit V-Series Microprocessor Data Book, the V20/V30 User's Manual (Oct 86),
  the 1997 16-bit V-Series User's Manual, and Intel's 8086 Family User's Manual
  (Oct 79) for the max-mode bus protocol and queue-status semantics.
- **MiSTer** — the DE10-Nano framework (`hdl/sys/`) this harness is built in.

---

## Accuracy of the resulting core

Every figure below is a **silicon-match** figure: the reference is a capture
from the socketed μPD70116C-8, not the model. Figures are as of `master`
@ `c59d205479`; `docs/notes/standing_gates.md` is authoritative and current.

### Architectural (functional) correctness

| gate | result |
|---|---|
| `ucsim_check` — v0.1 + v0.2 + v0.3 + v20suite + mod3_illegal | **7,341,126 / 7,341,126 exact** |
| microcode disassembly vs the published golden | byte-exact, 1,285 rows |
| PLA identification (`pla3_check`) | 21 checks, 0 contradictions |


### The RTL core, cycle-exact vs silicon (Verilator)

| gate | result |
|---|---|
| all opcodes, zero waits, cycles **and** architecture | **169,000 / 169,000** (348 forms) |
| wait-state suites `v0.1-w1` / `-w3` | 1,200 / 1,200 each |
| the four interrupt (`evt`) cells | 200 / 1,200 / 200 / 1,200 |
| lockstep vs the C++ model, all scenarios, waits 0–3 | **17,350 / 17,350** |
| `v0.3` block-I/O forms (INM/OUTM, 6C–6F + REP/segment variants) | 229,999 / 229,999 |
| directed boundary suites (`f4a_boundary`, `f0lock_tranche`) | 160/160, 400/400 |
| HLT delay sweeps (4 suites, waits 0–3) | **279 / 283** |
| S16 directed display walk (`tb_v30_core`) | 1,320 / 1,371 |
| S16 directed display walk (Verilated integration, and in fabric) | **1,347 / 1,371** |
| whole-program random-wait fuzz, registered bank | **1,564 / 1,702** |
| … same bank, event-replay column | 937 / 1,008 |
| … combined | **2,501 / 2,710** |
| the b2 victory tranche | **182 / 188** (the C++ model scores 161/188) |

### In fabric — the flashed bitstream (FLASH #21, 2026-08-14)

The core in the FPGA, scored against the chip in the same socket, on the same
harness.

| measurement | result |
|---|---|
| fuzz-v2 whole-program corpus | **107 failures of 3,838 seeds = 97.2 % exact** |
| per-cycle rows across that corpus | **99.0844 % of 11,330,674 compared rows** |
| boot A/B, three legs (chip-vs-golden, core-vs-chip, core-vs-golden) | MATCH 800 × 3 |
| HLT sweeps in fabric | 279 / 283 — the offline column exactly, 0 disagreements |
| S16 walk in fabric | 1,347 / 1,371 — 0 PASS/FAIL disagreements and 0 differing coordinates over all 1,371 |
| the microcode in block RAM, verified word-for-word on the flashed build | 8192 × 12 and 1028 × 29, every word |

The fabric and offline columns agreeing *cell for cell, coordinate for
coordinate* is the load-bearing result there: it means the remaining
divergences are diagnosable offline and are not artefacts of the board.

### Cost and timing

Measured on the current tree (5-seed CONTROL sweep, 2026-08-20):

| | |
|---|---|
| device | Cyclone V SE `5CSEBA6U23I7` (DE10-Nano) |
| logic | **10,281–10,334 ALMs of 41,910 — 25 %** across the five seeds |
| Fmax, control | **worst-of-5 = 38.25 MHz** (median 40.08, best 40.43, spread 2.18) |
| Fmax, retention | 39.63 MHz — **a single draw, not promotion-grade** |
| worst setup slack | +6.749 to +7.232 ns |
| timing closure | PASS on every seed, **TNS 0.000 setup and hold on every domain**, 0 errors, 0 latches, 0 inferred dividers |

The target is 32 MHz; the harness divides it down to a 4 MHz CPU clock. The
quotable figure is the **worst-of-N**, never the best draw — see gap #8.

---

## Building and running

```sh
# The C++ reference model
python3 sw/simbin.py --build
python3 sw/simbin.py --disasm          # ROM disassembly gate (1,285 rows)

# The RTL core in Verilator
python3 sw/check_core.py --build --core ucore
python3 sw/check_core.py --opcodes all --cases 0        # 169,000 cases

# Cross-check RTL against the model
python3 sw/ulockstep.py --golden all --cases 50         # 17,350

# Synthesis receipt (required before any RTL landing or flash)
python3 sw/quartus_gate.py                              # add --retention for that build

# Always-on structural lints
python3 sw/r7_lint.py
python3 sw/ss_lint.py
python3 sw/test_artifact.py
```

`docs/notes/standing_gates.md` is the full gate set with each gate's current
figure and its falsifier. **Board work has its own rules** — single-writer check
first, socket only, pre-register predictions and commit before first board
contact, verify and return the board to idle afterwards. They are in `CLAUDE.md`
and they are not optional.

---

## License

GPL v2 (`LICENSE`), consistent with the MiSTer framework this harness is built
in.

The third-party microcode and PLA dumps in `docs/` are **not** this project's
work and are not covered by that grant; see
[Sources and attribution](#sources-and-attribution) and
`docs/facts/pla_model.md`. The vendored SingleStepTests V20 suite at
`tests/v30/v20suite/` retains its upstream authorship and terms. Vendor
documentation in `docs/raw/` is reproduced from bitsavers.org for reference.
