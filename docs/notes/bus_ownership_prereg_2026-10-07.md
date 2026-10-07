# Generic bus ownership adapter — scope and registered checks

Base: `ed50fb4e5222fb5567c01ff16d34cd8a08f584e2`, fork `rtzor/nuV30`,
branch `feature/bus-ownership-contract`. Independent clone owned by this chat.
No changes to the stable PCS86 integration, private reference copies or FPGA.

## Evidence and design decision

**Documented (NEC):** small-scale/minimum mode uses HLDRQ/HLDAK;
large-scale/maximum mode uses bidirectional RQ/AK0 and RQ/AK1, with channel 0
priority. The maximum-mode timing diagram shows request, acknowledge and release
pulses. These are bus ownership protocols, not instructions. Sources: Oct86
User's Manual, chapter 1 pin descriptions and BUSLOCK instruction; 1991 Data
Book, V30 pin descriptions and Hold Request/Acknowledge Timing [Large Scale].
Local text anchors: Oct86 lines 1752–1768, 29428–29440; 1991 lines
21933–22000 and 23207–23230. The originals remain under `docs/raw/`.

**Observed in source:** the core is maximum-mode. Its BUSLOCK_N output is
constant 1 (`v30_core.sv:508–510`), although the EU decodes and retains a LOCK
prefix (`v30u_eu_step.svh:91`, cleared at instruction completion). Consequently
BUSLOCK_N cannot currently supply a valid exclusion signal to an arbiter.
SS_BUS_QUIET requires no running cycle, no announced cycle, no queued EU access
and no pending HALT (`v30u_biu.sv:926`).

**Measured by upstream, not remeasured here:** `docs/facts/biu_model.md`,
BUSLOCK section, describes socket measurements of three locked RMW forms:
continuous exclusion spanning read, intervening prefetch and write. That file's
implementation paragraph describes the archived FSM, not the current ucore.
It explicitly says hold requests under LOCK were not exercised.

**Engineering choice, not a silicon fact:** implement an opt-in external,
two-channel level request/grant controller. Pause the whole core at
SS_BUS_QUIET, including CE_HALF in a multiplexed integration, and expose a bus
ownership enable for an external mux. Gate CE on the acquisition edge itself
so an EU request cannot be posted on the same edge as a grant. Complete all
in-flight work before acquisition; leave READY and instruction timing alone.
No existing core ports, state, tables or production integration change.

This deliberately narrower adapter does not implement the physical RQ/AK
pulse protocol, minimum-mode pins, or native EU progress from the queue while
DMA owns the bus. It does not establish silicon-match correctness or fix a
PCS86 failure. PCS86 DOS/FDC/XTA reads currently pass using external arbitration
(user-provided observation); that stable system is outside this session.

## Caller obligations and limitations

- Requests, exclusion and quiet must be synchronous and stable at the sampling
  edge. Hold a request until grant, then deassert it to release ownership.
- Supply a genuine exclusion guard covering atomic/LOCK operations and the
  interrupt acknowledge pair. **Do not connect the current BUSLOCK_N output as
  the sole guard.** Native exclusion remains a separate implementation task.
- Mux or isolate all shared data, address and control outputs before allowing
  another master to drive. Gating enables alone does not disconnect bus drivers.
- No save-state writes, backdoor injection or independent mutation of the core
  during arbitration. Adapter ownership is external state and must also be
  restored consistently if save states are supported later.
- Preserve interrupts/events externally: a pulse entirely within the paused
  interval is not sampled by the stopped core. This adapter is not an event latch.
- No grant-latency or fairness bound: continuous queued activity, a pending HALT
  or permanent exclusion may prevent grant. Channel 0 wins simultaneous eligible
  requests but cannot preempt an existing owner. RESET cancels grants and passes
  the core enables so the core receives reset; the system must reset other masters
  consistently before allowing the CPU to drive again.

## Checks registered before implementation acceptance

Controller simulation must demonstrate: no acquisition without CE, no grant
while busy or excluded, cancellation before quiet, acquisition-edge CE blocking,
both enable phases blocked during ownership, one-hot grants, channel-0 priority,
no preemption, release/resume, and RESET priority with pending simultaneous
requests. Directed drain stimuli must exercise wait and prefetch backlog.

Actual ucore simulation must demonstrate execution/prefetch before acquisition,
no grant while a waited cycle is active, no running or announced cycle at grant,
state preservation while paused, and resumption after release. A no-request
control must retain the unadapted core's behavior. Each executed binary must
have an input/binary SHA-256 receipt from a fresh build.

Results must distinguish controller simulation, core integration simulation,
synthesis and hardware. Neither simulation proves native pin timing. The new
module is not in any production QIP or bitstream. No synthesis/hardware result
will be claimed without an actual run. Any PR will remain a draft integration
utility, not RTL promotion of the native core under CLAUDE.md's Quartus gate.
