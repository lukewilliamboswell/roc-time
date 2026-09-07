# Keep examples and versions together

A working example has three parts: the application’s complete source folder, its package URLs and its Roc compiler version. Preserve all three when you copy or upgrade it.

## Published examples

The app header’s `roc` field records the compiler. `time` and optional `zones` fields point to immutable, content-addressed packages. Changing the compiler alone is not a package upgrade strategy.

Choose a [release](https://github.com/lukewilliamboswell/roc-time/releases) and download its starter kit. The kit contains release-specific package URLs; a source tag can retain preceding example pins. Copy the kit's headers when targeting that release. Each root is named `main.roc` and may import neighboring modules.

## Core and optional zone data

The [release notes](https://github.com/lukewilliamboswell/roc-time/releases) identify both packages. Use core-only dependencies for offset timestamps, interval algebra and calendar work. Add the zone-data package when the application needs named rules.

A zone name and version describe data; they do not authenticate a transition table or silently fetch a replacement. An in-memory interpretation retains its explicit rules. Saving an IXDTF declaration alone does not save that context: applications must supply appropriate rules when loading it. The [interpretation context example](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/interpretation_context) shows how keeping or changing rules affects an interpretation.

The [repeated local time application](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/repeated_local_time) compares first and last appointment choices with the disconnected coverage of a repeated local range. It keeps these distinctions in memory without claiming that a local timestamp alone records them.

## Development examples

Read `package/main.roc` for the development compiler. Examples under `tests/` can depend on local source and require the full checkout. Public examples declare their own compiler and package URLs; inspect their headers rather than assuming they match development.

## When upgrading

1. Read the target package’s release notes and API changes.
2. Take the compiler and both relevant package URLs from a compatible released application.
3. Update the application header intentionally and keep companion modules with it.
4. Run the complete application, including the date/zone boundary cases that matter to your caller.

The website itself has a build compiler and basic-ssg platform pin. Those are documentation tooling dependencies; they do not change the compiler required by a released roc-time example.
