# Cross-language temporal benchmarks

The reference environment is the native Apple M2 MacBook Air (Mac14,2).
The matrix covers Gregorian dates, fixed-offset timestamps, coverage, named
zones and recurrence through public APIs with independent expectations.
The first native capture and the two fresh date and timestamp confirmations
have separate reports. [Starting baseline](starting-native-m2.md) ·
[Gregorian and fixed-offset results](native-date-timestamp.md) ·
[Coverage, zone and recurrence results](native-operational.md)

```sh
ROC_NIGHTLY=/path/to/roc blueprint run benchmark-replay
ROC_NIGHTLY=/path/to/roc blueprint run benchmark-peers -- --fetch --smoke
ROC_NIGHTLY=/path/to/roc blueprint run benchmark-peers
ROC_NIGHTLY=/path/to/roc blueprint run benchmark-operations-peers -- --fetch
ROC_NIGHTLY=/path/to/roc blueprint run benchmark-comparison
```

`PYTHON_BENCH` selects the measured CPython executable (default `/usr/bin/python3`).
Peer runs require native Rust 1.95.0, Go 1.26.5 and CPython 3.12.3.
On macOS, the hash-verified ciso8601 source archive builds with the selected
CPython and its preinstalled packaging tools. On Linux, the hash-verified
wheel is extracted directly. Tempo is currently available in the separate
Linux environment and is reported as unavailable in native runs.

On Linux, choose an available CPU (`Cpus_allowed_list` in `/proc/self/status`), preferably with an idle SMT
sibling. CPU affinity does not establish exclusive CPU access, fixed frequency,
or freedom from thermal throttling. Do not run other builds/tests during timings.
The runner applies affinity to each measured child and Tempo container. It never
changes governor settings or system configuration.

`--fetch` downloads the hash-pinned ciso8601 artifact and locked Cargo dependencies.
Linux setup also downloads exact Tempo source and locked Hex dependencies.
Downloads, builds and raw results stay under `.roc-time-tmp/`.
Tempo runs in a digest-pinned Linux container on the host
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
| `format`, `end_to_end` | Canonical text with six digits and original numeric offset. The checksum visits all bytes. Complete records also observe the exact signed POSIX coordinate. Python includes ASCII encoding. These rows use the six-digit profile. |

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
use the native Apple target on the reference host and musl on Linux x86-64.
Go uses `CGO_ENABLED=0`, Python and BEAM use their installed
runtimes/allocators. The report records pins, source/corpus hashes, executable
versions, CPU/affinity, source revision/dirty state, every sample and known
limitations. Raw JSON remains ignored; this README intentionally contains no
performance results.

## Native performance matrix

Use the native scheduler with no affinity override. Record the CPU, model,
OS build, power and scheduling settings in the reference report. Each
competitive cell has a 1.50× target and a reviewed roc-time baseline.

| Operation | Profiles | Competitive peers |
|---|---|---|
| `construct` | Gregorian fields from the 32-case corpus | Chrono, Jiff, Go, Python datetime |
| `date_to_day` | Gregorian dates from the 32-case corpus | Chrono, Go, Python datetime |
| `roundtrip` | Gregorian date → day → checked Gregorian date, 32 cases | Chrono, Go, Python datetime |
| `add_days` | Gregorian date +17 across month, leap and century boundaries, 32 cases | Chrono, Jiff, Go, Python datetime |
| `parse` | 32 six-digit inputs, 34 whole-second inputs, including negative coordinates and both signs of offset | Chrono, Jiff, Go, Python datetime and ciso8601 for both profiles. Tempo qualifies for whole seconds in the separate Linux environment. |
| `format` | 32 six-digit inputs, canonical text with the original offset | Chrono, Go, Python datetime |
| `end_to_end` | 32 six-digit inputs, exact resolution and canonical text | Chrono, Go, Python datetime and ciso8601. Observe both the signed coordinate and every byte. |
| `date_control`, `parse_only`, `resolve` | Date fields or representation-specific staging, both input profiles where implemented | Diagnostic measurements |

The date corpus is shared with ingest so both profiles can replay the same
public benchmark root. Native comparative date claims use the 32-case profile.
Construct observes all returned fields. Convert observes the signed civil day
and round trip and addition observe all resulting fields. The exact coordinate
is observed by ingest and the text checksum visits every byte. Preparation
occurs before timing. These are bounded constant-cost operations over the
declared fixed-size inputs. Invalid Gregorian fields, unrepresentable calendar
days, malformed timestamps and unsupported leap seconds use the corresponding
package and public fuzz checks outside the throughput samples.

### Coverage, zone and recurrence profiles

Coverage uses signed I64 half-open ranges in repeating 16µs blocks. It uses
zero, eight and 4,096 raw spans, with sparse, touching-dense and disjoint
pairs. It retains prepared input across iterations. The query profiles use
late misses, one hit and up to 64 hits. The hosted resource gate also checks
a retained source slice with zero allocations for containment and folding.

The coverage peer is Rust Rangemap 1.7.1. It coalesces touching ranges into
canonical half-open coverage, compares the same endpoints and emits the same
ordered full members. Both adapters produce a reusable coverage value for
set operations and explicitly materialize overlap results in that profile.
Both traverse all requested matches for the fold. Sorted construction
checks input order in both adapters. The reversed-order rejection row is
diagnostic. The remaining coverage rows have separate 1.50× targets.
An independent bounded point model checks each profile before sampling.
[Rangemap source and API](https://docs.rs/crate/rangemap/1.7.1/source/README.md)

Zones and recurrence use absolute timings pending peers with matching
transition data, ambiguity results, and resumable work contracts.
The independent zone cases use both fold positions with CPython zoneinfo
and accept exact local round trips against the pinned 2026e wheel.
The recurrence cases use explicit Gregorian occurrence lists.

| Caller operation and timed boundary | Finite inputs and observations | Expected cost and independent expectation |
|---|---|---|
| Import sorted availability, `Coverage.from_sorted_spans` | 0, 8 and 4,096 spans. Touching runs, disjoint spans and rejected reversed input order. Observe every canonical endpoint or `UnsortedInput`. | Linear validation and coalescing. Independent point model. |
| Import unordered availability, `Coverage.from_spans` | Same sizes and extents in reversed order. Observe all canonical endpoints. | Sort then linear coalescing. Independent point model. |
| Combine availability, `Coverage.union`, `intersection`, `difference` | Two sets with matching input size. Sparse overlap, dense touching inputs and disjoint pairs. Observe all canonical endpoints. | Linear in total inputs and outputs. Independent point model. |
| Check appointment availability, `Coverage.contains` | Same sizes, with a late start hit and an exclusive-end miss. Observe membership. | Logarithmic seek, zero result allocations. Independent direct half-open endpoint tests. |
| Search overlapping appointments, `Coverage.fold_overlaps` and `overlapping_spans` as separate rows | Same sizes, queries near the last span returning 0, 1 or up to 64 ordered whole spans. Observe every endpoint. | Logarithmic seek plus matches. Independent direct half-open overlap test. |
| Look up or load named-zone rules, `Database.get` and `ZoneRules.from_database` separately | Pinned New York and Lord Howe records. Observe transition counts. Reject a corrupted schema. | Search the static name inventory or admit transitions in linear work. Known inventory counts from the pinned asset. |
| Look up and resolve warm zone rules, `ZoneRules.offset_at` and `resolve` as separate rows | Same pinned zones. Ordinary times and both sides of gap/fold endpoints, plus an out-of-validity failure. Observe offset or status and every ordered exact boundary. | Lookup seeks transitions. Resolution also visits applicable segments. Use pinned zone oracle expectations including non-hour transitions. |
| Start a series, `DateRecurrence.new` | Daily, monthly and distant profiles. Observe the validated anchor and exclusions. Reject count zero. | Construction independent of logical window length. Fixed Gregorian declaration fixtures. |
| First consumption and resumption, `DateRecurrence.Cursor.next` | Daily and monthly short windows and one ending in year 2,000,000,000. Observe exact occurrence, work and buffered count. Time the initial cursor and the independently prepared saved cursor separately. | One buffered occurrence, with 64–65 daily steps, 256–257 monthly steps, and 8–9 steps for the distant profile. Fixed expected dates at leap and month boundaries. |
| Evaluate a query window, `DateRecurrence.Cursor.collect` | Daily and monthly late-window cases with exclusions, plus a distant window that returns `Limited`. Observe all dates, status and work. | Same candidate budgets, four buffered and four output dates. Explicit independent occurrence lists and a bounded incomplete case. |

Coverage alternates two prepared coordinate sets translated by a microsecond.
Each adapter checks both independently, selects the timed input through an
opaque call and consumes the complete result through the same checksum.
Hosted resource assertions cover retained input slices and allocation separately.
Run supported Wasm resource checks as a separate environment.

The operational matrix uses three rounds, nine samples and three warmups.
Each sample contains 300 operations for large coverage sets and zone setup,
1,000 for recurrence, and 10,000 for the other profiles. The replay gate
checks the same independent expectations with smaller bounds. Zone and
recurrence reports currently record absolute elapsed time per operation.
