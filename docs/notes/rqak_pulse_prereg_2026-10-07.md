# Conservative maximum-mode pulse frontend — preregistration

Branch: `feature/rqak-pulse-interface`, from `69580745` (opt-in native-state
exclusion guard). Intended PR: `rtzor/nuV30`, base `master`. Upload remains
deferred. This document must be committed before frontend RTL, its testbench
or acceptance simulations are written/run. Existing core and production
integration remain unchanged; no private inputs or FPGA contact are authorized.

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted.
Complex or confusing observed behavior is likely simple systems interacting
in ways not yet understood. A large fitted table, a many-cased rule, or a
per-opcode special case is a signal of misunderstanding, not a deliverable.

## Evidence and boundary

NEC's maximum-mode RQ/AK interface uses two bidirectional active-low lines.
Its diagram shows a requester input pulse, CPU acknowledge pulse and third
requester input pulse. The documented CPU
acknowledge lasts one tCYK and bus-driver ownership transfers at its **end**.
The diagram requires the requester to separate its next pulse on the same
line from that end by at least two CPU intervals. Source: 1991 NEC data book,
V30 PDF page 106 (printed page 3b), figure 83IH-5509B under **Timing Waveforms
(cont)**; converted-text anchors 23207–23230 and pin-description anchors
21992–22000. The vendor publication is also identified by
[the bus contract](bus_ownership_prereg_2026-10-07.md).

Interpreting the third requester pulse as return/release is the protocol
interpretation adopted by this engineering contract; the reviewed NEC diagram
labels its direction rather than stating that role in prose. That interpretation
must not be reported as an additional directly documented NEC timing fact or
filled in with Intel 8086 behavior presented as NEC evidence.

This candidate is a **standalone FPGA pulse frontend** for the existing
whole-core pause utility. It does not claim NEC physical edge alignment,
first-T4 grant timing, native EU progress from prefetch, minimum-mode pins,
or a bounded grant delay. `CE` defines an abstract CPU interval; physical pad
electrical behavior, sampling alignment and synchronization remain integration
responsibilities. Native BIU yield/resume is a separate pending milestone.

The BIU has separate queued, announced and active requests plus fast redirect
and HALT paths. Its quiet condition also requires an empty EU request queue.
That existing behavior is preserved. Frontend pending requests survive
arbitrary quiet/READY/exclusion delay; they do not force the BIU to become idle.
All claims from this candidate's simulations will be contract observations,
not new silicon measurements.

## Minimal interface and closed contract

Proposed standalone module: `v30_rqak_frontend`. Inputs are `CLK`, `RESET`,
`CE`, `RQAK_I_N[1:0]` (resolved lines), and `INTERNAL_GRANT[1:0]` from the
unchanged `v30_bus_ownership.GRANT`. Outputs are `REQUEST[1:0]` to that
utility, `RQAK_DRIVE_LOW[1:0]` (low-drive enables only), `EXTERNAL_GRANT[1:0]`
and sticky per-channel `PROTOCOL_ERROR[1:0]` diagnostics cleared by reset.
The frontend has no physical inout, high-driving output or fabricated core pin.

The external resolver drives each line low when its CPU low-drive enable or
requester's low-drive enable is set; otherwise it is high. Inputs must be
synchronous to CLK and are sampled only at CE. The frontend remains clocked
and receives CE while CPU enables are frozen. The level adapter continues
to supply CPU CE/CE_HALF and bus isolation decisions. Its existing obligations
remain in force, including event retention and prohibition of SS writes.

### Request capture and selection

- An external falling sample is eligible only after a sampled high has armed
  that channel. A held-low input produces one event, never repeated events.
- Reset clears the armed state. A line already low after reset is invalid
  until high is observed and a new falling sample occurs; no stale request is
  manufactured by reset release.
- An accepted request latches REQUEST high. The request pulse returning high
  does not cancel it. Pending requests survive exclusion and busy/READY delay.
- Both channels are captured independently, including while the other channel
  is acknowledging, owned or returning. When both requests are pending before
  the level adapter chooses an owner, channel 0 wins. A current internal owner
  is never preempted, even if channel 0 arrives before that owner's ACK begins.
  This is the existing adapter's selection contract, not a new timing claim.
- A redundant falling event on an already pending non-owner channel sets its
  PROTOCOL_ERROR and is ignored. It cannot release the current owner.

### Acknowledge and external ownership

- INTERNAL_GRANT already freezes the CPU and isolates its bus earlier than
  external ownership. It is not permission for the requester to drive.
- ACK starts only after the selected owner's resolved line is sampled **high**
  while the CPU is not driving that line. This proves its request pulse ended.
  A held-low request retains pending/internal ownership, with CPU frozen, but
  produces neither ACK nor EXTERNAL_GRANT until high is observed.
- Once internal ownership and that high sample exist, RQAK_DRIVE_LOW asserts
  for exactly one eligible CE interval. At the next eligible CE it deasserts
  and EXTERNAL_GRANT asserts for that owner. Transfer is at ACK's end.
  CE=0 stretches the interval in fabric clocks without completing it.
- CPU ACK reflection is masked on its own channel. The frontend cannot treat
  its low-drive echo as either an external request or a return pulse. Other
  channel capture continues independently.
- Rearm requires a sampled high after the local ACK ends. The requester may
  send a return only when at least two complete eligible CE intervals have
  elapsed since ACK end. An earlier falling event sets PROTOCOL_ERROR, is
  ignored and disarms the channel until another high sample. If that invalid
  pulse stays low past the permitted time, it is **not** reinterpreted later.
- Exact abstract sampling convention: let E be the eligible edge ending ACK.
  Its low line sample is masked as local ACK echo. A high sample at E+1 arms
  the owner's channel; a fall at E+2 is valid, because two intervals have
  elapsed including the interval completed by E+2. If the owner's resolved
  line instead remains low at E+1, before any post-ACK high observation, that
  low is early/malformed: set PROTOCOL_ERROR and ignore it until high and a
  fresh eligible fall. This explicitly diagnoses an E+1 low even though no
  armed falling transition exists yet. Holding it through E+3 cannot make
  it mature into a return. The minimum separation applies to the ACK owner's
  same line; independent requests on the other channel remain permitted.
- Only an eligible falling sample on the externally granted owner's channel
  is a return. A pulse on the other channel cannot release that owner; it is
  handled by the independent pending-request rules.

### Return and CPU restart

- An accepted owner return immediately clears EXTERNAL_GRANT. The requester
  must stop driving independently of that bookkeeping and complete its pulse
  by returning the resolved line high.
- REQUEST for the internal owner remains high until its returned line has
  been observed high and **two additional complete CE intervals** have elapsed
  after that high observation. This return gap is an explicit conservative
  engineering choice, not a newly established NEC T4/resume fact.
- Throughout return-low and the registered return gap, INTERNAL_GRANT remains
  owned and both CPU enables remain gated. The frontend must not delay only
  EXTERNAL_GRANT bookkeeping while allowing the level adapter to restart CPU.
- At gap completion the frontend drops the owner's REQUEST. The level adapter
  consumes that change on its next CE release edge, keeps CPU frozen on that
  edge, then permits execution on the following eligible edge unless another
  pending owner acquires. The frontend does not alter this existing cadence.
- The returning owner cannot request again during return-low or return gap.
  Such a falling sample sets PROTOCOL_ERROR and is ignored. A new request is
  eligible only after that return is complete and a fresh armed falling sample
  is seen. Held-low malformed pulses are never converted into future requests.

### Reset

RESET has priority over CE and every phase: clear pending requests, local ACK
drive, external grants, diagnostics, counters and rearm state. Requesters and
external bus isolation must stop remote drive on RESET independently of stale
grant outputs. The level adapter's reset delivery remains unchanged. Requests
held low across reset stay invalid until a high sample rearms their channel.

## Registered implementation and simulation bars

Before acceptance, the dedicated controller testbench must PASS **at least
32 distinct directed output/transition checks**, fail on any mismatch, and
exercise every category below. Increasing a check count by repeating an
identical assertion does not satisfy the bar. No unexpected protocol errors
are allowed in valid flows; malformed-flow tests must assert the specified
diagnostic and show that ownership cannot change through the rejected pulse.

1. Both channels request/ACK/own/return/resume individually.
2. Simultaneous and independently queued requests select channel 0 before
   internal grant; current ownership does not preempt; pending channel survives.
3. ACK starts only after request-high, lasts exactly one CE interval and
   publishes external ownership only at its end.
4. Own-ACK loopback cannot create or release ownership; the other channel can
   request during that ACK.
5. CE=0 stretches acquisition/ACK/return phases; both CPU CE and CE_HALF remain
   frozen while internal ownership exists, including ACK and return gap.
6. Requests survive EXCLUDE, quiet=false and modeled READY/backlog delays;
   returning request high never cancels the pending request.
7. A request held low produces one pending event, no ACK before high, and no
   external ownership until ACK completes.
8. Early return is flagged and ignored; held-low invalid return does not become
   valid as its age increases. Specifically, E+1 low held through E+3 sets
   PROTOCOL_ERROR and cannot release ownership; E+1 high followed by E+2 fall
   accepts return. E's own ACK-end echo is masked. Fresh high/new fall is
   required after rejection; the other channel can request in those intervals.
9. A non-owner pulse cannot release the owner; redundant pending pulses are
   flagged. Same-owner requests during return are rejected, and a fresh request
   after return is accepted.
10. Return-low blocks restart; the two-interval engineering gap follows observed
    high; CPU remains frozen until the unchanged adapter completes release.
11. Reset from idle, pending/wait-high, ACK, externally owned, return-low and
    return-gap clears all outputs/state; low-held inputs require new high rearm.
12. Valid flows retain one-hot internal and external grants and never drive
    both ACK lines; reset independently prevents remote-drive assumptions.

Fresh binaries must carry receipts hashing controller/frontend/testbench,
runner, relevant core SV/SVH/HEX inputs where used, binary and full logs.
Build artifacts stay under the thread's work directory. Negative cases remain
in the full run and are not silently dropped or relabeled after a failure.

Default standalone-controller, default-core integration and opt-in native
guard regressions must remain PASS with their existing bars (26 controller
checks, actual-core pause/resume and 18 guard case/wait combinations plus
optional-port absence). The default-core regression retains its raw versus
adapted public bus/QS/architectural-register comparison for at least **200
eligible CPU clocks** before requests. That existing testbench instantiates
the level adapter and **does not instantiate the new pulse frontend**.
It therefore supplies regression evidence, not frontend/core integration.
The new standalone gate includes the frontend, level adapter, dedicated
testbench and runner in its declared hashes. Actual core plus pulse-frontend
integration is outside this bounded first implementation unless separately
scoped; no complete wrapper/core integration claim is authorized by these
standalone checks. No production QIP or ucore source changes are planned.

## Synthesis and close-out boundary

Parent will scope any standalone synthesis check and the inherited G6
promotion requirement independently. Controller simulation alone does not
certify synthesis, physical NEC timing or hardware. Record all failed attempts
and corrections in a later results document; preserve original preregistration.
No commits of implementation, uploads, merges or FPGA programming are implied
by writing this preregistration. Native yield/resume remains separate work.
