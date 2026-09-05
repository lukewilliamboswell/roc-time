# Nested record equality compiler crash

On `nightly-2026-09-04-c125b82`, Apple Silicon macOS, this dependency-free
reproduction crashes compilation with SIGSEGV (exit 139):

```sh
"$ROC" check tests/compiler_repro/nested_record_equality/main.roc
"$ROC" build tests/compiler_repro/nested_record_equality/main.roc --output=.roc-time-tmp/nested-equality
```

The check succeeds. The build crashes while compiling equality of two records
containing a list of nominal values and a Boolean. Expected output is `True`.
The input depends on the argument count, so this is not solely a unit-test or
constant-input evaluation failure. No temporal operations or package imports
are involved.

The control changes only whole-record equality to equality of each field:

```sh
"$ROC" build tests/compiler_repro/nested_record_equality/fieldwise/main.roc --output=.roc-time-tmp/fieldwise-equality
.roc-time-tmp/fieldwise-equality
```

The control builds and prints `True`. TimedRecurrence's BYSETPOS resumption test
compares each result field, including the original source-label list, to retain
its full assertion without triggering this compiler defect. The independent
native recurrence probe also printed both expected source labels intact.

This is a known-failure reproduction, not a passing portability gate. No upstream
report has been sent. Recheck it when updating the pinned compiler.
