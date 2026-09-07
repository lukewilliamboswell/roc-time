# Optional zone database

This companion supplies IANA time-zone offsets and compatibility aliases over
an explicit finite horizon on the POSIX timeline. The [package manifest](package/manifest.json)
records the source release, covered identifiers, validity bounds and integrity hashes.
It is a separate dependency: interval-only and fixed-offset applications need
only roc-time. No host database, filesystem access or network lookup is needed
when using the compiled data.

The [overnight staffing application](../examples/staffing/main.roc) shows the
ordinary flow: `Database.get(name)`, `ZoneRules.from_database(data)`, then resolve
local appointments with explicit occurrence policies. `Database.get` returns
`UnknownZone(name)` for an unrecognized name. Imported rules reject queries
outside the supplied horizon; local resolution can need additional data around
its endpoints to prove completeness.

The pack preserves requested aliases and canonical identities. Its source is the
Python tzdata distribution pinned by that manifest, including its historical coverage
choices. Pre-standardization offsets are source conventions, not a guarantee of
historical local practice. Future transitions expand that release's rules; they
are not predictions of future legislation. The pack provides offsets, without
an abbreviation or daylight-saving-status API.

Keep the data version pinned independently of the core. An application may pass
its own schema-compatible data to the same adapter. Updating a data dependency
requires explicitly resolving new values; existing snapshots retain their rules.
The data package imports no roc-time modules.
The [voyage briefing](../examples/voyage/main.roc) demonstrates an application-owned
clock schedule and an explicit update while retaining the original booking.

The package contains one implementation module and two compact text assets.
Roc imports and decodes the assets into top-level values at compile time;
ordinary lookups use the resulting immutable data. Both assets are included in
the content-addressed package archive, so applications need no separate files.
This layout does not promise that a one-zone application eliminates all other
zones from its binary.

To add the published companion, copy the `zones` dependency URL from the
[staffing application's header](../examples/staffing/main.roc), alongside its
`time` dependency and compiler requirement. Import `zones.Database` to select
data and `time.ZoneRules` to validate it. The [release notes and starter kit](../README.md#try-it)
provide both package archives and complete applications. Run an application
directly with its declared Roc compiler; no data-generation script is needed.

For contributors, see the
[contributor guide](../CONTRIBUTING.md#zone-data-representation-measurements)
for generation, review and verification. Generated files and source notices are
under `package/`. Maintain the decoder in `Database.roc` and regenerate the
distributable package; do not edit generated assets or copied modules by hand.
