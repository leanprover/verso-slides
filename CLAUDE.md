# VersoSlides — working notes for Claude

## Testing

Run **both** the fixture build and the Playwright tests after any change that affects
rendering (directives, CSS, HTML templates, Verso genre internals):

```
scripts/test.sh
```

This runs `lake test` (the Lean-side test driver), then `lake exe test-fixtures-build`,
then `uv run pytest` in `browser-tests/`, failing if any step fails. Extra args are
forwarded to pytest, so `scripts/test.sh test_tables.py -v` works for narrowing down
the browser tests.

A passing `lake build` alone is **not** enough — it only proves the code compiles,
not that slides render correctly.
