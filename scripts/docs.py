#!/usr/bin/env python3
"""Generate versioned package documentation.

Writes the docs to `<docs-root>/<version>`. Stable releases point the root
redirect at the highest stable version present; prereleases preserve it.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO_NAME = "roc-time"
NUMERIC = r"(?:0|[1-9][0-9]*)"
PRERELEASE_IDENTIFIER = rf"(?:{NUMERIC}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
VERSION_RE = re.compile(
    rf"{NUMERIC}\.{NUMERIC}\.{NUMERIC}"
    rf"(?:-(?P<prerelease>{PRERELEASE_IDENTIFIER}(?:\.{PRERELEASE_IDENTIFIER})*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)

INDEX_TEMPLATE = """<!doctype html>
<html lang="en">
    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>Redirecting...</title>
        <script>
            window.location.href = "/{repo}/{version}/";
        </script>
    </head>
    <body>
        <noscript>
            <p>
                If you are not automatically redirected, please
                <a href="/{repo}/{version}/">click here</a>.
            </p>
        </noscript>
    </body>
</html>
"""


def roc_command() -> str:
    roc = os.environ.get("ROC", "roc")
    if "/" in roc or "\\" in roc:
        return str(Path(roc).resolve())
    return roc


def update_stable_index(docs_root: Path) -> str:
    """Select numeric SemVer precedence from generated stable documentation only."""
    candidates = []
    for entry in docs_root.iterdir():
        parsed = VERSION_RE.fullmatch(entry.name)
        if (parsed is None or parsed.group("prerelease") is not None
                or not entry.is_dir() or not (entry / "index.html").is_file()):
            continue
        # Build metadata does not affect precedence. The spelling is a stable
        # tie-breaker if history contains two names for the same numeric release.
        numbers = tuple(int(part) for part in entry.name.split("+", 1)[0].split("."))
        candidates.append((numbers, entry.name))
    if not candidates:
        raise ValueError("No generated stable documentation available for the root redirect")
    version = max(candidates)[1]
    (docs_root / "index.html").write_text(
        INDEX_TEMPLATE.format(repo=REPO_NAME, version=version), encoding="utf-8"
    )
    return version


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Release version, e.g. 0.1.0 or 0.1.0-rc1")
    parser.add_argument("--source-root", type=Path, default=ROOT,
                        help="Checkout whose package and overview to document")
    parser.add_argument(
        "--docs-root",
        type=Path,
        default=Path(os.environ.get("DOCS_ROOT", ROOT / "www")),
    )
    args = parser.parse_args()

    version = args.version.removeprefix("v")
    parsed_version = VERSION_RE.fullmatch(version)
    if parsed_version is None:
        raise SystemExit(f"Error: version must be SemVer (e.g. 0.1.0 or 0.1.0-rc1), got {version!r}")

    source_root = args.source_root.resolve()
    docs_root = args.docs_root.resolve()
    version_dir = docs_root / version

    shutil.rmtree(version_dir, ignore_errors=True)
    docs_root.mkdir(parents=True, exist_ok=True)

    cmd = [roc_command(), "docs", "package/main.roc", f"--output={version_dir}"]
    print("+", " ".join(cmd), file=sys.stderr)
    completed = subprocess.run(cmd, cwd=source_root)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)

    # roc docs supplies navigation and API pages but no package introduction.
    index = version_dir / "index.html"
    page = index.read_text()
    marker = '<div class="main-content">'
    if page.count(marker) != 1:
        raise SystemExit("Compiler docs layout changed; review landing-page insertion")
    guide = (source_root / "docs/overview.html").read_text()
    page = page.replace(marker, marker + "\n" + guide, 1)
    page = page.replace('<div class="index-decoration">', '<div class="index-decoration" style="display: none">', 1)
    index.write_text(page)
    for generated_page in version_dir.rglob("*.html"):
        html = generated_page.read_text().replace("package Docs", "roc-time API")
        html = re.sub(r'(<h1 class="pkg-full-name"><a href="[^"]*">)package(</a></h1>)',
                      r'\1roc-time\2', html)
        generated_page.write_text(html)

    if parsed_version.group("prerelease") is None:
        update_stable_index(docs_root)

    print(f"Generated docs for {version} in {version_dir}")


if __name__ == "__main__":
    main()
