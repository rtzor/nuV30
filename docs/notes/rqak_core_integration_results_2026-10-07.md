# RQ/AK real-core integration results — 2026-10-07

Preregistration `fd4095fe` preceded implementation and runs. This milestone adds only the integration TB, exclusive `--rqak-core` runner mode and documentation. Frontend, ownership adapter, ucore RTL and production QIP are unchanged.

The actual simulated chain connects resolved RQ/AK lines with own ACK echo, frontend REQUEST, level-adapter GRANT and frontend external ownership to the demultiplexed core's real BUS_EXCLUDE, SS_BUS_QUIET and gated CE. These are modeled transactions under an engineering whole-core freeze contract. They do not establish hardware behavior, native NEC pin timing, EU progress during ownership or FPGA timing.

## Final acceptance

All **13 profiles passed**. Each first compared raw and chained core public buses, QS and architectural registers for **200 eligible CPU clocks without requests**. Raw comparison ends before arbitration.

| Workload | Waits | Required literal result | Continuous frozen clocks |
| --- | --- | --- | --- |
| F0 INC even word 0200 | 0, 1, 3 | 0001 to 0002; completed write before grant | 42 each |
| F0 INC odd word 0201 | 0, 1, 3 | 0001 to 0002; two modeled bus writes; adjacent A5/5A unchanged | 42 each |
| F0 REP MOVSW, three iterations | 0, 1, 3 | destination 1111/2222/3333, CX=0, three writes before grant | 42 each |
| IRQ, two INTA and handler | 0, 1, 3 | two completed INTA; four excluded gap clocks; SP=07FA, CS=0000, terminal HALT IP=0104; frame PSW=F202/CS=0000/IP matches registered acceptance boundary 0003 | 42 each |
| READY, queued ownership and DMA loop | 0 plus forced READY low | 16 eligible actual Tw clocks; channel 0 then queued channel 1; six-byte queue naturally full; resumed fresh read and store consume 6A35 | 52 |

Every isolated edge checks no modeled CPU transaction completion and no state/phase advancement. Snapshots include architectural registers, all six queue storage bytes, registered queue count/head/fetch pointer, EU state/microcode/loop registers, BIU phase/run state and public bus. They persist through ACK, return gap and queued owners until an edge actually samples CORE_CE high. Acquisition checks quiet and absence of running/committed BIU cycles; MEMR/INTA completions corroborate actual pre-edge T3/Tw. Write lanes are sampled at actual T1.

The READY profile retains both request pulses after the resolved lines return HIGH, grants neither while READY is low, and acquires channel 0 first after draining. Peers change 0600 to 3C5A then 6A35 only with their matching external grant, CPU bus disabled and CORE_CE low. CPU CE stays inhibited between owners. Following final return, one new completed MEMR at latched 0600 and one completed literal store at 0602 are counted, with AX and destination 6A35. Earlier reads are allowed.

The public DMA loop at 0000:0000 is `A1 00 06 A3 02 06 F7 F1 EB F6` (`MOV AX,[0600]; MOV [0602],AX; DIV CX; JMP 0000`). Initial registers are AX=1234, CX=0001, DX=BX=BP=0000, SP=0800, SI=0300, DI=0400, all segments and IP=0000; PSW input 0002 normalizes to F002. Memory is initialized to byte 90, with word 0600=1111; the loop uses data/result addresses 0600/0602. Queue initialization is empty and subsequent queue accumulation is natural. The protected programs and complete public memory images remain in the receipt-declared TB.

## Reproduction and final receipts

From the repository: `python sw/bus_ownership_gate.py --compiler clang --rqak-core`. The modes `--native-guard`, `--rqak`, `--core` and default controller remain regressions. Each creates a fresh build under thread `work/bus-ownership/` and records declared SV/SVH/HEX inputs plus runner hashes, exact command/tool versions, binary and full log hashes. These runs used Verilator 5.050 and clang 22.1.8 through the existing Windows recipe. Compiler flag/header warnings remain visible in logs.

Run IDs below refer to local `work/bus-ownership/bus_ownership_<id>/` custody directories, not portable source dependencies.

| Run | Result | Receipt SHA-256 |
| --- | --- | --- |
| zhcq7yj7 | Actual chain 13 PASS; parent verified/replayed | 8e8292165b3ddeba1860022960dacbf932288ddbe07fe2852e10084e680e13a4 |
| 39pwh14c | Parent independent fresh actual-chain build 13 PASS and replay | f8be70e53464806409ae3615402568723bd7ff95f1bc7e8a0d618bee1436299f |
| 2wvv_drk | Native guard 18 PASS and absent default port; parent verified/replayed | fcaf6308306bdf61579d57ab97312e62cd1c8d6697494c029203ad0884392e2a |
| _mxlluy7 | Standalone frontend 66 distinct/82 total PASS; parent verified/replayed | d255615bf6c6d88a3a12358ada4d8d4579b63797b792ed7f46131b33549f0e97 |
| xl9ivo53 | Level controller 26 PASS; parent verified/replayed | 2c4181a52ecc91c438638d96462f516742a2ae8fe1cc4b4320efcdaad444227e |
| 6k9o9lu8 | Default-core regression PASS; parent verified/replayed | 97260d23a3b9a3d7eccd7f65e68e95e36fc44a88f51efa8d88f0d776d31ebacc |

Agent integration binary SHA-256: `6fc2c10f040ef267c50dd2f873c2551a8222cc054d5e1986847b050e57adc638`; full log `013a283bb33bfcbf7e04823350a949be61bc0af9c2440f8d2d5fc47f76b2057d`. Parent independent binary `6d35e69bf252e835e4a2c462cf1492601473e7308ea109d2c0b8e32528a8865a`; full log `8b693c817854d4e0f27329aec9b20da1192af94f2024c184a23b24c2d400c1f4`. Parent independently verified all declared inputs, binaries and logs against receipts.

## Retained failures and correction

Three intermediate builds (`7zojja37`, `0bhz_gc3`, `8x96_74o`) failed the IRQ terminal-HALT watchdog after the first three waits=0 profiles passed. Their complete `gate.log` files remain retained. They are not acceptance runs.

The synthetic interrupt source originally held INT high indefinitely. The diagnostic trace showed two INTA, vector reads 0080=0100/0082=0000, frame F202/0000/0003, handler fetches 0100=2690 and 0102=F490, then HALT at IP0104 followed by execution at IP0105 while INT was still high. The corrected public controller withdraws INT only after the second modeled INTA completes, applying the same stimulus to both cores. Final runs pass the terminal-HALT bar; no RTL, timeout or requirement was relaxed.

The stacked PSW expectation was corrected from unnormalized initialization input 0202 to F202 using existing `PSW_WRITABLE=0FD5`, `PSW_FORCED=F002` and backdoor normalization. This is source-derived. The second attempt added all-completion counting and direct BIU corroboration; the third added the retained transaction diagnostics. The runner remained frozen throughout acceptance/regression builds.

## Production scope

Parent verified the test-only synthesis reuse proof `work/quartus-control/test_only_synthesis_reuse.json`, SHA-256 `5e4293d494294eca741a52a536f923f62ebf9528a96a2efcb5677d6eb1832996`: the existing 85-input production closure is unchanged and all six mismatch lists are empty. This reuses earlier production compatibility evidence; no new Quartus run or frontend timing/native/silicon claim is made.
