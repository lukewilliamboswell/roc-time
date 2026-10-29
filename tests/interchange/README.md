# EDTF interval evidence

`package/EdtfInterval.roc` contains the independently reviewed expected meanings
for these Library of Congress examples. Normal tests use the checked-in typed
fixtures; they do not fetch the specification or regenerate expectations.

Source: [Extended Date/Time Format specification](https://www.loc.gov/standards/datetime/edtf.html),
February 4, 2019 edition, reviewed 2026-10-20. The retrieved HTML was 27,069 bytes,
SHA-256 `4b49ba3056e53cea5611343873793b352d71932844699eb334faf43b21c4f7e7`.
The digest identifies the reviewed source bytes; it is not authentication.
No source implementation code was adapted.

The Level 0 **Time Interval** examples 1–6 independently establish endpoint
fields and year/month/day resolution, including mixed resolutions. Level 1
**Extended Interval** examples 3, 6, 9 and 12 establish known-year endpoints
with an open or unknown opposite side. Level 2 **Interval** example 1 establishes
independent approximate-day qualifications on June 1 and June 20, 2004.
Fixtures compare fields, calendar, resolution, knowledge and scope directly;
serializer/parser agreement is supplementary evidence.

The declared adapter also accepts `/`, `../..`, `/..` and `../`. These are
model-derived compositions of the specification's per-side null and double-dot
rules, rather than additional examples quoted from LOC. All nine combinations
of Known, Unknown and Open are native descriptions. No combination is a numeric
infinity sentinel or an automatically computed interval.

The independent generated model in `InterchangeCase.roc` enumerates admissible
months within one Gregorian year. It checks whether an unqualified start domain
can precede an end-month domain. It uses integer field order rather than
production civil-day conversion or exclusive-upper-bound construction. Its
intersection covers generated years 1900–2100, valid day labels and independent
year/month/day start resolution. Fixed tests add year zero, 9999, the terminal
native I32 provider year, same-day domains, Julian export rejection and
qualified reverse-looking labels.

Mixed-calendar order checks reuse two independently sourced corpus anchors:
the generated Julian corpus id 100 (Julian 1582-10-05, Hinnant-derived reference)
and the generated Gregorian corpus id 112 (Gregorian 1582-10-15, Python datetime).
Both have civil day -141427; their respective manifests pin the reference
implementations and provenance. A next-day Julian endpoint must be rejected
against that Gregorian end. Native tests also cover same-day and reversed
adjacent endpoints at both calendars' lowest provider year.

These checks establish faithful interchange and the conservative intrinsic
reversal check. They do not establish a calendar/zone endpoint-domain solver,
probabilities, inferred tolerances, full EDTF conformance or certain timeline
coverage. CalendarInterval.interpretation_support reports that missing capability.
