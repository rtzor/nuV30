# Native BUSLOCK tooling — custody addendum 2026-10-08

This supplements the committed registration `de2e41c6`. The 144-cell population,
zero-error custody bar, strict per-clock comparator and pending native RTL status
remain unchanged. No new timing mechanism is selected or accepted here.

## Retain the failed latest-manifest interpretation

The first custody survey found that the current merged
`sw/testdata/iret-tf/board/manifest.json` contains only the last validation run's
60 image identities. The merged table and original raw captures also contain
earlier derivation cells. Exactly 64 selected `I0`/`P1` `nop`/`addrr` cells have
no image identity in that latest manifest. The original interpretation requiring
all images from only that manifest FAILS for those 64 cells. Preserve that
finding and any corresponding failed audit; never invent missing image hashes
or alter the original manifest.

## Explicit original acquisition source

For those exact 64 control cells only, use the original derivation acquisition
manifest from Git commit
`22151f64c7151120472c0be90591a18fa41964a1`, repository path
`sw/testdata/iret-tf/board/manifest.json`.
Its original byte stream is 25,182 bytes and SHA-256
`81e2f7f8dd1ced9848220e2e7c549f9d05b757b3f3eabb8f4e8182ec5a706462`.
It declares socket source, divider 8, 832 derivation cells, 208 image identities
and timestamp `2026-08-12T01:02:34Z`.

Retain its byte-exact snapshot as
`docs/notes/native_buslock_iret_derivation_manifest_2026-10-08.json` and seal its
Git commit/blob and byte identity in the public inventory. The other 80 selected
cells use their current explicitly named acquisition manifests. The source map
is fixed by experimental leg, not by a candidate's success or pin values.

Acceptance requires all 16 selected historical control raw shards to be
byte-identical to their current originals; all 64 historical/current table
entries must agree in canonical word-stream hash/count and image identity;
each original manifest image must agree with those tables. An absent historical
object, conflicting source or modified recovered manifest remains an error.
Custody verification artifact:
`work/native-buslock-evidence/historical-manifest-custody.json`, SHA-256
`ff96d02b5d4cb234f29d20bbbdf85f9726c817d213373df933fdd64802873588`.
This is recovery of an actual committed acquisition record, not a recomputed
image recipe or a newly observed hardware fact.

## Exact checkout byte variants

Some tracked source text is checked out with CRLF on Windows while its original
Git blob uses LF. Original compressed captures do not have this distinction.
For portable offline verification, the inventory may enumerate only those two
exact byte streams for affected text: the verified Git blob, and the mechanical
LF-to-CRLF Git checkout of that same blob. Record both SHA-256 identities and
the Git blob ID before acceptance. The verifier must hash actual bytes and
accept only an explicitly enumerated identity, recording the chosen identity
in its receipt. Do not normalize text, accept arbitrary equivalent JSON,
rewrite originals, or reinterpret stale SHA256SUMS entries as current input
hashes. Raw compressed captures and per-cell canonical word-stream hashes
still require their single sealed original identities.

The latest-manifest failure stays visible alongside the restored historical
chain. A successful custody audit validates this chain and tooling; it does not
implement native BUSLOCK, repair historical silicon residuals or close the
missing memory-RMW/split/REP/RQ-AK capture debts.
