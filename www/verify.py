#!/usr/bin/env python3
"""Validate generated guide HTML and its links without a network dependency."""
from html.parser import HTMLParser
from pathlib import Path
import argparse
from urllib.parse import unquote, urlsplit

SOURCE = Path(__file__).resolve().parent


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.links = []
        self.ids = set()
        self.h1 = 0
        self.titles = 0
        self.current = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                raise ValueError(f"Duplicate HTML id: {attrs['id']}")
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.h1 += 1
        if tag == "title":
            self.titles += 1
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])
            if attrs.get("aria-current") == "page":
                self.current.append(attrs["href"])


def verify(output, api_root):
    output = output.resolve()
    expected = {path.with_suffix(".html").name for path in (SOURCE / "content").glob("*.md")}
    actual = {str(path.relative_to(output)) for path in output.rglob("*.html")}
    if actual != expected:
        raise ValueError(f"Generated page mismatch: missing={expected-actual}, stale={actual-expected}")
    parsed = {name: Page((output / name).read_text()) for name in sorted(actual)}
    checked = 0
    for name, page in parsed.items():
        if page.h1 != 1 or page.titles != 1 or page.current != [name]:
            raise ValueError(f"{name}: expected one heading/title/current navigation item")
        if "content" not in page.ids or "#content" not in page.links:
            raise ValueError(f"{name}: missing keyboard skip target")
        for href in page.links:
            link = urlsplit(href)
            if link.scheme or link.netloc:
                if link.scheme != "https":
                    raise ValueError(f"{name}: unexpected external link scheme: {href}")
                if link.netloc == "lukewilliamboswell.github.io" and link.path.startswith("/roc-time/"):
                    relative = unquote(link.path.removeprefix("/roc-time/"))
                    target = api_root / relative
                    if target.is_dir():
                        target /= "index.html"
                    if not target.is_file():
                        raise ValueError(f"{name}: missing versioned API reference: {href}")
                continue
            if link.path.startswith("/"):
                raise ValueError(f"{name}: root-relative link breaks prefixed previews: {href}")
            target = (output / name).parent / unquote(link.path or name)
            if target.is_dir():
                target /= "index.html"
            target = target.resolve()
            if not target.is_relative_to(output) or not target.is_file():
                raise ValueError(f"{name}: missing or escaping local target: {href}")
            if link.fragment:
                target_page = parsed[str(target.relative_to(output))]
                if unquote(link.fragment) not in target_page.ids:
                    raise ValueError(f"{name}: missing fragment: {href}")
            checked += 1
    print(f"PASS documentation site: {len(parsed)} pages, {checked} local links; released API targets exist")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="generated HTML directory")
    parser.add_argument("--api-root", type=Path, required=True, help="Restored release documentation tree")
    args = parser.parse_args()
    verify(args.output, args.api_root.resolve())
