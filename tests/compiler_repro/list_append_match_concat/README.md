# List strings lost across loop and match updates

On `nightly-2026-09-06-d85e877`, Linux x86_64, `main.roc` loses an appended
string during its second iteration. Interpreter, native dev and native speed
all reproduce the same wrong list. No roc-time imports or custom platform are
involved. `Str.inspect` already displays the corruption before JSON encoding.

Run with the pinned compiler:

```sh
"$ROC" tests/compiler_repro/list_append_match_concat/main.roc -- 2
"$ROC" build tests/compiler_repro/list_append_match_concat/main.roc --opt=dev --output=.roc-time-tmp/append-match-dev
.roc-time-tmp/append-match-dev 2
"$ROC" build tests/compiler_repro/list_append_match_concat/main.roc --opt=speed --output=.roc-time-tmp/append-match-speed
.roc-time-tmp/append-match-speed 2
```

Expected final JSON:

```json
["coordinate","1","2","source-0","after","coordinate","2","source-1","after","coordinate","2"]
```

Observed final JSON:

```json
["coordinate","1","2","source-0","after","coordinate","2","source-1","","coordinate","2"]
```

The loop appends a source string, then updates the same list inside a
three-branch match using `append(...).concat(...)`. One entry works. Two entries
lose the second `after` string; 64 entries lose 125 source/tag strings. The
coordinate/value strings introduced by the final concat remain intact. A
single-branch version and a direct loop without the match did not reproduce.
This isolates a compiler/runtime defect; it does not identify its internal
lowering or reference-counting cause.

The equivalent [hoisted control](hoisted/main.roc) constructs each ending's
fields in a pure match and performs one outer list update. Run/build that root
with the same commands to compare. It preserves the expected list in all three
modes. This is the equivalent source shape used by `PersistenceEndings`; no
temporal semantics or archive bytes are changed to accommodate the defect.

This is a known-failure compiler reproducer, not a passing package semantic
test. Before removing the equivalent source form after a compiler update,
verify both roots and the public schedule archive resource gate. No upstream
report has been sent.
