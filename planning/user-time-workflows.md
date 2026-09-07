# Publish everyday appointment applications

Objective: make the staged caller applications available through a compatible
release and public examples. Follow [R05, R07–R09 and R14–R16](../design.md#acceptance-requirements).

## Remaining deliverables

When a compatible release includes the required native civil text and display
APIs, promote the [named-zone appointment application](../tests/zoned_appointment/main.roc)
into the public example collection with pinned compiler and immutable core/zone
URLs. Include it in the starter kit and retain its independent fixture and
exact-output gates. Coordinate the appointment-display promotion in
[civil ergonomics](civil-ergonomics.md).

Verify compiler compatibility before choosing the release source: development
currently uses a newer compiler than public examples. Keep existing published
examples runnable and validate promoted multi-file applications against both
local sources and the distributable bundles. Release notes must identify the
compiler, both package URLs, supported profiles and runnable examples.

Localized presentation, relative phrases, timer/sleep services, a general zoned
wrapper and speculative unit helpers need a concrete caller before expansion.
Broader outstanding obligations remain in [implement-design.md](implement-design.md).

Remove this plan once publication and its executable acceptance are complete.
