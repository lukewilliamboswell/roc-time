# Starting native Apple M2 baseline

This capture establishes the starting point for the date and fixed-offset
portion of the [workload matrix](README.md#native-performance-matrix).
Coverage, named zones and recurrence are pending. This session establishes
starting values for investigation. Independent repeat sessions are needed
before setting timing tolerances or publishing throughput claims.

- 2026-11-20 UTC on a Mac14,2 with an Apple M2 and eight cores. macOS
  26.3.1(a), build 25D771280a, Darwin 25.3.0, battery power, native scheduler
  with no affinity override.
- Roc nightly `nightly-2026-11-18-a520eed`, LLVM `--opt=speed`,
  `--target=arm64mac`, `--no-cache`. Host built with Zig 0.17.0
  `ReleaseFast` and the benchmark libc allocator.
- Rust 1.95.0 (`59807616e`), Chrono 0.4.45 and Jiff 0.2.35, Cargo
  `--offline --locked --release --target aarch64-apple-darwin`. Go 1.26.5
  `darwin/arm64`, `-trimpath`, `CGO_ENABLED=0`.
  CPython 3.12.3 and ciso8601 2.3.3 from the hash-pinned source distribution,
  built with setuptools 69.5.1 and wheel 0.43.0.
- Package source base `8539f5623387c555f8c109f1c394688b0fc01bc4`.
  The capture used the working tree with the new comparison adapters and a
  concurrent NanoClockTime documentation edit. The adapter and corpus digests
  and peer binary identities are in the [peer baseline](peer-baseline.json).
- 100,000 operations per sample, 3 warmup batches, 9 samples per process,
  3 independently started process rounds with rotated sequential ordering.
  The spread is the observed minimum to maximum across the 27 samples.
- Per-case exact output and timed checksum verification passed for the two
  [reviewed profiles](expectations/manifest.json). Tempo was unavailable in
  the native comparison because no native runtime pin was admitted.

## Competitive rows

| Profile and workload | Roc median ns/op | Roc sample spread ns/op | Fastest eligible peer | Peer median ns/op | Ratio | Target |
|---|---:|---:|---|---:|---:|---|
| Gregorian construction | 2.656 | 2.653–2.854 | Jiff | 2.041 | 1.30× | Meets |
| Gregorian date to civil day | 3.807 | 3.796–4.085 | Chrono | 1.644 | 2.32× | Miss |
| Gregorian round trip | 12.529 | 12.455–13.135 | Chrono | 6.875 | 1.82× | Miss |
| Gregorian +17 civil days | 12.503 | 12.480–13.431 | Chrono | 3.510 | 3.56× | Miss |
| Six-digit fixed-offset ingest | 84.920 | 83.850–88.190 | Chrono | 23.228 | 3.66× | Miss |
| Whole-second fixed-offset ingest | 71.501 | 70.385–72.863 | Chrono | 17.973 | 3.98× | Miss |
| Six-digit canonical formatting | 65.969 | 65.003–67.273 | Chrono | 49.588 | 1.33× | Meets |
| Six-digit complete record processing | 152.022 | 150.257–155.919 | Chrono | 73.925 | 2.06× | Miss |

The +17-day operation in this capture adds to the bounded civil-day coordinate
and validates the resulting Gregorian date. The general checked arithmetic
entry point needs a separate measurement before acceptance.

## Diagnostic rows

| Profile | Stored date fields | Parse and observe local fields | Resolve prepared record |
|---|---:|---:|---:|
| Six digits | 1.393 ns/op | 75.631 ns/op | 9.165 ns/op |
| Whole seconds | 1.408 ns/op | 61.087 ns/op | 9.139 ns/op |

## Reproduction

Use the compiler and pinned subjects above on the reference environment and
select the benchmark CPython with `PYTHON_BENCH`.

```sh
blueprint run benchmark-peers -- --fetch --smoke
blueprint run benchmark-peers
blueprint run benchmark-comparison
```

The full comparison records all timing samples, compiler versions, targets,
workload and adapter hashes, preparation limits and availability in the
`.roc-time-tmp/announcement/arm64mac/results-*.json` report. The initial raw
report was `results-20261120T035604Z.json`.
