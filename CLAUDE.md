# VersoSlides — working notes for Claude

## Testing

Run **both** the fixture build and the Playwright tests after any
change that affects rendering (directives, CSS, HTML templates, Verso
genre internals):

```
scripts/test.sh
```

This runs `lake test` (the Lean-side test driver), then
`lake exe test-fixtures-build`, then `uv run pytest` in
`browser-tests/`, failing if any step fails. Extra args are forwarded
to pytest, so `scripts/test.sh test_tables.py -v` works for narrowing
down the browser tests.

A passing `lake build` alone is **not** enough — it only proves the
code compiles, not that slides render correctly.

## Documentation

Whenever user-visible behaviour changes — new directives, new flags or
arguments on existing directives, new roles, new metadata fields,
changes to default rendering or to the executable's CLI — check that
`README.md` still describes the feature accurately. Add a section for
new features, update existing sections when behaviour changes, and
keep the usage examples in sync with the real syntax (flags, argument
names, fence styles). A code change without a matching README update
should be treated as incomplete.
