# Native Gregorian and fixed-offset results

All eight competitive Gregorian and fixed-offset rows met 1.50× in both
fresh peer sessions on 2026-11-20 UTC. The six-digit RFC 3339 workload
parsed complete fixed-offset inputs and returned exact signed POSIX
microseconds at 41.8 and 42.8 million timestamps per second. These results
cover this part of the matrix. [Workload matrix](README.md#native-performance-matrix)
[Coverage, zone and recurrence results](native-operational.md)

Apple M2 MacBook Air (Mac14,2), macOS 26.3.1(a) build 25D771280a,
battery power, native scheduling. Roc `nightly-2026-11-18-a520eed`,
LLVM speed, `arm64mac`, Zig 0.17.0. Rust 1.95.0, Chrono 0.4.45 and Jiff
0.2.35, Go 1.26.5, CPython 3.12.3 and ciso8601 2.3.3. Each session uses
three process rounds with three warmups and nine 100,000-operation samples
per subject in each round. [Starting baseline and build flags](starting-native-m2.md)

| Competitive workload | Roc ns/op, A | Fastest peer ns/op, A | Ratio, A | Roc ns/op, B | Fastest peer ns/op, B | Ratio, B |
|---|---:|---:|---:|---:|---:|---:|
| Gregorian validated construction | 2.732 | 2.058 Jiff | 1.33× | 2.645 | 2.039 Jiff | 1.30× |
| Gregorian date to civil day | 2.125 | 1.669 Chrono | 1.27× | 2.088 | 1.685 Chrono | 1.24× |
| Gregorian round trip | 10.044 | 6.920 Chrono | 1.45× | 9.841 | 6.865 Chrono | 1.43× |
| Gregorian checked +17 civil days | 3.220 | 3.469 Chrono | 0.93× | 3.205 | 3.463 Chrono | 0.93× |
| Six-digit fixed-offset ingest | 23.929 | 23.435 Chrono | 1.02× | 23.348 | 23.208 Chrono | 1.01× |
| Whole-second fixed-offset ingest | 24.261 | 18.162 Chrono | 1.34× | 24.347 | 18.083 Chrono | 1.35× |
| Six-digit canonical formatting | 67.552 | 49.914 Chrono | 1.35× | 66.808 | 49.273 Chrono | 1.36× |
| Six-digit complete record processing | 99.501 | 73.930 Chrono | 1.35× | 98.338 | 73.127 Chrono | 1.34× |

The source is the Gregorian and timestamp implementation accompanying this
report, based on `8539f5623387c555f8c109f1c394688b0fc01bc4`. Raw session reports
`results-20261120T040957Z.json` and `results-20261120T041051Z.json` in
`.roc-time-tmp/announcement/arm64mac/` record the exact source and binary
digests, options, timings, and per-profile verification. The retained peer
cache uses the independent starting peer measurements. Three later Roc-only
sessions produced the regression baseline and timing-control observations.
[Peer cache](peer-baseline.json) · [Roc baseline](roc-baseline.json)

| Measured source file | SHA-256 |
|---|---|
| `package/OffsetTimestamp.roc` | `1f5d5598fe39620aef50ce658e4d882ecd2fbed29b7335c084ffd0f43c20a3a3` |
| `package/GregorianDate.roc` | `99c9bef4d21cd574a8b5f5ee5e1bf73b05fd8d044c72ced9439203b7f6f87cdf` |
| `package/Calendar.roc` | `4fe5f1c0c7c072731a09bc78459c1899dd34c26067e8bf63dfcfe6323a799083` |
| `benchmarks/chrono/main.roc` | `fd2649da252b95085d4648605fd6062598c0cebc40da3344f375ae35d620c022` |
| `benchmarks/chrono/Benchmark.roc` | `9bb336df8ad592a0db2fb5fbdc4318339dd650228b2de5d023f179f5786e7fa8` |

The numeric-offset scanner uses checked vector loads, lane validation and
base-ten dot products. Both scanners share calendar, clock, and offset
validation. Native dev and speed resource tests counted zero scoped parser
allocations for 12 direct, aliased and sliced cases. The wasm32 LLVM fixture
checks exact coordinates for three runtime six-digit inputs in dev and speed
builds. It observes zero allocation calls and rejects a deliberately
allocating control. Run it with `blueprint run check-wasm-timestamp-resource`.

With the pinned peers installed, run the two fresh sessions independently
using the same native reference settings.

```sh
blueprint run benchmark-replay
blueprint run benchmark-peers
blueprint run benchmark-peers
blueprint run benchmark-comparison
```
