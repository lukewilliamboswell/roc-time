# Publish everyday appointment applications

Objective: make the staged caller applications available through a compatible
release and public examples. Follow [R05, R07–R09 and R14–R16](../design.md#acceptance-requirements).

## Remaining deliverables

When a compatible release includes the required native civil text, display and
query APIs, promote these staged applications into the public example collection:

- [Named-zone appointment](../tests/zoned_appointment/main.roc), with both core and zone dependencies.
- [Appointment display](../tests/appointment_display/main.roc), with the core dependency.
- [Invoice report](../tests/invoice_report/main.roc), with the core dependency.
- [Schedule exchange](../tests/schedule_exchange/main.roc), with the core dependency and DATE export APIs.
- [Meeting exchange](../tests/meeting_exchange/main.roc), with both dependencies and timed export APIs.

Pin each compiler and immutable package URL. Include the applications in the
starter kit and preserve their independent fixtures, scenario checks and exact
output gates. When moving the invoice module, update the scenario-check staging
to copy the same application implementation from its new path.

Verify compiler compatibility before choosing the release source: development
currently uses a newer compiler than public examples. Keep existing published
examples runnable and validate promoted multi-file applications against both
local sources and the distributable bundles. Release notes must identify the
compiler, both package URLs, supported profiles and runnable examples.

Localized presentation, relative phrases, timer/sleep services, a general zoned
wrapper, next-weekday arithmetic, inverse ISO constructors, customizable weeks
and speculative unit helpers need a concrete caller before expansion. New zoned
day/month selection helpers must preserve skipped dates, exclusive endpoints
and disconnected coverage.
Broader outstanding obligations remain in [implement-design.md](implement-design.md).

Remove this plan once publication and its executable acceptance are complete.
