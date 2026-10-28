# Local appointments across a clock change

A UTC-only recurrence test can miss a local appointment being removed twice,
losing its original identity, or receiving the wrong ending after a clock change.
These tests compose those operations through the public scheduling API.
They cover R07, R09, R11–R12 and R15–R16.

Run the deterministic gate with the package compiler selected explicitly:

```text
blueprint shell
ROC_NIGHTLY=/path/to/roc roc-stable scripts/test_local_recurrence.roc
```

`blueprint run check` includes this gate. It runs the interpreter,
then builds each native fixture once for `dev` and `speed`. Replay reads the
checked-in corpus; it does not generate or approve new expectations.

## What the corpus says

`../oracles/local-recurrence-v1.tsv` contains 108 independently modeled cases:

| Input | Values |
| --- | --- |
| Offset change at 1970-01-01 02:00Z | −60, −30, +30, +60 minutes |
| BYSETPOS | −1, omitted, +1 |
| RRULE termination | COUNT=3, inclusive local UNTIL, inclusive UTC UNTIL |
| Exclusions | none, original 02:30 label, selected 02:30Z boundary |

The daily source candidates are 01:30, 02:30, 03:30 and 04:30. Each case also
adds 03:30 explicitly and gives it a PERIOD ending at 05:30; a second PERIOD
adds 05:30 with a two-hour coordinate duration. A third PERIOD adds or overrides
01:30 with an explicit local 02:30 ending, so ending interpretation itself
crosses a fold or gap. The default lasts one hour.
Exclusions apply after recurrence COUNT and selection; they do not replenish
COUNT. PERIOD additions remain independent of RRULE termination. Local UNTIL
uses the native declaration because the zoned RFC adapter requires UTC UNTIL.

Each row starts with `shift/position/termination/exclusion`, followed by a tab
and ordered observations separated by commas. Each observation has six
colon-separated fields:

```text
original-source-minute:UTC-start-minute:UTC-end-minute:ending-kind:start-adjusted:end-adjusted
```

Minutes are signed offsets from 1970-01-01 midnight in the relevant coordinate.
Ending kinds are `0` for the default coordinate hour, `1` for the explicit
local 05:30 ending, `2` for the two-hour coordinate ending, and `3` for the
explicit local 02:30 ending. The last two flags retain start and end gap
adjustments independently. The actual fixture
also checks the retained ending policies, exact minute precision, and every
`{ series: "local-corpus", source }` identity before emitting observations.
It never receives an expected result.

For the +60-minute change, 02:30 and 03:30 both select 02:30Z. Removing the
02:30 source leaves 03:30; excluding 02:30Z removes both. Their distinct source
identities and ending intentions must survive until that exclusion is applied.
This is a small counterexample that a coverage-only comparison would miss.

Each case runs with one candidate/zone step and one output slot per call, then
with larger work chunks. Zero work, source-buffer, zone-work, zone-candidate
and output budgets must report `Limited`. Resuming must finish without losing
or duplicating results. A second query starting at 03:00 overlaps the first
window and must restrict the original series rather than restart COUNT.
The Roc harness rejects deliberately missing, changed and malformed records
through the same strict comparison used by ordinary replay.

## Why the expectations are independent

`LocalCases.roc` uses an exhaustive two-day integer-minute table. Its reference
model selects positions from each day's complete four-item list, counts the
series before exclusions, unions explicit additions, and filters the query last.
For interpretation it inverts the two constant-offset segments directly. A fold
chooses the first boundary; a gap uses the offset before the transition. Endings
come from a separate integer calculation. None of those expected calculations
calls production candidate generation, cursor execution or zone classification.

The shared assumptions are the Gregorian epoch, the source timestamp parser,
and the meaning of fixed offsets. Actual source labels are observed using the
package's zero-offset projection, while expected sources are literal table
indices. The existing sourced New York examples in `package/ICalPeriod.roc`
and `package/TimedRecurrence.roc` provide separate checks of those conventions:
RFC 5545 §3.3.5 gives the 2007 gap/fold meanings; verified erratum 4271 supplies
the recurrence gap policy. The corrected 1997 three-hour cutoff examples from
verified erratum 3883 remain in `TimedRecurrence.roc`. The manifest pins the
revision containing those fixtures. These standard examples are not outputs
from dateutil, and the new synthetic cases are model-derived extensions, not
claims that the RFC published these schedules.

The existing 384-case UTC/dateutil corpus remains unchanged. This additional
model does not establish general RFC conformance, mixed UTC/local additions,
leap seconds, arbitrary calendars, arbitrary transition histories or backend
portability beyond the hosts on which the gate actually runs. Replay reads no
host timezone data, clock, network or external reference service. Building the
fixture may fetch its already pinned platform/compiler dependencies.

The generator is retained in `generate.roc`. To propose an intentional corpus
refresh, run it with the package compiler and review the resulting diff:

```text
roc --opt=interpreter tests/local_recurrence/generate.roc
```

Update the reviewed manifest and harness digest together; never replace this
corpus with actual package observations. No external implementation code was
copied into this model.

## Fuzzing and resource checks

The existing `recurrence-v1` roc-fuzz target maps its bounded input fields onto
the same local model. It keeps the pinned 0.4.3 URL and existing runner:

```text
ROC_NIGHTLY=/path/to/roc blueprint run fuzz -- --operation replay --targets recurrence
ROC_NIGHTLY=/path/to/roc blueprint run fuzz -- --operation run --targets recurrence --runs 1000 --seconds 10 --seed 33
```

The six-byte `local-gap-boundary-exclusion` seed decodes to count=1,
exclude_anchor=False, interval=1, last_monday=False, query_month=1, work=2.
The local projection selects shift=+60, all positions, local UNTIL and UTC
boundary exclusion. It deliberately exercises the colliding-source case above.
Its SHA-256 is
`36c159d76b52e03e496363607c5940227f62f4e048df344b050159bc97bba3d7`.
It is a hand-authored seed, not a newly discovered failure or minimized crash.
Existing minimized recurrence regressions and their provenance remain intact.

`resource/main.roc` measures cursor construction, first appointment and resumed
appointment separately. The rule, immutable transition table and source ending
are built before those measurements. A retained cursor snapshot exercises shared
state. Years 1971 and 200000 must have identical requested-byte traffic and work
for that prefix, with a 4 KiB ceiling per stage and a five-second process bound.
Each ceiling has its own zero-byte failing control using the always-active host
assertion, including optimized builds. Semantic checks inspect the source ID and
both endpoints alongside the resource measurements.

These counters measure cumulative allocator requests, including output buffers,
not live or retained memory. The input table and declaration are outside cursor
scope; one pending ending and returned appointment are inside consumption scope.
After the measured scopes, the saved immutable cursor is independently consumed
again through bounded resumptions and must return its original first source and
span. This does not establish its exact retained size. The existing broader recurrence resource gate
still covers large clock products, shared/sliced tables and other limit stages.
