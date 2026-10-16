# PR1 fixed-profile execution addendum — 2026-10-16

This supplements, without rewriting, the
[2026-10-15 preregistration](rqak_master_adaptation_prereg_2026-10-15.md).
Programs, expected words, coverage requirements, reset behavior and every
watchdog remain unchanged. No execution result is claimed by this addendum.

`tb_rqak_8080_irq` accepts the optional numeric plusarg `+profile=N`, with
`N` spelled as canonical decimal `0..17`. Its fixed mapping is
`N = 9*emulation + 3*request_point + w`,
where `emulation` is 0 for native and 1 for 8080, request points 0/1/2 are
decision/active entry/INTA gap, and `w` 0/1/2 selects READY waits 0/1/3.
A selected process executes exactly one complete original profile, including
its own reset, coverage and endpoint checks. A parsed index outside `0..17`,
malformed spelling or integer overflow is fatal before execution: the original
string must equal the formatted parsed index.
Without the plusarg, the original complete 18-profile matrix runs in order.
The final summary reports the actual selected count and index.

The future batch owner must run the fixed indices 0 through 17, retain each
process's complete output and actual return code, and continue to the next
fixed process after a functional fatal. It must finish and categorize the
whole batch before any CPU repair is considered. Missing, partial, timed-out
or instrument-invalid profiles cannot count as passes. Selection is not a
filter chosen from observed results, and neither literals nor time limits
may be changed to obtain a pass. No automatic retry or source repair occurs.

## Address-domain erratum after the first complete batch

The first 18-process batch completed with three passes (native, waits 1,
selected indices 1/4/7) and fifteen instrument failures at the same unconditional
upper-address-zero check. All outputs and actual exit codes remain retained.
Those logs did not include the bus kind/address at the fatal, so they do not
establish that all fifteen failures occurred on HALT.

The check's domain was nevertheless wrong by the existing bus contract:
HALT is a pseudo-cycle, and the BIU publishes the retained AD output latch,
including its high status nibble, rather than a RAM address. The zero upper
address requirement belongs to this fixture's memory CODE/MEMR/MEMW cycles
(BS 4/5/6). INTA (BS 0) has its separate exact zero-address contract. At the
same existing phase-1 sample, HALT (BS 3) now emits one diagnostic observation
with BS, full public address, modeled phase and actual BIU phase. A memory
address fatal reports those same attribution fields. This does not reinterpret
HALT's retained address as a memory access or alter any read/write oracle.

READY generation, phase advancement, UBE sampling, resets, all eighteen fixed
program/cut/wait tuples, literals, selector, coverage and watchdogs are unchanged.
No CPU defect or CPU repair follows from this instrument-domain correction.
The entire batch must run again under separate authority; earlier failures are
not retroactively changed to passes.

The existing gate command builds and runs the default full matrix; it does
not itself own this 18-process campaign. The separately reviewed owner supplies
`+profile=0` through `+profile=17` to the one current compiled binary, with
explicit execution authority. Source verification does not invoke that binary.

SIMPLICITY: this is 80's era hardware — nothing on the die is wasted.
Complex or confusing observed behavior is likely simple systems interacting
in ways not yet understood. A large fitted table, a many-cased rule, or a
per-opcode special case is a signal of misunderstanding, not a deliverable.
