import os
import pytest
import random
import socket
import subprocess
import time
from pathlib import Path
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

DEFAULT_SITE_DIR = "../_test"
ALL_BROWSERS = ("chromium", "firefox")
# Env var used to share a --browser=random choice between the xdist master
# and its worker processes (workers inherit the env, so they agree).
RANDOM_BROWSER_ENV = "VERSO_TESTS_RANDOM_BROWSER"


def find_free_port():
    """Find an available port by binding to port 0."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def pytest_addoption(parser):
    parser.addoption(
        "--port",
        action="store",
        default=None,
        help="Port for the local test server (default: auto-select)"
    )
    parser.addoption(
        "--site-dir",
        action="store",
        default=DEFAULT_SITE_DIR,
        help="Path to the built site directory"
    )
    parser.addoption(
        "--server-url",
        action="store",
        default=None,
        help="Use an existing server instead of starting one (e.g., http://localhost:3000)"
    )
    parser.addoption(
        "--browser",
        action="store",
        default="all",
        choices=("all", "chromium", "firefox", "random"),
        help=(
            "Which browser(s) to run page-using tests against. "
            "'all' (default) runs every test in both Chromium and Firefox. "
            "'chromium' or 'firefox' picks one. "
            "'random' flips a coin once per session to pick one browser."
        ),
    )


def _resolve_browsers(config):
    """Translate the --browser option into the list of browsers to parametrize over.

    For --browser=random we need every pytest-xdist worker to agree on the
    same coin-flip; otherwise workers collect different parametrized test
    sets and xdist aborts. We stash the pick in an env var so worker
    subprocesses inherit it from the master.
    """
    cached = getattr(config, "_resolved_browsers", None)
    if cached is not None:
        return cached
    opt = config.getoption("--browser")
    if opt == "all":
        browsers = list(ALL_BROWSERS)
    elif opt == "random":
        chosen = os.environ.get(RANDOM_BROWSER_ENV)
        if chosen not in ALL_BROWSERS:
            chosen = random.choice(ALL_BROWSERS)
            os.environ[RANDOM_BROWSER_ENV] = chosen
        browsers = [chosen]
    else:
        browsers = [opt]
    config._resolved_browsers = browsers
    return browsers


def pytest_report_header(config):
    browsers = _resolve_browsers(config)
    mode = config.getoption("--browser")
    return f"browsers: {', '.join(browsers)} (--browser={mode})"


def pytest_generate_tests(metafunc):
    if "browser" in metafunc.fixturenames:
        browsers = _resolve_browsers(metafunc.config)
        metafunc.parametrize("browser", browsers, indirect=True, ids=browsers, scope="session")


@pytest.fixture(scope="session")
def site_dir(request):
    """Resolved path to the built test fixtures directory."""
    d = request.config.getoption("--site-dir")
    return Path(__file__).parent / d


@pytest.fixture(scope="session")
def markup_doc(site_dir):
    """Parse _test/markup/index.html with BeautifulSoup (markup fixture)."""
    html_path = site_dir / "markup" / "index.html"
    assert html_path.exists(), f"Markup fixture not found at {html_path}. Run 'lake exe test-fixtures-build' first."
    with open(html_path) as f:
        return BeautifulSoup(f.read(), "html.parser")


@pytest.fixture(scope="session")
def code_doc(site_dir):
    """Parse _test/code/index.html with BeautifulSoup (code fixture)."""
    html_path = site_dir / "code" / "index.html"
    assert html_path.exists(), f"Code fixture not found at {html_path}. Run 'lake exe test-fixtures-build' first."
    with open(html_path) as f:
        return BeautifulSoup(f.read(), "html.parser")


@pytest.fixture(scope="session")
def diagramanim_doc(site_dir):
    """Parse _test/diagramanim/index.html with BeautifulSoup (diagram/animation fixture)."""
    html_path = site_dir / "diagramanim" / "index.html"
    assert html_path.exists(), f"DiagramAnim fixture not found at {html_path}. Run 'lake exe test-fixtures-build' first."
    with open(html_path) as f:
        return BeautifulSoup(f.read(), "html.parser")


@pytest.fixture(scope="session")
def theme_doc(site_dir):
    """Parse _test/theme/index.html with BeautifulSoup (custom-theme fixture)."""
    html_path = site_dir / "theme" / "index.html"
    assert html_path.exists(), f"Theme fixture not found at {html_path}. Run 'lake exe test-fixtures-build' first."
    with open(html_path) as f:
        return BeautifulSoup(f.read(), "html.parser")


@pytest.fixture(scope="session")
def server(request, site_dir):
    """Start a local HTTP server for the built site, or use an existing one."""
    external_url = request.config.getoption("--server-url")

    if external_url:
        yield external_url
        return

    port = request.config.getoption("--port")

    if port is None:
        port = find_free_port()
    else:
        port = int(port)

    proc = subprocess.Popen(
        ["python", "-m", "http.server", str(port), "--bind", "127.0.0.1"],
        cwd=site_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(1)
    yield f"http://127.0.0.1:{port}"
    proc.terminate()
    proc.wait()


@pytest.fixture(scope="session")
def markup_url(server):
    """Base URL for the markup fixture."""
    return f"{server}/markup"


@pytest.fixture(scope="session")
def code_url(server):
    """Base URL for the code fixture."""
    return f"{server}/code"


@pytest.fixture(scope="session")
def diagramanim_url(server):
    """Base URL for the diagram/animation fixture."""
    return f"{server}/diagramanim"


@pytest.fixture(scope="session")
def theme_url(server):
    """Base URL for the custom-theme fixture."""
    return f"{server}/theme"


@pytest.fixture(scope="session")
def playwright_instance():
    with sync_playwright() as p:
        yield p


@pytest.fixture(scope="session")
def browser(request, playwright_instance):
    """Browser fixture parametrized by pytest_generate_tests from --browser."""
    browser_type = request.param
    browser = getattr(playwright_instance, browser_type).launch()
    yield browser
    browser.close()


@pytest.fixture
def page(browser):
    page = browser.new_page()
    yield page
    page.close()


_REVEAL_READY_EXPR = "() => !!(window.Reveal && window.Reveal.isReady && window.Reveal.isReady())"


def wait_for_reveal_ready(page, timeout=10000):
    """Wait until reveal.js has finished initialising on the current page.

    Replaces the old `wait_for_load_state("networkidle") + wait_for_timeout(1000)`
    combo — polls Reveal.isReady() instead, which resolves as soon as the
    presentation is interactive (usually well under a second).
    """
    page.wait_for_function(_REVEAL_READY_EXPR, timeout=timeout)


def goto_slide_by_title(page, base_url, title):
    """Navigate to a slide by its heading text.

    Uses Reveal.js's slide indexing: finds the section whose heading matches
    *title*, computes its index among top-level sections, and navigates to
    ``#/<index>``.
    """
    page.goto(f"{base_url}/index.html")
    wait_for_reveal_ready(page)
    index = page.evaluate("""(title) => {
        const sections = document.querySelectorAll('.slides > section');
        for (let i = 0; i < sections.length; i++) {
            const h = sections[i].querySelector('h1, h2, h3');
            if (h && h.textContent.trim() === title) return i;
        }
        return -1;
    }""", title)
    assert index >= 0, f"Slide with title '{title}' not found"
    page.goto(f"{base_url}/index.html#/{index}")
    # Reveal is already ready from the first goto; wait briefly for the
    # slide transition to settle before returning.
    page.wait_for_function(
        "(i) => window.Reveal && window.Reveal.getIndices().h === i",
        arg=index,
    )
    return page.locator(".slides > section").nth(index)
