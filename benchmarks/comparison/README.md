# Cross-language temporal benchmarks

Run the real public APIs on a checked shared domain, with independent expected
results. This is an opt-in Linux x86-64 throughput comparison. It does not measure
complete applications, memory, recurrence, zones, or coverage, and does not
establish a fastest-library ranking.

```sh
# Requires the compiler pinned in package/main.roc, Zig 0.16.0, Rust 1.95.0
# with x86_64-unknown-linux-musl, Go 1.26.5, CPython 3.12.3 + pip, and Docker.
ROC=/path/to/pinned/roc python3 scripts/benchmark_comparison.py --fetch --smoke
# Offline dependency reuse; builds finish before comparative measurements.
ROC=/path/to/pinned/roc python3 scripts/benchmark_comparison.py --cpu 2
# A single explicitly selected domain:
ROC=/path/to/pinned/roc python3 scripts/benchmark_comparison.py --profile seconds --cpu 2
```

Choose an available CPU (`os.sched_getaffinity(0)`), preferably with an idle SMT
sibling. CPU affinity does not establish exclusive CPU access, fixed frequency,
or freedom from thermal throttling. Do not run other builds/tests during timings.
The runner never changes governor settings or system configuration.

`--fetch` downloads the hash-pinned CPython wheel, exact Tempo source and locked
Hex/Cargo dependencies. Everything downloaded/built and every raw result stays
under `.roc-time-tmp/`. Tempo runs in a digest-pinned Linux container on the host
CPU, with one BEAM scheduler (`+S 1:1`), no network and no application startup.
The tested pure Tempo operations need no running applications; this also avoids
unrelated ephemeris/timezone setup. Docker/BEAM startup is outside the timer.
Other programs run directly on the host. Container/runtime differences remain
part of the measurement environment.

## Libraries and prior art

- Rust **Chrono 0.4.45** reuses the [existing reviewed harness](../chrono/README.md).
  **Jiff 0.2.35** supplies a performance-focused alternative. These are selected
  comparators, not a measured popularity ranking or exhaustive fastest search.
- Go uses standard **time** with `time.Local = time.UTC` to prevent host-zone
  lookup/reuse during fixed-offset parsing; Python uses standard **datetime** and
  **ciso8601 2.3.3**, whose implementation is a C extension. ciso8601 rows measure
  parsing plus Python observation; its datetime outputs use the standard library
  for subsequent arithmetic/formatting.
- **Tempo 1.6.4**, by Kip Cole and contributors, uses revision
  `e8a074ed1efed6a0f78b87d900fc4cb0c4156278`. Its own `mix.lock` is integrity-checked;
  upstream code and Apache-2.0 notices remain in the fetched checkout.

Relevant existing suites reviewed when choosing workloads:

| Suite | Relevance and differences |
|---|---|
| [Jiff Criterion suite](https://github.com/BurntSushi/jiff/tree/ab6e8c83462e9b6d0dfe33f9cb70583d3d82049b/bench) | Compares Jiff, Chrono and Rust time. Separates civil dates, timestamps, parsing, printing and zones. Its `date/add_days` varies within/across-year additions; ours retains the existing +17-day corpus and is not an exact port. |
| [Go time benchmarks](https://github.com/golang/go/blob/go1.26.5/src/time/time_test.go) | Separate RFC 3339 UTC/offset parsing and formatting. We include the offset example with its nine-digit fraction explicitly removed in the whole-second corpus. The UTC fast path is not measured here. |
| [ciso8601 comparison](https://github.com/closeio/ciso8601/tree/aff55974fe41e610204f835600f122c9c569f344/benchmarking) | Uses timeit and compares Python parsers with/without offsets. Its exact aware input `2014-01-09T21:48:00-05:30` is included in the second corpus. Our timestamp-resolution and checksum work is additional, so results must not be compared directly with its published parser timings. |
| [Tempo benchmarks](https://github.com/elixir-tempo/tempo/tree/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/bench) | Recurrence against ical, and interval-set construction/point queries. Those are separate semantic workloads, not implemented by this date/timestamp comparison. |

The adapters are original benchmark code calling public APIs. No upstream
implementation or benchmark code is copied. The upstream examples above are
input facts, with the stated adaptations. No universal cross-language benchmark
standard is claimed. Benchmark frameworks (Criterion, timeit, Benchee, Go testing)
provide measurement machinery, not a common semantic workload specification.

## Domains and observations

Requirements R01, R06, R08, R14–R16 apply. The realistic caller parses fixed-offset
records, calculates Gregorian deadlines, resolves POSIX coordinates and formats
records. Inputs are valid Gregorian dates in 1900–2100, all results fit, and no
host timezone, leap seconds or precision reduction is involved in execution.
Invalid-input behavior differs between libraries and is not timed.

`microseconds` uses the [32-case independent corpus](../chrono/corpus.jsonl):
exactly six fractional digits, century/leap/epoch boundaries, four nonzero
minute offsets. `seconds` uses the same cases without fractions, plus the two
upstream inputs described above (34 cases). Their numerical expectations are
computed with Python datetime using exact integer arithmetic. The deliberate Go
adaptation is `2020-08-22T11:27:43.123456789-02:00` to
`2020-08-22T11:27:43-02:00`; it is a different instant, not a rounded benchmark
result. The [generator](generate_seconds.py) prints expectations for deliberate
reviewed updates; ordinary replay independently checks, never regenerates them.
The Python oracle is independent of Roc/Rust/Go/Tempo but shares implementation
with the Python comparator; it is not independent evidence for Python itself.

**Tempo fractional negative-offset limitation:** the pinned version raises
`Tempo.ParseError` for `1900-02-28T01:13:17.027183-03:30`. The runner verifies that
specific diagnostic, records it, and omits Tempo from the entire microsecond
profile. It does not filter problematic rows or rewrite inputs for Tempo.
All seven comparators participate in the whole-second profile where supported.
A change to this limitation fails visibly and requires review.

Workload meanings and Roc/Chrono calls are detailed in the
[original workload table](../chrono/README.md#workloads).

| Workload | Additional adapters |
|---|---|
| `date_control` | Stored dates → year/month/day checksum; contextual loop/field-access control. |
| `construct` | Validated Gregorian construction; Go `time.Date` additionally checks returned fields because it normalizes invalid input. Tempo `new!`, Jiff `Date::new`, Python `date`. |
| `date_to_day` | Python ordinal conversion; Go date → explicit UTC midnight → POSIX day; Tempo `to_date` → Elixir Gregorian day. No Jiff row yet. |
| `roundtrip` | Python ordinal round trip; Go date → UTC day → date. No Tempo/Jiff row. |
| `add_days` | Go `AddDate`, Python date + timedelta, Tempo `shift` with a prepared 17-day duration, Jiff checked Span addition. Every result is observed as date fields. |
| `parse` | Parse → signed POSIX microseconds → Euclidean checksum. Tempo uses `parse_datetime!` then `to_date_time` and `DateTime.to_unix`; Python uses exact timedelta components, never float `timestamp()`. Jiff uses `parse_timestamp`. |
| `resolve` | Stored representation → microseconds. Go/Jiff already store resolved coordinates; Tempo/Roc preserve local fields. This is not equal internal work, nor isolated parser cost. |
| `parse_only` | Parse → local fields/clock/offset checksum; see the original caveat about internal resolution. Python/Go included; no Tempo/Jiff row. |
| `format`, `end_to_end` | Canonical text with six digits and original numeric offset; checksum visits all bytes. Python includes ASCII encoding. Only microsecond profile: Roc preserves supplied precision, whereas the other adapters force six digits. Tempo emits a different native syntax and is omitted. No Jiff formatter timing yet. |

Parsing inputs, stored values, narrow date arrays and construction fields are
prepared before sampling. Retained inputs are immutable; transient outputs are
consumed and discarded. No streaming, retained-slice or allocation claims follow.
The fixed 17-day durations are prepared before sampling in Python and Tempo;
Rust can constant-fold their construction. Construction kernels include result observation. All kernels are bounded O(1)
for these fixed-sized inputs; formatting includes bounded output creation.
Go/Python/Tempo dispatch their selected operation through a function call; Rust
closures and Roc can specialize. Whole-loop ns/op includes these runtime and
observer costs. Do not subtract controls or compare them as bare API latency.

## Measurement protocol

Every adapter verifies each input's civil day and exact microsecond coordinate
before timing. Where canonical RFC text is supported it is compared in full;
Tempo verifies numerical outputs only. Every timed sample must have the predicted
checksum and a positive elapsed time. Wrong checksums, missing/extra/malformed
records and nonpositive times have executable rejection controls.

Defaults: 100,000 items/sample, 3 warmup batches, 9 samples/process, 3 independent
process rounds. Libraries run sequentially, with deterministic rotated/reversed
order across workloads/rounds. These are descriptive medians; no significance
claim is made from the nested samples. Increase the preselected budget before a
study, not repeatedly until a desired ranking appears. `--smoke` uses 1,000 items,
one warmup, three samples and one round; it proves setup only.

In-process monotonic clocks exclude build, process startup, preparation and
printing. Optimized Roc/Rust use the reviewed opaque/black-box barriers. Both
use musl on x86-64; Go uses `CGO_ENABLED=0`, Python and BEAM use their installed
runtimes/allocators. The report records pins, source/corpus hashes, executable
versions, CPU/affinity, source revision/dirty state, every sample and known
limitations. Raw JSON remains ignored; this README intentionally contains no
performance results.
