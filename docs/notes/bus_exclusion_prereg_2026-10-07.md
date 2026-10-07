# Conservative native-state bus exclusion — preregistration

Branch `feature/bus-exclusion-guard`, based on adapter branch tip `ce82aa7b`
and original stable fork base `ed50fb4e`. Intended PR destination:
`rtzor/nuV30`, base `master`. Upload troubleshooting is deferred by the user.

## Problem and bounded change

The first ownership adapter requires a valid EXCLUDE guard. The ucore's
constant-inactive BUSLOCK_N cannot supply it. Existing decoded LOCK state can
instead provide an FPGA-only conservative exclusion guard, without inventing
physical pin timing or changing instruction scheduling.

Proposed output: BUS_EXCLUDE, only when V30_BUS_OWNERSHIP is defined on the
ucore top. Internal EU publication uses existing registers only:

```
!mode8080 && (lock_pfx || st == S_IRQ_D ||
             (upc_page == 7 && st >= S_ROW && st <= S_INSTR_END))
```

This is an engineering contract, not a measured native BUSLOCK waveform.
LOCK protects from prefix decode through normal completion; repeated operations
retain the latch. A LOCK-prefixed HALT retains it while halted. The dispatch
and page-7 active microsequence term deliberately excludes more than the INTA
pair (including NMI/trap/other internal sequences). Phase qualification prevents
stale microcode page/opcode from blocking subsequent loader/NOP execution.

The guard has no new register, save-state field or instruction-timing input.
It does not suppress prefetch. It is suitable only for the conservative adapter
which freezes on SS_BUS_QUIET. Its scope is native execution: 8080 execution
remains incomplete and is not declared protected. BUSLOCK_N is unchanged.

## Evidence

- NEC documents exclusion for a locked instruction/repeated block and the
  interrupt acknowledge sequence; minimum/maximum ownership protocols remain
  distinct. See the first bus-ownership contract's NEC sources.
- Source: v30u_eu_step.svh sets lock_pfx at prefix decode and clears it at normal
  instruction completion or interrupt dispatch. HALT bypasses that completion.
  EU microsequence states S_ROW..S_INSTR_END are contiguous.
- Upstream RMW measurements in biu_model.md do not certify this guard's timing,
  nor all waited/REP/HALT cases. Archived FSM release-at-first-write-T4 is not
  reusable for split writes or multi-iteration instructions.
- The timed C++ simulator has no independent BUSLOCK waveform oracle; its
  default lock_n field cannot be used to validate a newly implemented pin.

## Registered simulation checks

1. Executed locked and unlocked RMW programs, odd-address split word writes,
   repeated strings with multiple iterations, and waits 0/1/3. The guard must
   retain exclusion across each operation, while ordinary prefetch still runs.
2. LOCK+HALT retains exclusion; wake/reset releases as the existing native state
   changes. Requests while excluded cannot acquire even on a quiet BIU boundary.
3. A maskable interrupt must produce both INTA cycles; exclusion stays high in
   their intervening gap. NOP and prefix-only successors must demonstrate that
   stale page-7 decode does not leave exclusion stuck.
4. Without requests, adapted and raw cores must match bus/QS/architectural
   register traces. No instruction timing is adjusted to make this test pass.
5. The optional port must elaborate in the opt-in configuration and be absent
   in the default configuration. Existing save-state and structural lints must
   remain unchanged. Fresh binaries must have input/output/log hash receipts.

These tests establish supplied native-state guard semantics, not NEC RQ/AK pin
timing. A native yield/resume implementation and full maximum-mode pulse adapter
remain later work. External event retention and synchronous bus isolation are
still required by the first adapter's contract.

## Synthesis boundary

Installed Quartus is 22.1std.2; the inherited G6 scripts expect Linux17.1 and
sys.qip has no pll_q22.qip. Investigate isolated scratch compatibility from the
clone's public inputs, without touching private references or production
integration. A default CONTROL build alone would not establish synthesis of an
opt-in guard that is absent/pruned. Any guard synthesis result must prove its
port and logic are actually present. If G6 cannot be met, preserve the candidate
as unpromoted, record the exact limitation, and do not assert synthesis or
hardware correctness. No FPGA contact is authorized.
