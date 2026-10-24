# Empty-record dictionary values hang optimized builds

On macOS arm64 with `nightly-2026-10-23-18478ff`, the root passes `roc check`,
interprets and builds with `--opt=dev`, printing `True`. Building it with
`--opt=speed`, the `roc build` default, never finishes. `nightly-2026-10-21-5349569`
builds and runs it in every mode. The defect needs no roc-time code.

```sh
"$ROC" check tests/compiler_repro/unit_value_dict_build/main.roc
"$ROC" tests/compiler_repro/unit_value_dict_build/main.roc
"$ROC" build tests/compiler_repro/unit_value_dict_build/main.roc --opt=dev --output=.roc-time-tmp/unit-dict-dev
"$ROC" build tests/compiler_repro/unit_value_dict_build/main.roc --opt=speed --output=.roc-time-tmp/unit-dict-speed
```

`Seen` inserts a key with the value `{}` and looks it up. The
[Bool control](bool_value/main.roc) changes only that value to `True`. It builds
and executes in dev and speed modes, printing `True`.

Inside a larger roc-fuzz target the same shape instead crashed the compiler
with SIGSEGV during `lir_gen` with `--fuzz --opt=speed`, or hung without
`--opt`. `EventCollection.from_entries` tracked seen identities in a
`Dict(id, {})`; it now uses a `Set(id)`, which builds on both nightlies and
keeps the same duplicate-identity semantics. The `tests/events` fuzz target
exercises that path.

Reported upstream as [roc-lang/roc#12559](https://github.com/roc-lang/roc/issues/12559).
This is a known-failure reproducer. Recheck the root and its control when
changing the compiler pin.
