# roc-time and Chrono kernels

This opt-in benchmark compares a narrow semantic intersection through real public APIs. It is not a ranking of the libraries, a correctness gate for their full domains, or a zone/recurrence/coverage comparison. Run it without concurrent builds or tests.

```sh
# Once: acquire the exact Cargo.lock dependencies and run a bounded setup check.
ROC=/path/to/pinned/roc python3 scripts/benchmark_chrono.py --fetch --smoke
# Subsequent runs use Cargo --offline --locked.
ROC=/path/to/pinned/roc python3 scripts/benchmark_chrono.py
# Explicit alternative compiler backend; never combine these results with speed.
ROC=/path/to/pinned/roc python3 scripts/benchmark_chrono.py --roc-opt dev --smoke
```

The scoped `.cargo/config.toml` also directs editor/Cargo builds started in this crate to ignored temporary output.

Requires the repository-pinned Roc compiler, Zig 0.16.0, Python 3, Cargo/Rust with the native target installed, and the dependencies fetched once. Linux x86-64 uses musl for both executables; macOS arm64 uses the native Apple target. Other hosts fail explicitly. Build/download products and raw results stay under `.roc-time-tmp/`; no network is needed after dependencies and toolchains are installed. The Rust compiler version is recorded, not silently assumed equal to another run.

## Workloads

The checked-in 32-row corpus spans Gregorian 1900–2100, century/leap boundaries, pre-epoch dates, four nonzero asserted minute offsets, and exactly six fractional digits. No leap seconds, unknown offsets, timezone database, partial dates, month clamping or precision reduction occur. Chrono and roc-time have different behavior outside this intersection.

| Kernel | roc-time | Chrono | Included observation |
|---|---|---|---|
| `date_control` | stored date → fields checksum | stored date → fields checksum | year/month/day checksum; no construction or coordinate conversion |
| `date_to_day` | Gregorian → civil-day | date → days-from-CE, shifted to POSIX day | POSIX day + 1,000,000 checksum |
| `construct` | checked `GregorianDate.from_fields` | `NaiveDate::from_ymd_opt` | year/month/day checksum |
| `roundtrip` | Gregorian → civil-day → Gregorian | date → days-from-CE → date | year/month/day checksum |
| `add_days` | civil-day coordinate +17 → Gregorian | `checked_add_days(Days::new(17))` | year/month/day checksum |
| `parse` | `OffsetTimestamp.parse` + `boundary` | `DateTime::parse_from_rfc3339` + `timestamp_micros` | bounded microsecond checksum |
| `resolve` | stored `OffsetTimestamp.boundary` | stored `DateTime::timestamp_micros` | bounded microsecond checksum |
| `format` | stored `OffsetTimestamp.to_text` | stored `to_rfc3339_opts(Micros,false)` | all output bytes summed |
| `end_to_end` | parse + canonical text | parse + canonical text | all output bytes summed |

The `resolve` workload compares public representation operations on narrow arrays of stored timestamps. Chrono already stores the resolved coordinate; roc-time preserves the declared local fields and offset and computes the coordinate when requested. The checksum matches `parse`. Do not subtract `resolve` measurements from `parse` to infer parser-only latency: the representations, optimization opportunities and combined operation paths differ.

The day calculation is exact calendar-day addition on date-only values. It is not duration arithmetic on a zoned timestamp. All chosen dates and their +17-day results fit both providers. The parse workload explicitly includes resolution of the supplied fixed offset to the shared POSIX microsecond coordinate; formatting starts from preconstructed values. End-to-end means the text adapter pipeline, not process startup or corpus loading.

## Measurement and validation

Each process loads the same runtime argv corpus and constructs its stored dates/timestamps before sampling. Kernels cycle over retained immutable inputs; outputs are transient, with no mutation or cursor sharing. Before sampling, both implementations project narrow input arrays: dates for date/control/conversion kernels, fields for construction, strings for parsing/end-to-end and timestamps for formatting. Date iterations therefore do not copy or retain unrelated strings from verification records. Input preparation is excluded from measurements; the separate `construct` workload measures checked date construction itself. Each sample contains the requested number of operations, including indexing, checked API calls, checksum accumulation and formatting output disposal. Workload selection occurs before warmups and timestamp reads; each branch calls the shared sampling loop with a fixed operation. No per-item string dispatch occurs. Rust uses generic closures and `black_box` on kernel inputs and its result. Roc brackets each kernel with opaque external hosted identity calls on the iteration count and checksum, preventing reuse across samples or moving computation outside the timestamps. These two calls per sample are included in measured time; they do not allocate. Both implementations also publish checksums through observable output. No checksum is discarded by the runner.

The reported ns/op is therefore whole-loop cost per item, not isolated API latency; harness overhead matters particularly for tiny date kernels. `date_control` exposes the cost of stored-date field extraction and the surrounding loop, while `date_to_day` observes forward conversion without inverse conversion. The fixed day-checksum shift is nonnegative throughout the checked corpus. These are contextual controls: do not subtract their timings to claim isolated API latency. Representation and compiler optimization can differ between workloads.

Default settings are 100,000 operations per sample, three warmups and nine samples. `--smoke` uses 1,000 operations, one warmup and three samples to verify setup; these short noisy samples do not support performance conclusions. In-process monotonic timestamps bracket kernels, excluding startup, warmup and reporting. Timer reads are checked for nondecreasing values; the Roc clock observation is verified to allocate no Roc memory. Runs are sequential and language order alternates by workload. The runner records every sample plus compiler, target, machine, revision/dirty state and corpus/lock hashes. Medians are descriptive, with no significance claim or timing threshold.

`corpus.jsonl` expectations come from Python's independent `datetime` date/offset arithmetic, not either measured library. Its fixed generation order combines dates `1900-02-28`, `1969-12-31`, `1970-01-01`, `1999-12-31`, `2000-02-29`, `2000-03-01`, `2024-02-29`, `2100-02-28` with offsets `+05:30`, `-03:30`, `+01:00`, `-12:00`. The exact hour/minute/second/microsecond generation is preserved in [generate_corpus.py](generate_corpus.py), which writes only to stdout for deliberate reviewed refreshes. Ordinary replay never regenerates or writes the corpus. Every run revalidates checked-in expectations independently, then checks each binary's full canonical text, day coordinate and microsecond coordinate for every row before timing. Every timed checksum is independently predicted. A deliberately incorrect checksum verifies that the harness rejects mismatches. Shared assumptions are Gregorian civil dates, POSIX non-leap coordinates and explicit offsets; this corpus says nothing about unsupported interpretations.

Both benchmark executables use libc allocation on the matched target. The isolated Roc host is built with `-Dbenchmark-allocator=true`; default resource fixtures retain their DebugAllocator and leak checks. Roc still pays its ABI allocation headers, reference counting and counter increments, while Rust uses its System allocator. These remaining runtime costs are included; this is not a compiler-only comparison. Benchmark platform artifacts use a separate target directory and do not overwrite resource-fixture inputs.

No allocation count is compared between languages, and no requested-byte counter is described as live memory. Backend, allocator, compiler and representation differences are part of the implementation under measurement. Inspect the raw JSON and workload definition before interpreting a ratio.

## Dependency and API provenance

Chrono is pinned to **0.4.45**, with default features disabled and only `std` enabled. `Cargo.lock` pins the transitive crates and registry SHA-256 checksums; no local-zone or clock feature is enabled. The packaged `.cargo_vcs_info.json` identifies upstream revision [`170338250e836976a211e64728ec956e45e78a39`](https://github.com/chronotope/chrono/tree/170338250e836976a211e64728ec956e45e78a39). The crate checksum is `1aa79e62e7697b8e29b513a68abacf485adcd1fe8284a4316c5ae868e6633327`.

Primary API documentation reviewed 2026-09-06:

- [Chrono 0.4.45 features and supported calendar](https://docs.rs/chrono/0.4.45/chrono/).
- [DateTime parsing, timestamp microseconds and explicit fractional formatting](https://docs.rs/chrono/0.4.45/chrono/struct.DateTime.html).
- [NaiveDate checked construction and day calculations](https://docs.rs/chrono/0.4.45/chrono/struct.NaiveDate.html).

The benchmark calls these APIs; it does not adapt Chrono implementation code. Dependencies retain their upstream license notices in the fetched crate sources.
