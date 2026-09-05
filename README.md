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

Locally generate versioned docs using `./docs.sh 0.1.0`.

## Examples

Run an example with `roc examples/hello.roc`.

## Contributing

If you see anything that could be improved please create an Issue or Pull Request.

## Tests

Run the full CI check locally with `./ci/all_tests.sh`.

The Roc compiler version used by CI is pinned in `.roc-version`.

## Packaging

Bundle the package for distribution using `scripts/bundle.sh --output-dir dist`.

Run the release workflow from GitHub Actions with a release version such as `0.1.0`.
It builds and tests the bundle, creates the GitHub release, generates versioned docs,
commits the generated `www/` update, and publishes the docs to GitHub Pages.
