# UTC cancellation fixtures

These authored fixtures exercise the public iCalendar import/export, schedule,
standardized property round trips and bounded cursor APIs. Expected source identities,
positions and widths are fixed independently of roc-time execution.

Primary sources:

- [RFC 5545 §3.3.5](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.5)
  specifies the first occurrence of an ambiguous local time and the offset before
  a forward gap. Its New York examples imply 2007-11-04 01:30 → 05:30 UTC and
  2007-03-11 02:30 → 07:30 UTC. The finite rules here encode only the transitions
  needed for those examples, with explicit validity and version labels.
- [Verified erratum 4271](https://www.rfc-editor.org/errata/eid4271), verified
  2015-02-17, applies that gap interpretation to recurrence-generated labels.
- [RFC 5545 §3.8.5.1](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.8.5.1)
  gives EXDATE precedence over recurrence inclusions. COUNT and BYSETPOS select
  source candidates before exclusions; the fixtures check that cancellation does
  not replenish the source count.

Sources checked 2026-09-07. RFC 5545 is © 2009 IETF Trust and the identified
contributors, under BCP 78. No implementation or prose is copied into the tests.

The epoch fixture is synthetic: offset changes from zero to +3600 seconds at
POSIX zero. Under the explicit pre-gap policy, local 00:30 and 01:30 both resolve
to POSIX +1800 seconds. A UTC cancellation removes both starts; a local
cancellation removes only its original source identity. RDATE and PERIOD cases
exercise the same rule while preserving the surviving three-hour ending.
These collision cases extend the sourced interpretation; they are not quoted
RFC examples or external-library outputs.

Expected microseconds are calculated as Gregorian days since 1970-01-01 times
86400000000, plus UTC time-of-day microseconds. For example, the first fold is
`1194134400000000 + (5*3600+30*60)*1000000 = 1194154200000000`.
The standard-library-only `reference.py` independently checks every nontrivial
New York coordinate used by the fixtures. It does not import roc-time, consult
a zone database, or regenerate/bless Roc expectations.

Normal execution is offline. Each case compares an original broad-budget cursor
and a cursor rebuilt from exported/reimported RFC property values with the same
explicit caller-supplied zone context, limited to two work steps, one zone segment and one
output per call. Query windows overlap and preserve series/source IDs. Mixed
UTC RDATE/PERIOD and floating UTC EXDATE remain explicitly unsupported.
