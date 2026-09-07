# Documentation site source

This directory contains the authored guide site. `../0.1.0-rc*/` contains
generated, versioned API documentation maintained by the release workflow.
Keep those directories intact. Build this site into an ignored preview directory;
do not point the generator at `www/` during development.

## Build and preview

From the repository root, use the compiler pinned in `main.roc`, currently
`nightly-2026-09-06-d85e877` (also the package development compiler):

```sh
roc version
roc check www/site/main.roc
roc build www/site/main.roc --output=.roc-time-tmp/docs-site-builder
.roc-time-tmp/docs-site-builder www/site/content .roc-time-tmp/docs-site
python3 www/site/verify.py .roc-time-tmp/docs-site
python3 -m http.server 8000 --directory .roc-time-tmp/docs-site --bind 127.0.0.1
```

Open <http://127.0.0.1:8000/>. Stop the server with Ctrl-C. Alternatively, open
the generated `index.html` directly; navigation uses relative URLs. On Windows,
give the builder a `.exe` suffix and use the corresponding executable command.
Python is only used here for local verification and an optional preview server;
the site generator itself is a Roc application.

The app pins the published [basic-ssg 0.11.0 platform](https://github.com/lukewilliamboswell/basic-ssg/releases/tag/0.11.0)
by immutable content-addressed URL. `SSG.markdown_pages!`,
`SSG.parse_markdown!` and `SSG.write_file!` provide discovery, Markdown rendering
and output. No local basic-ssg checkout or platform build is required. The first
Roc build may download the pinned dependency.

## Authoring

- `content/*.md` contains the user-facing pages. Page names map directly to HTML
  names. These reviewed local sources are trusted Markdown; do not feed external
  untrusted content into the generator.
- `Site.roc` contains the page catalog, shared layout and responsive CSS. Add a
  catalog entry when adding a page; unregistered source pages fail the build.
- Keep headings, descriptive link text and the current-page navigation. The
  layout includes a keyboard skip link and visible focus styles. There are no
  runtime scripts, remote fonts, analytics or external styling dependencies.
- Link tasks to real multi-file applications and version-specific API docs.
  The default guides target rc3. Label development-only APIs explicitly, and
  check release-specific header rewriting before recommending a source tag’s
  dependency URLs. Keep the starter kit’s app/compiler/package pins together.
- `verify.py` checks generated page coverage, titles/headings/navigation, local
  links/fragments and release API links against checked-in documentation. It
  does not claim live external link availability or execute example code.

Rebuild into a fresh ignored output directory after deleting or renaming source
pages: basic-ssg writes output but does not remove stale files. The verifier
rejects stale HTML pages. Run the pinned formatter after changing Roc files:

```sh
roc fmt --check www/site/main.roc www/site/Site.roc
```

## Publishing boundary

This foundation does not change deployment. `scripts/docs.py` currently generates
versioned API docs and owns the root redirect; `.github/workflows/release-docs.yml`
publishes `www/`. Integrating this landing site must first settle ownership of
`www/index.html`, stage only generated output and historical API directories,
and preserve immutable release docs. See the scoped
[documentation-site plan](../../planning/documentation-site.md).
