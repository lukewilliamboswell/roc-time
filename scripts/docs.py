#!/usr/bin/env python3
"""Generate versioned package documentation.

Writes the docs to `<docs-root>/<version>` and refreshes the redirecting
`<docs-root>/index.html` that points at that version.
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
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")

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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Release version, e.g. 0.1.0")
    parser.add_argument(
        "--docs-root",
        type=Path,
        default=Path(os.environ.get("DOCS_ROOT", ROOT / "www")),
    )
    args = parser.parse_args()

    version = args.version.removeprefix("v")
    if not VERSION_RE.match(version):
        raise SystemExit(f"Error: version must be in the format x.y.z (e.g. 0.1.0), got {version}")

    docs_root = args.docs_root
    version_dir = docs_root / version

    shutil.rmtree(version_dir, ignore_errors=True)
    docs_root.mkdir(parents=True, exist_ok=True)

    cmd = [roc_command(), "docs", "package/main.roc", f"--output={version_dir}"]
    print("+", " ".join(cmd), file=sys.stderr)
    completed = subprocess.run(cmd, cwd=ROOT)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)

    # roc docs supplies navigation and API pages but no package introduction.
    index = version_dir / "index.html"
    page = index.read_text()
    marker = '<div class="main-content">'
    if page.count(marker) != 1:
        raise SystemExit("Compiler docs layout changed; review landing-page insertion")
    guide = (ROOT / "docs/overview.html").read_text()
    page = page.replace(marker, marker + "\n" + guide, 1)
    page = page.replace('<div class="index-decoration">', '<div class="index-decoration" style="display: none">', 1)
    index.write_text(page)
    for generated_page in version_dir.rglob("*.html"):
        html = generated_page.read_text().replace("package Docs", "roc-time API")
        html = re.sub(r'(<h1 class="pkg-full-name"><a href="[^"]*">)package(</a></h1>)',
                      r'\1roc-time\2', html)
        generated_page.write_text(html)

    (docs_root / "index.html").write_text(
        INDEX_TEMPLATE.format(repo=REPO_NAME, version=version), encoding="utf-8"
    )

    print(f"Generated docs for {version} in {version_dir}")


if __name__ == "__main__":
    main()
