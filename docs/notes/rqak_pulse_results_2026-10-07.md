# Conservative RQ/AK pulse frontend — results

Branch `feature/rqak-pulse-interface`, from `69580745`. Preregistration
`27468a21` was committed before frontend RTL, testbench and simulation:
[closed contract and registered bars](rqak_pulse_prereg_2026-10-07.md).
Intended PR destination: `rtzor/nuV30`, base `master`; upload is deferred.
No ucore, production QIP, stable PCS86 integration, private asset or FPGA
programming change is part of this milestone.

## Implemented scope

`v30_rqak_frontend.sv` is a standalone synchronous FPGA utility connected to
the existing level ownership adapter. Two externally resolved active-low
inputs accept request events; two low-drive enables produce CPU ACK pulses.
There is no physical inout or high-driving output. It retains requests across
quiet/exclusion delay, prevents owner preemption and distinguishes early
internal ownership from externally valid ownership at ACK end.

ACK requires observed request-high and lasts one CE interval. Its reflected
low is masked while the other channel remains independently sampled.
After ACK end E, E+1 HIGH/E+2 falling is valid; E+1 LOW is malformed and cannot
mature into return while held low. Return clears external ownership but holds
internal REQUEST through observed high plus two CE intervals. That gap and
CE's abstract sampling convention are engineering policy, not physical NEC
edge alignment. The existing adapter then releases on its frozen edge.

NEC documents the direction, polarity, one-tCYK CPU ACK, transfer at ACK end
and same-line minimum pulse separation in the reviewed figure. Interpreting
the third requester pulse as return/release is the contract's protocol
interpretation, not additional NEC prose evidence. See the preregistration's
precise 1991 data-book figure/text anchors. Native BIU yield/resume, native
EU progress from prefetch and physical first-T4/resume timing remain pending.

One-hot sticky INTERNAL_GRANT, external line resolution/isolation, synchronized
inputs, reset drive release, interrupt retention and SS-write exclusion remain
caller obligations. Grant latency is unbounded, as in the existing adapter.

## Final standalone simulation

```text
python sw/bus_ownership_gate.py --compiler clang --rqak
```

PASS: **66 distinct labelled output/transition checks**, 82 total invocations,
against the preregistered bar of at least 32 distinct checks. A unique-label
counter prevents repeated reset-helper checks from inflating that bar. The
testbench resolves remote lows with the frontend's own low-drive outputs,
so ACK loopback is present rather than merely assumed away.

Coverage includes both channels, ACK start/high prerequisite and exact
one-CE duration, external grant only at ACK end, own echo masking, other-channel
capture during ACK and first internal-owner observation, non-preemption,
pending channel-0 priority, quiet/backlog/exclusion delays, request-high
non-cancellation, CE=0 stretching, and CPU CE/CE_HALF gating while owned.

Malformed E+1 low is rejected through E+3; fresh high/fall later returns.
The valid E+1 HIGH / E+2 fall sequence is tested separately. Non-owner and
redundant pending pulses cannot release the owner. A clean return-gap scenario
proves its same-owner invalid pulse changes diagnostics from zero to one,
keeps REQUEST retained and preserves the expected grant/gating state.

Return-low and the HIGH-plus-two-interval gap keep CPU frozen until the level
adapter releases. Fresh same-owner requests after return require rearm.
Reset is exercised from idle, pending, wait-high, ACK, externally owned,
return-low, return-gap and internal release-wait. Explicit predecessor-phase
assertions prevent phase labels from describing a scenario never reached.
Held-low inputs across reset cannot manufacture stale requests.

All valid-flow checks require zero diagnostics. Malformed-flow checks expect
specified sticky diagnostics and unchanged ownership. Grants and ACK drive
remain one-hot. These are standalone controller/adapter observations, not
silicon measurements or actual-core-plus-frontend integration validation.
Quiet=false is a modeled busy/backlog input here; it is not a new real READY
bus-cycle measurement.

## Final receipts and regressions

Fresh local build artifacts are retained under the thread's
`work/bus-ownership/`; binaries and generated files are not committed.
The final frontend build is `bus_ownership_y0pvxa2j`.

| Artifact | SHA-256 |
|---|---|
| Frontend final `receipt.json` | `d6c7ccddce59214cfea3a92627fe613952c031001a8075cf613e4d9c6c020182` |
| Frontend final binary | `77f06c8a2f1238a5f679c6dfa238141e0ec0a747dd997bf4426810dc622e5aeb` |
| Frontend full `gate.log` | `60901f623a51798e6b29560757b0f97502eeaf3630a972c3a59c5926925d232b` |
| `v30_rqak_frontend.sv` | `525d27485e3a8b93b2ba1f37945f22386dfeb2eca17b50d21d656d842b066424` |
| `tb_rqak_frontend.sv` | `331eac7e1a094dfa94a23b070880e073a69f82aa2fc46d46d1f4e30373cad83a` |
| `bus_ownership_gate.py` | `1d319f37321bafc3688fb8529c8c134aacd6f893efe6afa996729e881ab8f010` |

The receipt also declares the unchanged level adapter source, exact build
command, tool-version log and binary hash. The log identifies Verilator 5.050
and clang64 clang 22.1.8. Existing C++ support-file tool warnings are retained;
the standalone RTL build uses `-Wall` without a functional warning waiver.

The final runner makes `--rqak`, `--core` and `--native-guard` mutually
exclusive. `--rqak --core` and `--rqak --native-guard` both exit 2 before
creating their specified work directory. Retained CLI probe logs under
`work/rqak-cli-probes/` have hashes:

- `rqak-core.txt`: `58dc9bac71babf929ed8696f0ef1d1e8b83226f5f1dd0242755d24575e1e4544`
- `rqak-native.txt`: `3e6172b9f008d74a586de81ddfecbf1665097995e7a68958e6d9981516c8dcf8`

Fresh existing-gate regressions use this same final runner hash:

| Local build | Result | Receipt SHA-256 | Binary SHA-256 |
|---|---|---|---|
| `bus_ownership_oywdxpiq` | Native guard: 18 case/wait combinations and negative optional-port control PASS; parent independently reran and verified declared hashes | `8f39529e7f6fcb2bc87e5bc4072df435eba5e8f58e06371967ba03343a8a9747` | `2266858076f5af49c8fd08e170e05120e16f812dc56bfa00dfca9f4633738537` |
| `bus_ownership_jy16xtcj` | Parent fresh standalone level-controller regression: 26 checks PASS; declared hashes verified | `2093a71f8864a6ea76d38ea582e9997ca05ae230868bcca3ab3f1d681ef5f757` | `5e855bb02dc593499d72a366bdf0e0afbef2a783ad466ea2af7068141ebe5858` |
| `bus_ownership_5ry8s39q` | Parent fresh default-core pause/resume regression PASS; declared hashes verified | `71b908d7e4ff05fa9dff754333632ecaeca60f8c5b218528b2a3031162ebdcf1` | `2af94bfd9dbacf954988a23cdd21598b4115f167d683e4e342dc58d07c48cdbb` |

The default-core test retains its 200-clock raw-core comparison and real READY
drain/prefetch/freeze/resume checks, but **does not instantiate the pulse
frontend**. These are regression results, not proof of a complete new
frontend/core wrapper. Actual frontend-plus-core integration remains separate.

## Review corrections and intermediate artifacts

No simulation build/run failed in this frontend session. Do not fabricate
failed logs from defects caught during source review or incomplete coverage.
The malformed-input scenarios above are expected PASS controls.

Before the first simulation, review caught an IDLE whole-vector `armed`
assignment that could overwrite the other channel's simultaneously captured
fall or high rearm. It was changed to update only the selected owner's bit.
The final tests explicitly exercise both coincidences. No failed simulation
log exists for that pre-simulation correction.

The first build `bus_ownership_86a0v5z6` passed 62 distinct/75 total checks;
receipt hash `d7288d73ea44cc91ec073887616ea3a8f0b361797125a167d3bacdb97e97cb11`.
Runner review then identified ambiguous combinations of gate flags; argparse
exclusivity was added without changing frontend RTL. Its fresh intermediate
`bus_ownership_azks_326` also passed 62 distinct/75 total checks; receipt hash
`ff3e6145c5b672d8fe2e9408ac4d48722c2d8ab98533aea8b44d7918cfbcce5b`.

Independent review found two coverage holes in both intermediate testbenches:
the purported reset-WAIT_HIGH case reset one edge before that phase, and a
same-owner gap-error check inherited an already set sticky error. These
intermediate PASS results therefore do not support those coverage claims.
The final testbench adds the missing phase-entry edge, predecessor-phase
assertions, internal release-wait reset and a separate error-zero clean-gap
scenario. Only the final receipt supports the full final coverage statement.
Frontend RTL remained fixed through those testbench changes.

## Synthesis and independent closure

Standalone Quartus analysis/synthesis of the final frontend source passed with
zero errors and zero warnings. Its receipt SHA-256 is
`fb1f59bba2d227b32692544bb1b11b7a5691cee83bbb587db729112636a9ffb5`, and
the declared frontend source is the `525d2748...` hash above. This is standalone
analysis/synthesis evidence; it does not establish fitter timing, a complete
physical bus interface or hardware operation.

Parent independently reran the final frontend binary: PASS 66 distinct/82
total checks, with all four declared input hashes, binary and full log verified
against the final receipt. No simulation gate remains pending.

Parent also verified all five synthesis inputs, four outputs, both tool
executable hashes and stage logs against the receipt. Post-synthesis VQM
SHA-256 is `16cb2ee9cfd776fefbed411f5bdc519f582c60de3ca257f7d5a7d06d634fa33d`.
Its eight output bits are driven by mapped registers, rather than discarded
or tied to constants. Quartus reports 20 registers and 15 pins. There is no
frontend fitter, timing or hardware claim.

The retained CONTROL/DEFAULT G6 receipt from the unchanged core/production
configuration is detailed in [the guard validation](bus_exclusion_results_2026-10-07.md):
receipt file SHA-256
`1b047d2e8bc0ab01b620fe99b2170e4e70505b38b4d10bd976cef68d074e5379`,
divclk 38.19 MHz, worst setup +6.923 ns and setup/hold TNS zero in every
reported domain. Its 1,346 warnings remain retained; this is one default
CONTROL build, not a frontend timing result or a Quartus-version comparison.

A read-only recursive QSF/QIP dependency comparison, additionally checking
ucore includes/runtime tables, active boot MIFs and the pre-flow build-date
script, confirms **85 static production inputs** and their references are
unchanged and covered by that CONTROL input manifest. Parent independently
reran this comparison after the frontend was written: PASS, no moved inputs,
changed reference edges or manifest coverage mismatch. The optional frontend
and its testbench are not production references.

Local corrected comparison:
`work/quartus-control/production_closure_after_frontend_v3.json`, SHA-256
`fafc4bc4b869f01b4a2f12e6a68feda552b56e420a91fc753e886b99909c9a08`.
The earlier 82-input comparison is retained and superseded; it omitted two
active boot MIFs and the pre-flow script. The comparison explicitly identifies
inactive literal resources rather than pretending they were compiled inputs.

The generated `build_id.v` was outside the original CONTROL input manifest.
Its retained bytes define only `BUILD_DATE "261007"`, matching the pre-flow
generation recorded in the CONTROL log; SHA-256 is
`51290c0a3c369581c0732f4dfd10fabb1daed9804041f2ce4732d7725644b9fa`.
This custody supplement was recorded after CONTROL, without changing its
original receipt or retroactively declaring that file an original input.

The bounded frontend is ready for review. Native pin timing, silicon
behavior, actual frontend/core integration and native BIU yield/resume remain
unvalidated. Upload remains deferred to `rtzor/nuV30`, base `master`.
