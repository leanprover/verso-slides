#!/usr/bin/env bash
# Vendor fonts referenced by reveal.js themes so presentations render
# correctly with no network access.
#
# Two sources:
#   1. Upstream reveal.js (`hakimel/reveal.js`) ships local fonts under
#      `css/theme/fonts/{source-sans-pro,league-gothic}` — fetched verbatim.
#   2. Several themes `@import` Google Fonts CSS over the network. We fetch
#      that CSS via the v1 API (woff2 per face/subset), download every
#      woff2 file, rewrite the URLs to be relative, and write a sibling CSS
#      file under `vendor/reveal.js/dist/theme/fonts/<family>/`.
#
# The vendored theme `.css` files in `vendor/reveal.js/dist/theme/` are NOT
# touched — they keep their original `@import` of `fonts.googleapis.com` so
# upstream bumps stay byte-for-byte refreshable. The Lean side strips/rewrites
# those `@import` lines at copy time (see `rewriteGoogleFontImports` in
# `VersoSlidesVendored.lean`).
#
# Re-run from the repo root after a reveal.js bump or to refresh fonts.

set -euo pipefail

cd "$(dirname "$0")/.."

REPO_RAW="https://raw.githubusercontent.com/hakimel/reveal.js/master/css/theme/fonts"
THEME_DIR="vendor/reveal.js/dist/theme"
FONTS_DIR="$THEME_DIR/fonts"

# A modern UA so Google Fonts returns woff2 (smaller, universally supported).
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

mkdir -p "$FONTS_DIR"

# --- 1. Local fonts shipped by upstream reveal.js -------------------------

fetch_upstream_font() {
    local family="$1"; shift
    local dir="$FONTS_DIR/$family"
    rm -rf "$dir"
    mkdir -p "$dir"
    for f in "$@"; do
        echo "  $family/$f"
        curl -sfL "$REPO_RAW/$family/$f" -o "$dir/$f"
    done
}

echo "Fetching upstream reveal.js local fonts..."
fetch_upstream_font source-sans-pro \
    LICENSE \
    source-sans-pro.css \
    source-sans-pro-regular.woff \
    source-sans-pro-italic.woff \
    source-sans-pro-semibold.woff \
    source-sans-pro-semibolditalic.woff

fetch_upstream_font league-gothic \
    LICENSE \
    league-gothic.css \
    league-gothic.woff

# --- 2. Google Fonts vendored locally -------------------------------------

# Fetch the Google Fonts v1 CSS for `family_spec` and convert it to a
# self-contained directory: one .woff2 per face (or face+subset) plus a CSS
# file with relative URLs.
fetch_google_font() {
    local slug="$1"        # local directory name, e.g. "lato"
    local family_spec="$2" # value of family= query param, e.g. "Lato:400,700,400italic,700italic"

    local dir="$FONTS_DIR/$slug"
    rm -rf "$dir"
    mkdir -p "$dir"
    echo "Fetching Google Fonts: $slug ($family_spec)"

    local css
    css=$(curl -sfL -A "$UA" "https://fonts.googleapis.com/css?family=${family_spec// /+}")

    local idx=0
    local rewritten=""
    while IFS= read -r line; do
        if [[ "$line" =~ src:\ url\((https://fonts\.gstatic\.com/[^\)]*)\) ]]; then
            local url="${BASH_REMATCH[1]}"
            local face_name
            face_name=$(printf "%s-%03d.woff2" "$slug" "$idx")
            idx=$((idx + 1))
            curl -sfL -A "$UA" "$url" -o "$dir/$face_name"
            rewritten+="  src: url('./$face_name') format('woff2');"$'\n'
        else
            rewritten+="$line"$'\n'
        fi
    done <<<"$css"
    printf "%s" "$rewritten" >"$dir/$slug.css"
}

# Themes and the font specs they need (matched to the `@import` URLs in the
# upstream theme CSS files):
#   beige, league, moon, solarized -> Lato 400/700, italic
#   blood                          -> Ubuntu 300/700, italic
#   night                          -> Montserrat 700, Open Sans 400/700 italic
#   simple                         -> News Cycle 400/700, Lato
#   sky                            -> Quicksand 400/700 italic, Open Sans
fetch_google_font lato        "Lato:400,700,400italic,700italic"
fetch_google_font ubuntu      "Ubuntu:300,700,300italic,700italic"
fetch_google_font montserrat  "Montserrat:700"
fetch_google_font open-sans   "Open+Sans:400,700,400italic,700italic"
fetch_google_font news-cycle  "News+Cycle:400,700"
fetch_google_font quicksand   "Quicksand:400,700,400italic,700italic"

echo "Done. Vendored fonts written under $FONTS_DIR."
echo "Theme CSS files in $THEME_DIR are unchanged from upstream;"
echo "the Lean side rewrites their Google-Fonts \`@import\` lines at copy time."
