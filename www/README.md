# Documentation site source

This directory contains authored guide sources. Generated API documentation is stored in release assets and restored during site assembly.
Build this site into an ignored preview directory;
do not point the generator at `www/` during development.

## Build and preview

From the repository root, use the compiler declared in `www/main.roc`:

```sh
roc version
roc check www/main.roc
roc build www/main.roc --output=.roc-time-tmp/docs-site-builder
.roc-time-tmp/docs-site-builder www/content .roc-time-tmp/docs-site
python3 www/verify.py .roc-time-tmp/docs-site --api-root .roc-time-tmp/api-docs
python3 -m http.server 8000 --directory .roc-time-tmp/docs-site --bind 127.0.0.1
```

Open <http://127.0.0.1:8000/>. Stop the server with Ctrl-C. Alternatively, open
the generated `index.html` directly; navigation uses relative URLs. On Windows,
give the builder a `.exe` suffix and use the corresponding executable command.
Python is only used here for local verification and an optional preview server;
the site generator itself is a Roc application.

The app pins the published [basic-ssg platform](https://github.com/lukewilliamboswell/basic-ssg/releases)
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
  Direct readers to the chosen release and application headers, and
  check release-specific header rewriting before recommending a source tag’s
  dependency URLs. Keep the starter kit’s app/compiler/package pins together.
- `verify.py` checks generated page coverage, titles/headings/navigation, local
  links/fragments and release API links against explicitly restored release documentation. It
  does not claim live external link availability or execute example code.

Rebuild into a fresh ignored output directory after deleting or renaming source
pages: basic-ssg writes output but does not remove stale files. The verifier
rejects stale HTML pages. Run the pinned formatter after changing Roc files:

```sh
roc fmt --check www/main.roc www/Site.roc
```

## Publishing boundary

The release workflow stores deterministic versioned API archives as GitHub release
assets. It restores historical assets into ignored storage, builds these authored
guides and deploys their combined output. Generated API pages and guide HTML do
not belong in Git. The authored guides own the root landing page; historical
`/<version>/` API URLs stay unchanged. Missing historical assets stop deployment.

For a complete local assembly, first restore release assets:

```sh
python3 scripts/release_docs.py fetch --output .roc-time-tmp/api-docs
python3 scripts/assemble_docs_site.py --api-root .roc-time-tmp/api-docs --output .roc-time-tmp/pages-site
```

Use fresh output directories. The standalone verifier needs that same restored
API directory; it does not depend on checked-in generated files.
