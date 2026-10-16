# RQ/AK PR1 adaptation to the 8080 master

This preregisters SOURCE and future validation before the first execution.
It updates the optional FPGA ownership utility to master
`182ec09622bdef6cbc3b594a89a59c6c0e0026b1`; earlier campaign notes remain
historical. No NEC RQ/AK waveform, silicon, clock-rate or board claim follows.

## Mechanism and profile

`BUS_EXCLUDE` is independent of `BUSLOCK_N`. Only the LOCK-prefix term is
native-mode-qualified. The interrupt decision and active internal page are
protected even while a forced native IRQ preserves an interrupted 8080 MD:

```text
(!mode8080 && lock_pfx) || st == S_IRQ_D ||
(upc_page == 7 && st >= S_ROW && st <= S_INSTR_END)
```

No execution register, save-state slot, decoder table or opcode law changes.
The merge retains all four staged-LOCK EU connections and the conditional
`BUSLOCK_N` implementation. The save-state lint expectation follows master's
version `0x90`, count 232 and tag `0x90E8`; the FSM's version `0x03` is unchanged.
There is no cross-version state-file compatibility claim.

The directed profile uses de-multiplexed bus ports, `V30_BUS_OWNERSHIP` and
`V30_BACKDOOR`, with staged LOCK disabled. This adapter freezes the entire core;
it does not satisfy staged LOCK's uninterrupted five-CE profile. The existing
staged/multiplexed profile rejection remains. Other controls require external
bus isolation, retained interrupt events and peer withdrawal on RESET, as in
the original ownership contract. No new macro combination is certified here.

## Fixed directed programs

`tb_rqak_8080_irq.sv` contains two programs, each reset independently. Initial
AX is `1234`, native SP `0800`, CS/DS/ES/SS/IP zero and defined flags `0202`.
The architectural native PSW is `F202`. No expected address, return PC, frame
word or marker value is obtained from a DUT register or observed result.

* Native control: `HLT` at `0000`, sixteen native NOPs, `MOV [0600],AX` at
  `0011`, then HLT. IRQ 20 saves IP `0001`, CS `0000`, PSW `F202` at
  `07FA/07FC/07FE`. The handler at `0000:0200` is IRET. Final IP is `0015`.
* 8080 case: `BRKEM 60` at `0000` (`0F FF 60`), then `MOV [0600],AX` and
  native HLT. Vector 60 at `0180/0182` is `0000:0100`. The emulation program
  is HLT, sixteen 8080 NOPs, RETEM (`ED FD`) at `0111`. BRKEM saves
  `0003/0000/F202` at `07FA/07FC/07FE`. IRQ 20 saves `0101/0000/7202` at
  `07F4/07F6/07F8`, retaining emulation MD in the frame. IRET restores that
  frame; RETEM restores the original native frame. Final native IP is `0007`.

Both IRQ vectors use the literal IVT words `0200/0000` at `0080/0082`.
INT is asserted only after the initial HLT is reached and withdrawn after
exactly two completed INTA transactions. The HLT state is a stimulus cut,
not the source of an expected PC. Every data read is matched to the exact
ordered IVT/IRET/RETEM address and word; every write is matched to an ordered
frame word or the final marker `0600=1234`. Native has five reads/four writes;
8080 has ten reads/seven writes. Code fetches are separate bus transactions.
Full final native PSW, SP, CS and AX are checked along with the fixed IP.

## Frozen matrix and nonvacuity

The complete matrix is 18 profiles: two programs × three request positions ×
READY waits `{0,1,3}`. One synchronous channel-0 request pulse is placed at:

1. `S_IRQ_D`;
2. the active page-7 entry;
3. the public idle gap after the first completed INTA and before the second.

Private state identifies stimulus/coverage cuts only. The frame and final
architectural oracles remain literal. The 8080 decision must actually retain
MD=8080, and the native control must not. Each profile must observe the decision,
active entry and INTA gap, with exclusion asserted throughout the relevant
interval and no grant there. No first-success sampling or skipped profiles.

After entry, the queued request must receive an external grant, remain owned
for at least 32 clocks with register/public-bus snapshots unchanged, return by
the existing pulse protocol and reach the exact frame/marker endpoint. Bounds
are 4096 ticks to initial HLT and each request cut, 8192 to grant/endpoint and
128 to ownership release. All 18 must pass; failures remain retained and are
not repaired by changing literals or time limits after observation.

Future command, requiring separate review and runtime authority:

```sh
python sw/bus_ownership_gate.py --compiler clang --rqak-8080-irq --work ../rq1-evidence
```

The gate remains a build-and-run command and must not be used as a SOURCE-only
check. Existing warning options are unchanged; no new suppression is added.
Fresh compiler/DUT receipts are required before any result can be quoted.

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted.
Complex or confusing observed behavior is likely simple systems interacting
in ways not yet understood. A large fitted table, a many-cased rule, or a
per-opcode special case is a signal of misunderstanding, not a deliverable.
