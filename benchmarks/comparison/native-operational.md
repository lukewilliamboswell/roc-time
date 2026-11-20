# Native coverage, zone and recurrence results

Both fresh sessions on 2026-11-20 UTC met all 86 coverage targets against
Rangemap 1.7.1. The highest ratios were 1.475× and 1.476× for subtracting
empty coverage from empty coverage. The other 59 rows record diagnostic or
absolute timings across coverage rejection, named-zone interpretation and
bounded recurrence.

Apple M2 MacBook Air (Mac14,2), macOS 26.3.1(a) build 25D771280a,
battery power, native scheduling. Roc `nightly-2026-11-18-a520eed`,
LLVM speed, `arm64mac`, Zig 0.17.0. Rangemap builds with pinned Rust 1.95.0
using `--offline --locked --release --target aarch64-apple-darwin`. Each
session uses three independent process rounds with three warmups and nine
samples. The local session reports record operations per sample.

Each coverage adapter validates both selected inputs against the independent
point model and observes all required results. Zone rows use the pinned IANA
2026e data and verify gaps, every ordered fold result, transition endpoints
and out-of-validity responses. Recurrence rows verify the returned dates,
limit status and candidate bounds. Coverage has a peer timing target. Zone and
recurrence measurements establish host-scoped Roc baselines.
[Workload profiles and semantic intersection](README.md#native-performance-matrix)

| Measured source file | SHA-256 |
|---|---|
| `package/Coverage.roc` | `1c6a0648a37bc2e22afed81698180da013df6386cd9fa39b52a90bc69149e73c` |
| `benchmarks/operational/main.roc` | `b4fc4a8c66c40a9c9c1769fe405cd91fde2bd1ddb9be40b32b6a7d072280aafd` |
| `benchmarks/operational/CoverageWorkload.roc` | `fea85dc5bdeab7125ed38c28406912569a28ccdc943854b4c354844c7f3e976b` |
| `benchmarks/operational/ZoneWorkload.roc` | `e7286733a9f54058c990fb1edcd90a2fe86786cac237fdd0ce37e78a529dbf46` |
| `benchmarks/operational/RecurrenceWorkload.roc` | `229e9314a1692215e1af6121f92c221bc917e08fffb3b9b32387e5e82fa579cd` |

The development source is based on `8539f5623387c555f8c109f1c394688b0fc01bc4`.
Raw reports `results-20261120T043957Z.json` and `results-20261120T044141Z.json`
under `.roc-time-tmp/benchmark-operational/` record every sample, paired
inputs, executable and file digests, and before/after timing controls.
Timing baselines and the per-workload export are stored locally under
`.roc-time-tmp/benchmark-baselines/`.

A subsequent cached run passed correctness replay, the timing control and all
coverage targets with the peer executables removed from their build paths.
Thirteen rows crossed their regression bands. The Roc executable digest was
identical across the repeat sessions and the cached run, so these observations
show timing variation with no change to the measured executable.

```sh
blueprint run benchmark-replay
blueprint run benchmark-operations-peers -- --fetch
blueprint run benchmark-operations-peers
blueprint run benchmark-operations
```

## Retained memory

The native roc-fuzz resource gate holds the caller slice or provider record
alongside the output at the measurement boundary. For sorted coverage, the
additional live bytes were 0, 136 and 69,992 at 0, 8 and 4,096 disjoint spans.
Loading each pinned zone added 9,224 live bytes after provider lookup. The
provider records in these fixtures use static storage. Both the entry and
exit live bytes and the peak are checked independently of cumulative
allocation traffic. [Reviewed resource baseline](../../tests/fuzz/baselines/retention.json)

```sh
blueprint run fuzz -- --operation run --targets retention --runs 100 --seconds 1 --seed 1
```
