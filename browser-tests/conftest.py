import pytest
import socket
import subprocess
import time
from pathlib import Path
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

DEFAULT_SITE_DIR = "../_test"


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
def playwright_instance():
    with sync_playwright() as p:
        yield p


@pytest.fixture(scope="session", params=["chromium", "firefox"])
def browser(request, playwright_instance):
    """Parameterized fixture to run tests in multiple browsers."""
    browser_type = request.param
    browser = getattr(playwright_instance, browser_type).launch()
    yield browser
    browser.close()


@pytest.fixture
def page(browser):
    page = browser.new_page()
    yield page
    page.close()


def goto_slide_by_title(page, base_url, title):
    """Navigate to a slide by its heading text.

    Uses Reveal.js's slide indexing: finds the section whose heading matches
    *title*, computes its index among top-level sections, and navigates to
    ``#/<index>``.
    """
    page.goto(f"{base_url}/index.html")
    page.wait_for_load_state("networkidle")
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
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(1000)
    return page.locator(".slides > section").nth(index)
