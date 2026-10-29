# Bundled timezone rules

These fixtures check the optional database through `Database.get`,
`ZoneRules.from_database`, `ZoneRules.offset_at` and
`ZoneRules.resolve_occurrence`. They cover R07, R09, R14 and R16.

Run the offline gate with the package compiler:

```sh
ROC_NIGHTLY=/path/to/nightly blueprint run check-zone-database
```

The gate verifies every accepted name, metadata, transition checksum and both
sides of every transition, then runs `ProviderCase` interpreted and native.
It also checks finite-horizon errors, future footer expansion, unknown names,
alias identity, corrupt inputs and lookup allocation budgets in dev/speed builds.

## Source-backed expectations

`ProviderCase.changed_rules` uses facts from IANA release **2026e**, commit
[`039ef27cc5f062a2055cb67435d6d71adbefd27d`](https://github.com/eggert/tz/tree/039ef27cc5f062a2055cb67435d6d71adbefd27d).
The expected offsets and UTC transition times were derived from the source
rules below, independently of the generated Roc pack. Each boundary fixture
checks the microsecond before and the boundary itself.

| Source and rule | Expected caller behavior |
| --- | --- |
| `northamerica`: Winnipeg, Edmonton, Inuvik and Vancouver; `NEWS` 2026b–e | Their March 2026 spring-forward becomes the final clock change. At the former November fall-back, offsets stay −05, −06, −06 and −07 respectively. Winnipeg 2026-11-02 09:00 resolves uniquely to 14:00 UTC, including through `Canada/Central`. |
| `africa`: Casablanca and El_Aaiun, `2026 Sep 20 2:00` | The offset changes from +01 to +00 at 01:00 UTC. This is a real offset change, unlike the Canadian no-offset-change boundaries. |
| `europe`: Chisinau uses EU rules from 2022 | Both spring and autumn transitions occur at 01:00 UTC, replacing the earlier Moldova transition hours. |
| `northamerica`: Tijuana uses CA rules from 1953 through 1966; CA's April transition is at 01:00 local | At 1953-04-26 09:00 UTC the offset changes from −08 to −07. |
| `southamerica`: CO `1992 May 2 0:00` | Bogota's spring-forward occurs at 1992-05-02 05:00 UTC, rather than a day later. |
| `asia`: Iran `1979 May 26 0:00` | Tehran changes from +03:30 to +04:30 at 1979-05-25 20:30 UTC, rather than a day later. |
| `europe`: Dublin's `1925 Sep Sun>=16 2:00s` zone boundary | The offset changes from +01 to +00 at 1925-09-20 02:00 UTC, rather than October 4. |
| `northamerica`: standalone EST5EDT, CST6CDT, MST7MDT and PST8PDT use US federal rules | Each has its named fixed standard offset in 1900. EST5EDT also stays −05 in summer 1960, when New York's local DST history differs. These are now canonical identities, not aliases of cities. |
| `asia`: Tbilisi `1997 Mar lastSun`; `NEWS` 2026a | The switch from fixed +05 to seasonal +05 at 1997-03-29 19:00 UTC has no offset change. Removing a redundant transition must preserve the result. |

The reviewed upstream files have these SHA256 digests:

```text
NEWS          b1aecd6fe12b04ca145395ff52b9550e5315a1126da49b35f3637a2fe915501c
northamerica  c0c5da0dc337444d80709cf9f8d8011719b789df160ce107a5c38c90e73dc54c
africa        f2851d4be4a4925cbdc9d56e10d780bccadb89d6ffb9aed78c3e35f97c200aed
europe        fec11bf6c6bd0619a8777bbdaa2ecd184fde291cb4b97efa87d334c7145ba3c2
southamerica  13be56a242da3c1a4a6d12050e5fd48b1753c8c1dc237cbc2edb40eac636be7f
asia          02b69728085f6b0c999da70de2f1f9a2d8952b533a450d53bb41e03eb7d0e92e
```

The distributed artifact is the separately pinned `tzdata 2026.5` wheel. Its
SHA256, URL, IANA version and upstream revision live in the generator and package
manifest. Generation checks the wheel hash, then checks **both** embedded IANA
version declarations before decoding. Apache notices are copied from that wheel;
IANA's source data is public domain as described in its `LICENSE`.

The intervening `NEWS` releases 2025c, 2026a, 2026b, 2026c, 2026d and 2026e were
reviewed. The rows above cover every changed offset history in the generated
1800–2200 profile, plus its redundant-transition change. All existing names are
retained. The four POSIX names become standalone canonical rows; other aliases
keep their identity. No consumer should depend on a fixed canonical-zone count.
Changes to abbreviations, DST flags, leap-aware files and tzcode behavior are
outside this offset-only profile.

## Independence and limits

The source fixtures detect incorrect exported rules, off-by-one transitions and
wrong local appointment results. They share IANA's authority with the wheel;
they do not independently establish historical or legal truth. Generation also
compares Python footer expansion with CPython's C `ZoneInfo` over every segment
and monthly probes. Those are different implementations using the same bytes.

This is a data refresh, not a new interpretation algorithm. Deterministic
source-backed boundary fixtures and exhaustive replay of the finite exported
transition tables are more useful here than random timezone names. The existing
zone fuzz target continues to exercise the core interpretation algorithm.

Historical oracle corpora under `tests/oracle_zones` remain pinned to 2025b.
Their generator and expectations are deliberately unchanged. Refreshing this
companion does not redefine earlier evidence, change an application's pinned
release URL, or mutate previously resolved snapshots. Applications opt into the
new data by selecting a new package release and explicitly re-resolving when
needed. Ordinary replay uses checked-in files, with no network or host database.
