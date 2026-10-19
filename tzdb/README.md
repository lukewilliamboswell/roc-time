# Optional zone database

An appointment at 09:00 in Melbourne needs rules that say which UTC offset
applies on that date. This companion supplies those rules for IANA zone names
and their compatibility aliases. Applications working only with explicit offsets
or interval algebra can depend on the core package alone.

## Add it to an application

Copy the `zones` dependency URL from your release's notes or archived staffing
example, alongside the `time` dependency. The
[examples archive](../README.md#try-it) supplies complete applications using
those exact packages. You don't need to generate data yourself.

The [staffing application](../examples/staffing/main.roc) shows the flow:

1. `zones.Database.get(name)` selects a data record for the requested name.
2. `time.ZoneRules.from_database(data)` validates it for interpretation.
3. The application resolves local labels with explicit appointment policies or
   selects the coverage of a whole local range.

The compiled package needs no host timezone database, filesystem access or
network lookup during interpretation. Roc downloads its package dependency as
usual when building the application.

## Check the data you selected

The [manifest](package/manifest.json) records the source release, identifiers,
finite validity bounds and integrity hashes. `Database.get` returns
`UnknownZone(name)` for an unrecognized name. Imported rules reject queries
outside their horizon. Resolving a local label can require additional data near
that boundary to prove all possible matches were considered.

The pack keeps both the requested alias and its canonical identity. It supplies
whole-second offsets on the POSIX timeline, without an abbreviation or
daylight-saving-status API. Its historical coverage follows the pinned Python
tzdata distribution; early offsets are source conventions, not proof of every
place's historical clock practice. Future transitions follow that release's
rules, which can change with later legislation.

Pin the data version independently of the core. Updating a dependency doesn't
rewrite an existing in-memory interpretation: explicitly resolve again when you
want new rules. The [voyage example](../examples/voyage/main.roc) demonstrates
keeping an original booking while considering updated application-owned rules.
Custom schema-compatible providers enter through the same adapter; this data
package imports no roc-time modules.

## How the package is stored

One implementation module and two compact text assets are bundled together.
Roc decodes the assets into top-level values at compile time; lookups use the
resulting immutable data. Applications don't load separate data files at
runtime. This layout doesn't guarantee that choosing one zone removes every
other zone from the compiled binary.

For generation and review, follow the
[contributor workflow](../CONTRIBUTING.md#zone-data-representation-measurements).
Maintain `Database.roc` and regenerate the distributable package instead of
editing generated assets or the copied module by hand. Generated files and
source notices live under `package/`.
