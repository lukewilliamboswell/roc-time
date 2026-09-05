# roc-time

A date and time package for [Roc](https://www.roc-lang.org).

> [!NOTE]
> This package is a work in progress. It currently contains only a placeholder
> module while the repository scaffolding is established.

```roc
expect Time.hello("World") == "Hello, World!"
```

## Documentation

See [lukewilliamboswell.github.io/roc-time/](https://lukewilliamboswell.github.io/roc-time/)

Locally generate versioned docs using `python3 scripts/docs.py 0.1.0`.

## Examples

Run an example with `roc examples/hello.roc`.

## Scripts

All repository tooling lives in `scripts/` and is written in Python 3 with no
third-party dependencies.

| Script | Purpose |
| --- | --- |
| `all_tests.py` | Full local CI run: check, test, docs, bundle, examples |
| `bundle.py` | Bundle `package/` into a distributable `.tar.zst` |
| `docs.py` | Generate versioned docs into `www/<version>` |
| `test_bundle_examples.py` | Verify the examples against a bundled package served over localhost |
| `update_example_urls.py` | Point the examples at a released bundle URL |

These are Python rather than Roc for one reason: verifying the examples against
a bundle requires serving it over `http://localhost` (Roc rejects `file://` and
local paths for package dependencies), and `basic-cli` currently has no way to
spawn a background process or listen on a socket. Once that lands upstream the
scripts can be rewritten in Roc.

## Contributing

If you see anything that could be improved please create an Issue or Pull Request.

## Tests

Run the full CI check locally with `python3 scripts/all_tests.py`.

The Roc compiler version used by CI is pinned in `.roc-version`.

## Packaging

Bundle the package for distribution using `python3 scripts/bundle.py --output-dir dist`.

Run the release workflow from GitHub Actions with a release version such as `0.1.0`.
It builds and tests the bundle, creates the GitHub release, generates versioned docs,
commits the generated `www/` update, and publishes the docs to GitHub Pages.
