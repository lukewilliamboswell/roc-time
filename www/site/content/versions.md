# Keep examples and versions together

A working example has three parts: the application’s complete source folder, its package URLs and its Roc compiler version. Preserve all three when you copy or upgrade it.

## Published examples

The guides currently target **0.1.0-rc3** with compiler **nightly-2026-09-05-b195f5b**. Release candidates are usable for experimentation, but their APIs can change. There is no versioned stable Roc release yet.

The app header’s `roc` field records the compiler. `time` and optional `zones` fields point to immutable, content-addressed packages. Changing the compiler alone is not a package upgrade strategy.

Use the [released starter kit](https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-starter.zip) for a ready collection, or browse the implementations in the [release source](https://github.com/lukewilliamboswell/roc-time/tree/0.1.0-rc3/examples). The starter kit contains the release-specific rewritten package URLs; the source tag can retain a preceding release’s example pins. Copy the kit’s headers when targeting rc3. Each root is named `main.roc` and may import neighboring modules.

## Core and optional zone data

The [rc3 release notes](https://github.com/lukewilliamboswell/roc-time/releases/tag/0.1.0-rc3) identify both packages. Use core-only dependencies for offset timestamps, interval algebra and calendar work. Add the zone-data package when the application needs named rules.

A zone name and version describe data; they do not authenticate a transition table or silently fetch a replacement. When reproducibility matters, preserve the interpretation snapshot supported by your API.

## Development examples

Main uses **nightly-2026-09-06-d85e877** in `package/main.roc`. New workflow examples may live under `tests/` until a release publishes their APIs. They reference local packages and need the full checkout.

The public `examples/` collection uses released package URLs. A newly added application can still use an older released package, but that does not put the application into an already-published starter ZIP.

The `roc-0.1.x` branch is a pilot compatibility lane using a selected nightly as a stand-in for a future stable Roc release. It is not evidence that upstream Roc 0.1 exists. Intended future lanes follow upstream Roc versions; package changes produce new immutable package releases.

## When upgrading

1. Read the target package’s release notes and API changes.
2. Take the compiler and both relevant package URLs from a compatible released application.
3. Update the application header intentionally and keep companion modules with it.
4. Run the complete application, including the date/zone boundary cases that matter to your caller.

The website itself has a build compiler and basic-ssg platform pin. Those are documentation tooling dependencies; they do not change the compiler required by a released roc-time example.
