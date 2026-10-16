# Actual-core RQ/AK chain integration — preregistration

Baseline: `81d9aa14`, branch `feature/rqak-pulse-interface`, existing PR #1
to `rtzor/nuV30`, base `master`. Parent must commit this preregistration before
the new testbench or acceptance runs. This milestone changes verification and
its runner only: no frontend, level-adapter, ucore, production QIP or stable
PCS86 integration changes. No private BIOS/media or FPGA contact is authorized.

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted.
Complex or confusing observed behavior is likely simple systems interacting
in ways not yet understood. A large fitted table, a many-cased rule, or a
per-opcode special case is a signal of misunderstanding, not a deliverable.

## Scope and evidence boundary

The new bench instantiates the real chain, not a replay of separate tests:

```text
external peer + frontend low-drive -> resolved RQ/AK inputs
frontend REQUEST -> level adapter -> INTERNAL_GRANT -> frontend
ucore BUS_EXCLUDE -> adapter EXCLUDE
ucore SS_BUS_QUIET -> adapter CORE_QUIET
adapter CORE_CE -> ucore CE
frontend EXTERNAL_GRANT -> peer ownership permission
adapter CORE_BUS_ENABLE -> test bus isolation
```

Compile the unmodified ucore with `V30_BUS_OWNERSHIP` and inert verification
backdoor initialization. Use its demultiplexed data/address interface; no
multiplexed physical-pin timing claim follows. CLK/CE remain available to the
frontend while CPU CE is frozen. Synthetic public program/data bytes and
known register initialization are the only inputs. SS writes remain disabled.

The chain still pauses the whole CPU. This is FPGA integration validation of
the closed pulse and ownership contracts, not native BIU yield/resume, native
EU progress during ownership, a bounded hardware grant latency or NEC physical
edge verification. Third-pulse return semantics and the return gap retain
their engineering interpretation. Native CPU correctness ultimately requires
silicon evidence; twin-core equality and literal memory checks here do not
replace that bar.

## Test harness and memory custody

Two actual cores provide the no-request control: raw CE versus the complete
frontend/adapter chain, with identical initial public memory and registers.
Compare public address/data/status/control bus, QS and architectural debug
registers. Their memory models use identical bus-phase and wait rules.

Reuse the corrected public BS/READY phase model. Address comes from the
announcement; UBE is captured on actual T1, independently corroborated by
registered BIU state. Write data is sampled at physical write completion,
preserving the existing paired-data forwarding path. An odd first cycle writes
only its selected upper lane; its even second cycle must preserve neighboring
bytes. Initial register loading is permitted; forcing internal execution,
queue or ownership state to obtain an outcome is prohibited.

Count a CPU transaction commit only on its eligible CORE_CE edge and correct
bus completion. While CORE_BUS_ENABLE is false, no CPU transaction may commit
and CPU memory drive must be isolated. A peer write is permitted only when its
EXTERNAL_GRANT bit is set, CORE_BUS_ENABLE is false and CPU CE is gated.
No peer writes during internal grant alone or ACK. Reset independently revokes
peer drive permission; it is not conditional on stale grant state.

## Compact registered matrix

Four protected programs crossed with wait settings 0, 1 and 3 give **12
case/wait combinations**. Each initializes afresh, executes actual bytes and
uses real BUS_EXCLUDE and SS_BUS_QUIET. Representative programs may use the
previous guard bench's established workloads without modifying instruction
scheduling. Each no-request comparison covers at least **200 eligible CPU
clocks**; the request run begins from the same initial public state.

| Protected program | Literal operation evidence | Request/grant requirement |
|---|---|---|
| `F0 INC word [0200]` | Initial 0001 becomes 0002; at least one physical write | Request while genuine decoded LOCK is active; no internal/external grant before final write |
| `F0 INC word [0201]` | Initial 0001 becomes 0002; at least two physical writes; A5/5A neighbors at 0200/0203 unchanged | Same exclusion across both physical halves, including waits |
| `F0 F3 MOVSW`, CX=3 | Destination words 1111/2222/3333, CX=0; at least three physical writes | No internal/external grant before the third write/final iteration |
| Maskable IRQ into a public handler | Exactly two INTA cycles; vector/frame/handler execution reaches a known terminal state | Request during real entry exclusion; no internal/external grant before both acknowledgements; exclusion covers their gap |

These programs may terminate with HALT. They need not all perform the DMA
readback scenario below. Quiet=false throughout an operation is permissible;
do not invent a quiet clock to satisfy coverage. Requests must remain pending
while real exclusion is active, regardless of whether a quiet opportunity
appears. Memory/acknowledgement results must be checked directly, not merely
by agreement between two cores using the same model.

## READY, queue, priority and DMA/resume scenario

One additional actual-core scenario gives **13 total integration profiles**.
Use a public loop containing reads from 0600, an observable store to 0602 and
a native DIV by initialized CX=1 so prefetch can naturally accumulate:

```text
MOV AX,[0600]; MOV [0602],AX; DIV CX; JMP loop
```

Initial DS/CS are zero, CX=1, DX=0 and memory[0600]=1111. The exact byte image,
initial register values and addresses must be stated in the result/receipt.
DIV is a workload, not a timing adjustment for the frontend.

Once a real MEMR of 0600 is active, hold READY low. Send a channel-1 request
pulse, return its line high, then a channel-0 request pulse and high. Both must
be retained before READY is released and before internal acquisition, without
forcing CORE_QUIET. Channel 0 must subsequently acquire first; channel 1
remains queued and cannot preempt it.

The READY bar is **at least 16 eligible CORE_CE clocks in actual Tw** with
READY low, both input request pulses already high and REQUEST retained.
Use registered BIU `r_ts==4` only to corroborate/count actual Tw against the
source's enum. Merely spending 16 clocks after lowering READY is insufficient
because T2/T3 may precede Tw. During those counted Tw clocks, no internal grant,
ACK or external grant may occur. Releasing READY must drain real bus activity
and eventually permit ownership at naturally reached quiet state.

At first internal acquisition require a nonempty prefetch queue: **q_count>=1**.
Prefer/report a naturally full six-byte queue, but six bytes are not the
acceptance bar and no queue state may be injected to manufacture it. If the
selected workload does not meet the nonempty bar, report failure and investigate
the public program/harness before modifying any requirement or CPU timing.

Snapshot architectural registers, all **six queue storage bytes**, registered
queue count/head/fetch pointer, EU execution state/microcode page/opcode/location
and loop counter, BIU running/T-state, and public bus outputs at acquisition.
Check preservation for **at least 32 CLK edges**, and continue checking through
ACK, external ownership, accepted return and its HIGH-plus-two-CE gap until
the actual CPU resumes. Assert explicitly that neither EU execution/microcode/
loop phase nor BIU transaction phase advances while CPU is isolated, alongside
the no-commit check. The adapter release edge itself remains a frozen CPU edge:
judge progression using the CPU enable sampled at the clock edge, not an enable
that becomes high afterward. The external peer deliberately holds ownership long
enough to meet the 32-clock bar. No CPU transaction commit is permitted while
isolated. Frontend/adapter phase counters are allowed to advance.

After channel-0 ACK ends, peer 0 writes 3C5A to memory[0600], only under the
permission/isolation conditions above. After valid return and queued channel-1
ACK, peer 1 writes **6A35** to the same address under its own permission.
The CPU remains frozen across both owners and their turnarounds. No peer may
write on the other channel's grant or during ACK.

After the last return, the loop must perform **at least one post-resume MEMR
of 0600**, and produce literal 6A35 in its architectural/result path and an
observable post-resume store of 6A35 to 0602. Earlier reads of 0600 are allowed:
the test does not require that the first such read was delayed until ownership.
That avoids making quiet scheduling an artificial instruction-timing constraint.
Post-resume transaction counters and result checks distinguish a real fresh
read/store from stale pre-ownership register or memory contents.

## Numeric bars, watchdogs and artifacts

Acceptance requires all **12 protected case/wait combinations plus the one
READY/DMA profile** to PASS, no unexpected protocol diagnostics, and the
200-clock no-request, 16-Tw-clock, nonempty-queue, 32-clock snapshot and
post-resume read/store bars above. Existing standalone frontend **66 distinct
checks**, level-controller **26 checks**, default-core integration and native
guard **18 case/wait combinations plus optional-port absence** remain regression
bars; label those separate from this newly instantiated chain.

Preregistered watchdogs for the directed harness:

- Reach program/request or targeted real MEMR: **4096 eligible CPU clocks**.
- Reach actual Tw after lowering READY: **128 eligible CPU clocks**, followed
  by the counted 16-Tw hold; failure is not silently called a wait test.
- Acknowledge/acquire after directed exclusion/READY release: **8192 eligible
  controller CE intervals**; this is a test watchdog, not hardware latency.
- Complete return/queued-owner transfer after a valid source return: **128
  eligible controller CE intervals** per phase, using the unchanged frontend.
- Observe post-resume fresh read and literal result store: **4096 eligible
  CPU clocks**. Protected program terminal/result checks use the same bound.

`sw/bus_ownership_gate.py --rqak-core` will be a new mutually exclusive mode.
Every fresh receipt must hash the new bench, runner, frontend, level adapter,
all relevant ucore SV/SVH and runtime HEX inputs, binary and full logs. Build
artifacts stay under this thread's work directory. Preserve failed attempts
and explain corrected harness assumptions in a later results document.
Parent commits this preregistration before any new testbench or acceptance run.
No synthesis, native pin timing, hardware programming or production integration
claim follows from a simulation PASS.
