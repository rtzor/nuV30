# PCS86 two-phase CPU contract

This branch adapts wickerwaka/nuV30 `a35a29c` and `ce39ed61`, with the
unconditional-port/freeze prerequisite `1c71c4f5`, onto the Final53 8080 fork
and its db3e978 queue-ripe/LEA backports. The EU arms and preload retain the
fork's execution logic. The combined branch also uses the adapted `2ceb8c3`
chain flattening. No optional staged LOCK or RQ/AK profile is qualified here.

`CE_HALF` is mandatory for the EU in both bus shapes. The inherited top's
older prose about CE_HALF belonging only to multiplexed AD describes the
earlier interface; the unconditional port, current freeze assertions and
this document describe this branch's contract.

The PCS86 wrapper keeps a 50 MHz fabric/service clock and nominal 10 MHz CPU.
Its modulo-five divider commits CPU state at count4 and captures derived EU
stage1 at count1. CE -> HALF has two fabric periods (40 ns); HALF -> CE has
three (60 ns). The enables never coincide. A guarded CPU tick can suppress CE;
HALF continues and recaptures the same architectural/BIU state. A caller that
stops both enables must re-prime HALF before resuming CE. No extra CPU cycle
or nominal CPU frequency increase is introduced by the split.

The 780-bit derived shadow is the identical pack/unpack at the cut: upstream's
779 bits plus `md_write_enabled_n`, already present in SSA_E_MODE8080 bit1.
Only functions of CE-committed EU state and registered BIU publications belong
in stage1. READY, data and pin sampling remain at the original CE boundary;
POLL shifts in stage2 beside the other pin pipelines. The runtime assertion
requires the captured shadow to equal the live stage1 value at every normal
CE. This is a falsifier over executed tests, not silicon equivalence.

Reset causes the shadow to track the reset state before execution. The wrapper
resets its divider and schedules HALF before its first post-reset CE. Save
state writes require both external enables off, no simultaneous reset, and
command-staging drain before resume. Stage1 evaluates independently of the
SS write arm; that arm reloads the original preload for architectural writes.
The final drain reconstructs the shadow from fully restored state. The
lifecycle fixture allows two drain clocks and checks the complete 232-word
stream after explicit AX/session disturbance and restoration. External bus
transactions and platform save/restore are outside that pure-core fixture.

Final53 already used private version `0x90`, tag `0x90E8`, before this branch.
The package and all addresses remain byte-identical to db3e978. `s1q` is
justified as derived state in the census whitelist; it survives edges and is
not mislabeled as a temporary. The standing lint was corrected to expect the
fork's existing version, and strengthened to recognize same-line sequential
assignments. Missing read, missing derived entry, wrong version and unmapped
state mutants must all fail.

For the MiSTer integration, exclude shadow registers from the inherited CE5
state collection. CE-state -> shadow gets setup/hold 2/1; shadow -> CE-state
gets 3/2; CE-state -> CE-state keeps 5/4. Input/reply/divider paths and other
shadow boundaries retain their single-cycle budget. These exceptions require
fitted enable/hold evidence and all-corner timing; source-level simulation
alone does not qualify them. Reset priming and tied-off platform SS writes
are part of that integration contract.

Finite validation records and device-specific resource/timing results live
in the isolated fpgaMach integration branch. MiSTer results do not qualify
the complete Cyclone IV EP55 machine or a physical board. No stable core is
replaced or activated by this work.
