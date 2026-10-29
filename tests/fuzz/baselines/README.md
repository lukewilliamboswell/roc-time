# Allocation observations

These roc-fuzz 0.5.0 baselines cover the complete source-declared retained input
inventory for all fourteen semantic targets. Each input retains its original
corpus bytes and name; hashes are checked in baseline entries and replay reports.
The platform/dependency revision and archive SHA-256 are in [dependency.json](../dependency.json).

Scope: `x64musl`, LLVM `--opt=speed --fuzz`, profile `speed`, compiler
`nightly-2026-10-28-bad769b`, metric version `roc-fuzz-allocations/1`. Each named
property executes once in a fresh process. Counters cover the platform's
`$property` region, including the property's independent models and assertions;
they are not isolated production API costs. Requested bytes are cumulative,
while entry/exit/peak live bytes describe the region's tracked allocations.
Owned input collections can be live at region entry and consumed by the property;
coverage/event examples therefore release entry allocations rather than ending
with the same live count. All accepted examples end with zero tracked live
allocations. These observations do not establish general allocation bounds, retained process
memory, portability, or performance. Existing native fixture resource assertions
remain a separate gate.

Intentional acceptance, after reviewing property inputs and observations:

```sh
ROC_NIGHTLY=/absolute/path/to/roc blueprint run fuzz -- --operation accept
ROC_NIGHTLY=/absolute/path/to/roc blueprint run fuzz -- --operation all --runs 100 --seconds 1 --seed 1
```

Ordinary replay/search checks never accept changes. Review baseline diffs rather
than automatically refreshing them for a compiler update. Add a reviewed entry
for another host/profile before claiming that combination passes. Disposable
quality reports and supervisor/native logs remain under `.roc-time-tmp/fuzz/`.
The failure lifecycle includes real changed-baseline and missing-baseline
controls; the first must stop exploration and fail, and the second must be
rejected by repository policy despite the platform's successful exit status.
