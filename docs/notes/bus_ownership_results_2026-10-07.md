# Generic bus ownership utility — simulation results

Date: 2026-10-07. Fork: `rtzor/nuV30`. Branch:
`feature/bus-ownership-contract`. Base:
`ed50fb4e5222fb5567c01ff16d34cd8a08f584e2`.
Scope registered at `28b98529`, inventory at `f8a9be0c`.
Independent clone in this chat; stable PCS86 integration outside the work.

## Result and boundary

The external adapter's declared synchronous contract passed controller and
demultiplexed-core simulation. It is an opt-in integration utility, absent from
production QIPs. **This is not native V30 bus arbitration or native LOCK
validation.** A caller must provide valid EXCLUDE, synchronous bus isolation,
reset of other masters and retention of interrupt events. See
`bus_ownership_prereg_2026-10-07.md` for the complete obligations.

No core source, instruction timing, ROM/PLA table, save-state map or production
harness changed. No private inputs, media or diagnostic PCS86_DBG_REGS patch
were imported. Existing LICENSE and attribution retained. No synthesis or
hardware tests were run; no FPGA programming. No RTL promotion of the native
core is claimed under the repository's Quartus receipt rule.

## Executed checks

Toolchain: Verilator 5.050 (2026-07-01), MSYS2 clang64 clang 22.1.8,
x86_64-w64-windows-gnu, C++20. Fresh builds use --assert.

| Check | Result | Scope |
|---|---|---|
| `python sw/bus_ownership_gate.py --compiler clang` | PASS, 26 directed output checks | CE and CE_HALF gating, quiet/exclusion, cancellation, channel-0 priority, no preemption, release/resume and reset |
| `python sw/bus_ownership_gate.py --compiler clang --core` | PASS | Actual unmodified ucore, demultiplexed interface, synthetic public DIV-loop instruction bytes |
| Parent independent replay | PASS, both binaries | Input, binary and log hashes verified before re-execution |
| `python sw/test_artifact.py` | PASS, 45/45 | Existing artifact integrity layer; includes deliberate rejection-path tests |
| `git diff --check` | PASS | Whitespace check |

The actual-core harness compares adapted and raw cores for 200 no-request
clocks. It then requests ownership while READY is low during a real read;
the adapter does not grant or stop core CE during the 16-clock wait. After
READY returns, acquisition blocks CE on the transfer edge itself. During a
32-clock pause, architectural debug registers, all six prefetch bytes, queue
count, fetch pointer and public bus outputs retain their values. Release
resumes execution. A separate acquisition occurs at a quiet boundary with
all six queue bytes occupied.

The core harness uses existing V30_BACKDOOR verification ports with injection
and scripted-consumer controls tied inactive. It adds no diagnostic port.
CE_HALF is tested in the standalone controller only; actual multiplexed-core
integration remains untested. EXCLUDE is a supplied guard stimulus, not a
measurement of native BUSLOCK. This small program is not the complete inherited
instruction or fuzz suite, and no historical silicon scores were re-claimed.

## Artifact identities

Receipts include every declared SV/SVH/runtime HEX input, the runner, build
command and log hash. Local intermediates remain under this chat's
`work/bus-ownership/`; binaries and build outputs are not committed.

| Artifact | SHA-256 |
|---|---|
| Controller receipt | `8174679b9db9e2f3c22b7ba82edfa9e5d701da10e3f2a7df809fb55094bd03b8` |
| Controller binary | `2963a46a44fa948c51ff9f1f70037a8fcab62116274e7e9da8c2cc06ae51d957` |
| Core-integration receipt | `90247f850c8fc3c255525cd35ad2e37a6d48752d1d295157e718462358d8341f` |
| Core-integration binary | `50404b6be85059b3062c6210802858571a57f529cb7d307a89a0ca8ba743d44c` |
| Existing `sw/test_artifact.py` source | `52457c516d2b126f43c4a4cb6b70d379b87762dc0029ef9abe096f1e06c00e23` |

## Failures retained and resolved

Initial GCC 16.2 linking failed on a std::string move-constructor symbol in
the local Verilator support library. UCRT clang then failed against GCC
coroutine headers. The clang64 toolchain built successfully after using C++20
and Windows-specific make overrides: clear exported LINK before clang linking
and use CFG_LDLIBS_THREADS=-pthread instead of the unavailable -latomic.
No compiler installations or system files were modified. GCC remains the
runner default; clang is explicit. Verilator-support compiler warnings about
unused -fcoroutines and unknown -Wno-subobject-linkage remain visible in the
logs. The final new RTL elaborated without warnings.

The first actual-core program used a MUL loop and failed the full-six-byte
queue coverage bar, after passing the other checks. Its log is retained in
`work/bus-ownership/bus_ownership_p7kz7n49/gate.log`. The bar was not lowered:
the final even-aligned DX-clear/DIV CX loop reaches it. Only the synthetic
test program changed; no instruction execution timing was adjusted.

Independent source review found no controller defect within the declared
contract. It clarified combinational bus-enable and reset-drive obligations,
recorded in the module header and contract. These are caller requirements,
not evidence that the physical RQ/AK or LOCK protocols work.

## Next work

Restore a native BUSLOCK output/exclusion contract from the documented and
upstream-measured behavior, including INTA and repeat/standby cases, before
allowing generic DMA against arbitrary native code. Then implement maximum-mode
RQ/AK request/acknowledge/release timing and a genuine BIU yield/resume path,
including waited transfers, pending prefetch, split accesses and concurrent
requesters. Native instruction failures follow the contrasted inventory;
BRKEM/8080 completion remains last in the requested order.
