# BIU-yield adaptation to the 8080 master — 2026-10-16

This preregistration precedes the adapted PR2 builds and runs. It preserves the
2026-10-07 contract, programs, literal results, watchdogs and historical results.
The ordinary merge brings in the published PR1 adaptation and the current C4
8080 core; it does not turn their earlier artifacts into PR2 measurements.

The gate driver retains both `--biu-yield` and `--rqak-8080-irq`. The only new
BIU-bank edits connect 29 empty output slots to typed unused wires: four in the
two-core generate body and 25 in the separate BIU fixture. No oracle changes.

The existing positive population remains 28 real-core profiles and six
separately scoped BIU fixtures. Two runtime misuse controls must terminate
nonzero with their declared diagnostics: owned 8080 mode and SS mutation during
arbitration. Three elaboration controls must reject an absent yield port, yield
without ownership support, and unsupported multiplexed yield. Run the six
existing ownership gates with strict lint and retained full logs; the new BIU
gate uses separate lint, build, compiled review and run stages. No warning
suppression may replace a failed functional or structural check.

`YIELD_PENDING` is deferred while MD is 8080, including forced-native interrupt
entry that preserves the interrupted frame's MD. `BUS_OWNED` in that mode remains
unsupported. Keep CE live for BIU yield, external bus isolation, event retention,
and both `CORE_QUIET=YIELD_READY` and the independent `EXCLUDE=BUS_EXCLUDE` guard.
The corrected interrupt guard and committed opcode namespace are unchanged.
`BUSLOCK_N` is constant inactive only with staged LOCK disabled. Whole-core
freeze with staged LOCK and the existing multiplexed/staged combination remain
unsupported; this adaptation does not qualify a new staged-yield profile.

Acceptance also requires current SS90/232/tag90E8 and ROM-source checks, fresh
default smoke baseline/holdout (12+12), and a fresh default G6 artifact before
RTL promotion. Optional-yield mapped retention is a separate obligation. No
NEC RQ/AK or HLDRQ/HLDAK pin protocol, silicon timing, nominal 10 MHz CPU, or
50 MHz/divide-by-five timing claim follows from these finite simulations.
