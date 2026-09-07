#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
from pathlib import Path


sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DEPENDENCY_RE = re.compile(r'(?m)^(\s*time:\s*)"[^"]+"')
ICAL_NAMES = {
    "RfcDateRule": "ICalDateRule",
    "RfcDateTime": "ICalDateTime",
    "RfcDuration": "ICalDuration",
    "RfcPeriod": "ICalPeriod",
    "RfcTimedRule": "ICalTimedRule",
}
ICAL_NAME_RE = re.compile(r"\b(?:" + "|".join(ICAL_NAMES) + r")\b")


def migrate_example_api(source: str) -> str:
    """Rebind known example identifiers, including tags and interpolations.

    This explicit source migration belongs only to current-package copies and
    new releases. Previously published archives retain their original APIs.
    Whole-name matching leaves longer application identifiers unchanged.
    """
    return migrate_calendar_names(ICAL_NAME_RE.sub(lambda match: ICAL_NAMES[match[0]], source))


def migrate_calendar_names(source: str) -> str:
    """Rebind legacy public names only in explicitly migrated package copies."""
    moved = {
        "selection_cursor": "(|migration_value, migration_rules| ZoneRules.calendar_selection_cursor(migration_rules, migration_value))",
        "local_bounds": "LocalDateTime.calendar_value_bounds",
        "start_label": "LocalDateTime.from_calendar_value",
        "fact_at": "SemanticFact.calendar_value_fact_at",
        "fact_count": "SemanticFact.calendar_value_fact_count",
    }
    owners = set()
    for method, replacement in moved.items():
        source, count = re.subn(r"\b(?:CalendarValue|Calendar\.Value)\." + method + r"\b", replacement, source)
        if count:
            owners.add("ZoneRules" if method == "selection_cursor" else replacement.split(".")[0])
    source = re.sub(r"^(import[ \t]+(?:time\.)?)Calendar(?:Date|Delta|Value|Arithmetic)[ \t]*$", r"\1Calendar", source, flags=re.MULTILINE)
    for old, new in {"CalendarDate": "Calendar.Date", "CalendarDelta": "Calendar.Delta", "CalendarValue": "Calendar.Value", "CalendarArithmetic": "Calendar.Arithmetic"}.items():
        source = re.sub(r"\b" + old + r"\b", new, source)
    seen = set()
    lines = []
    for line in source.splitlines(keepends=True):
        if line.startswith("import "):
            key = line.strip()
            if key in seen:
                continue
            seen.add(key)
        lines.append(line)
    missing = [f"import time.{owner}\n" for owner in sorted(owners)
               if f"import time.{owner}" not in seen]
    # Companion modules begin with imports; app headers must stay first.
    if missing:
        index = next((i for i, line in enumerate(lines) if line.startswith("import ")), None)
        if index is None:
            raise ValueError("Moved Calendar.Value operation needs an explicit import insertion point")
        lines[index:index] = missing
    return "".join(lines)


def update_examples(examples_dir: Path, bundle_url: str, zone_bundle_url: str | None = None, *, compiler: str | None = None, migrate_api: bool = False) -> list[Path]:
    examples = sorted(examples_dir.rglob("main.roc"))
    if not examples:
        raise SystemExit(f"No Roc examples found in {examples_dir}")

    updated: list[Path] = []
    for example in examples:
        source = example.read_text(encoding="utf-8")
        rewritten, count = PACKAGE_DEPENDENCY_RE.subn(
            lambda match: f'{match.group(1)}"{bundle_url}"',
            source,
            count=1,
        )
        if count != 1:
            raise SystemExit(f"{example} does not declare the expected time package dependency")
        if zone_bundle_url is not None:
            rewritten = re.sub(r'(?m)^(\s*zones:\s*)"[^"]+"', lambda match: f'{match.group(1)}"{zone_bundle_url}"', rewritten)
        if compiler is not None:
            from roc_version import replace_pin
            rewritten = replace_pin(rewritten, compiler)
        if rewritten != source:
            example.write_text(rewritten, encoding="utf-8")
            updated.append(example)

    if migrate_api:
        for path in sorted(examples_dir.rglob("*.roc")):
            source = path.read_text(encoding="utf-8")
            rewritten = migrate_example_api(source)
            if rewritten != source:
                path.write_text(rewritten, encoding="utf-8")
                if path not in updated:
                    updated.append(path)

    return updated


def copy_examples(destination: Path, core: str, zones: str, *, compiler: str, source: Path = ROOT / "examples") -> list[Path]:
    """Rebind complete applications in a disposable copy, never tracked sources."""
    shutil.copytree(source, destination)
    update_examples(destination, core, zones, compiler=compiler, migrate_api=True)
    return sorted(destination.rglob("main.roc"))


def self_test() -> None:
    from roc_version import read_pin
    temporary = ROOT / ".roc-time-tmp"
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="example-copy-test-", dir=temporary) as directory:
        work = Path(directory)
        source = work / "source"
        (source / "sample").mkdir(parents=True)
        original = ('app [main!] {\n'
                    ' roc: "nightly-2026-09-05-b195f5b",\n'
                    ' time: "https://example.com/time.tar.zst",\n'
                    ' zones: "https://example.com/zones.tar.zst",\n'
                    '}\nimport Example\nmain! = |_args| { Ok({}) }\n')
        main = source / "sample/main.roc"
        main.write_text(original)
        companion = source / "sample/Example.roc"
        companion_source = ('import time.RfcDateRule\nimport time.RfcDateTime\n'
                            'import time.RfcDuration\nimport time.RfcPeriod\n'
                            'import time.RfcTimedRule\n'
                            'Example := []\n'
                            'parse = RfcDateRule.parse\n'
                            'clock : RfcDateTime\n'
                            'duration = RfcDuration.parse\n'
                            'period = RfcPeriod.parse\n'
                            'rule = RfcTimedRule.parse\n'
                            'description = "${RfcDateTime.to_text(clock)}"\n'
                            'MyRfcPeriod = "unchanged"\n')
        companion.write_text(companion_source)
        expected_companion = ('import time.ICalDateRule\nimport time.ICalDateTime\n'
                              'import time.ICalDuration\nimport time.ICalPeriod\n'
                              'import time.ICalTimedRule\n'
                              'Example := []\n'
                              'parse = ICalDateRule.parse\n'
                              'clock : ICalDateTime\n'
                              'duration = ICalDuration.parse\n'
                              'period = ICalPeriod.parse\n'
                              'rule = ICalTimedRule.parse\n'
                              'description = "${ICalDateTime.to_text(clock)}"\n'
                              'MyRfcPeriod = "unchanged"\n')
        mixed = source / "sample" / "CalendarUse.roc"
        mixed_source = (
            "import time.CalendarDate\nimport time.CalendarDelta\nimport time.CalendarValue\n"
            "import time.Calendar\nimport time.LocalDateTime\nimport time.ZoneRules\nimport time.CalendarArithmetic\n"
            "value : CalendarValue\nvalue = CalendarValue.minute(date, 9, 30)?\n"
            "date = CalendarDate.from_fields(Gregorian, fields)?\n"
            "delta = CalendarDelta.days(1)\n"
            "shifted = CalendarArithmetic.shift_day(date, delta, Reject)?\n"
            "select = CalendarValue.selection_cursor\n"
            "cursor = CalendarValue.selection_cursor(value, rules)?\n"
            "bounds = CalendarValue.local_bounds(value)?\n"
            "start = CalendarValue.start_label(value)\n"
            "fact = CalendarValue.fact_at(value, 0)\n"
            "count = CalendarValue.fact_count(value)\n"
            "qualified = QualifiedCalendarValue.selection_cursor(query, rules)?\n"
        )
        mixed.write_text(mixed_source)
        copied = copy_examples(work / "copied", "/local/package/main.roc",
                               "/local/tzdb/package/main.roc",
                               compiler="nightly-2026-09-06-d85e877", source=source)
        if (len(copied) != 1 or read_pin(copied[0]) != "nightly-2026-09-06-d85e877"
                or 'time: "/local/package/main.roc"' not in copied[0].read_text()
                or 'zones: "/local/tzdb/package/main.roc"' not in copied[0].read_text()
                or main.read_text() != original
                or companion.read_text() != companion_source
                or (copied[0].parent / "Example.roc").read_text() != expected_companion):
            raise RuntimeError("Example copy did not preserve sources and rebind headers/dependencies")
        expected_mixed = (
            "import time.SemanticFact\nimport time.Calendar\nimport time.LocalDateTime\nimport time.ZoneRules\n"
            "value : Calendar.Value\nvalue = Calendar.Value.minute(date, 9, 30)?\n"
            "date = Calendar.Date.from_fields(Gregorian, fields)?\n"
            "delta = Calendar.Delta.days(1)\n"
            "shifted = Calendar.Arithmetic.shift_day(date, delta, Reject)?\n"
            "select = (|migration_value, migration_rules| ZoneRules.calendar_selection_cursor(migration_rules, migration_value))\n"
            "cursor = (|migration_value, migration_rules| ZoneRules.calendar_selection_cursor(migration_rules, migration_value))(value, rules)?\n"
            "bounds = LocalDateTime.calendar_value_bounds(value)?\n"
            "start = LocalDateTime.from_calendar_value(value)\n"
            "fact = SemanticFact.calendar_value_fact_at(value, 0)\n"
            "count = SemanticFact.calendar_value_fact_count(value)\n"
            "qualified = QualifiedCalendarValue.selection_cursor(query, rules)?\n"
        )
        actual_mixed = (copied[0].parent / "CalendarUse.roc").read_text()
        if mixed.read_text() != mixed_source or actual_mixed != expected_mixed:
            raise RuntimeError("Calendar migration lost owner/import distinctions or changed source")
        if migrate_example_api(actual_mixed) != actual_mixed:
            raise RuntimeError("Calendar migration is not idempotent")
        update_examples(source, "https://example.com/new.tar.zst")
        if companion.read_text() != companion_source:
            raise RuntimeError("URL-only rebinding unexpectedly migrated identifiers")
        update_examples(source, "https://example.com/new.tar.zst", migrate_api=True)
        migrated = companion.read_text()
        if "RfcDateRule.parse" in migrated or "ICalDateRule.parse" not in migrated:
            raise RuntimeError("Explicit release rebinding did not migrate companion identifiers")
        if migrate_example_api(migrated) != migrated:
            raise RuntimeError("Identifier migration is not idempotent")
        main.write_text(original.replace(' time:', ' absent:'))
        try:
            copy_examples(work / "invalid", "/local/core", "/local/zones",
                          compiler="nightly-2026-09-06-d85e877", source=source)
        except SystemExit as error:
            if "expected time package dependency" not in str(error):
                raise
        else:
            raise RuntimeError("Missing dependency declaration was accepted")
    print("PASS example copies: compiler/dependency rebind, ICal/Calendar companion migrations, immutable sources, explicit release migration, missing declaration")


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-url")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--zone-bundle-url", help="Optional independently versioned zone-data bundle")
    parser.add_argument("--examples-dir", type=Path, default=ROOT / "examples")
    parser.add_argument("--compiler", help="Rebind copied example app compiler headers")
    parser.add_argument("--migrate-api", "--migrate-ical", dest="migrate_api", action="store_true", help="Migrate example API names for the current package or a new release")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if args.bundle_url is None:
        parser.error("--bundle-url is required")
    updated = update_examples(args.examples_dir, args.bundle_url, args.zone_bundle_url, compiler=args.compiler, migrate_api=args.migrate_api)
    if updated:
        print("Updated example URLs:")
        for path in updated:
            print(f"- {display_path(path)}")
    else:
        print("Example URLs are already up to date.")


if __name__ == "__main__":
    main()
