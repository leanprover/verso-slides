# Contributing to VersoSlides

## Running the Test Suite

The full test run (Lean tests, fixture build, JS type-checks,
formatting, and Playwright browser tests) is:

```
scripts/test.sh
```

Extra arguments are forwarded to pytest, so
`scripts/test.sh test_tables.py -v` narrows down the browser tests. A
passing `lake build` alone is _not_ enough: it only proves the code
compiles, not that slides render correctly.

### Parallel Browser Tests

`scripts/test.sh` runs the Playwright suite with
[`pytest-xdist`](https://pytest-xdist.readthedocs.io/) using 4 workers
by default. This gives roughly a 3–4× speedup over a serial run
without tripping over browser process contention.

- Override the worker count with the `PYTEST_WORKERS` env var:
    ```
    PYTEST_WORKERS=2 scripts/test.sh      # fewer workers
    PYTEST_WORKERS=auto scripts/test.sh   # xdist's auto (cpu_count)
    PYTEST_WORKERS=1 scripts/test.sh      # effectively serial
    ```
- `PYTEST_WORKERS=auto` is flaky on machines with many cores because
  each worker launches its own Chromium; stick with a small integer
  unless you've verified your setup handles more.

### Choosing Browsers (`--browser`)

The browser tests are parametrized over Chromium and Firefox. Use
`--browser` to narrow that down:

| Value      | Behavior                                                  |
| ---------- | --------------------------------------------------------- |
| `all`      | (default, CI) run every test in both Chromium and Firefox |
| `chromium` | Chromium only                                             |
| `firefox`  | Firefox only                                              |
| `random`   | flip a coin once per session and pick one browser         |

Examples:

```
scripts/test.sh --browser=chromium          # fastest local loop
scripts/test.sh --browser=random            # rotate coverage
scripts/test.sh --browser=firefox test_panel.py
```

CI must keep the default `--browser=all` so both browsers are always
exercised. For day-to-day local work, `--browser=random` is a good
compromise. Any single run is single-browser and fast, but over time
both browsers get exercised. There's no strong performance reason to
prefer one over the other locally.

### Running pytest Directly

`pytest` must be invoked from the `browser-tests/` directory (that's
where the `pyproject.toml` lives):

```
cd browser-tests
uv run pytest                          # serial, both browsers
uv run pytest -n 4                     # 4 workers
uv run pytest --browser=chromium       # Chromium only
uv run pytest test_lightbox.py -v      # narrow + verbose
```

The session report header shows the resolved browser list, which is
useful for `--browser=random`:

```
browsers: firefox (--browser=random)
```

## Documentation

When user-visible behaviour changes (new directives, new flags or
arguments on existing directives, new roles, new metadata fields,
changes to default rendering or to the executable's CLI), check that
`README.md` still describes the feature accurately.
