/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
  VersoSlidesVendored - Vendored third-party assets embedded at compile time

  This is a separate Lake library so that `input_dir` tracking in the lakefile
  triggers a rebuild when any file under `vendor/` changes.
-/
module
public import Verso.Output.Html.KaTeX
public import VersoManual.Html.CssFile
public meta import VersoUtil.BinFiles
public import VersoUtil.BinFiles.Z85

namespace VersoSlides.Vendor

public def resetCss := include_str "vendor/reveal.js/dist/reset.css"
public def revealCss := include_str "vendor/reveal.js/dist/reveal.css"
public def revealJs := include_str "vendor/reveal.js/dist/reveal.js"

public def themeBlack := include_str "vendor/reveal.js/dist/theme/black.css"
public def themeWhite := include_str "vendor/reveal.js/dist/theme/white.css"
public def themeLeague := include_str "vendor/reveal.js/dist/theme/league.css"
public def themeBeige := include_str "vendor/reveal.js/dist/theme/beige.css"
public def themeNight := include_str "vendor/reveal.js/dist/theme/night.css"
public def themeMoon := include_str "vendor/reveal.js/dist/theme/moon.css"
public def themeSerif := include_str "vendor/reveal.js/dist/theme/serif.css"
public def themeSimple := include_str "vendor/reveal.js/dist/theme/simple.css"
public def themeSky := include_str "vendor/reveal.js/dist/theme/sky.css"
public def themeSolarized := include_str "vendor/reveal.js/dist/theme/solarized.css"
public def themeBlood := include_str "vendor/reveal.js/dist/theme/blood.css"
public def themeDracula := include_str "vendor/reveal.js/dist/theme/dracula.css"
public def themeBlackContrast := include_str "vendor/reveal.js/dist/theme/black-contrast.css"
public def themeWhiteContrast := include_str "vendor/reveal.js/dist/theme/white-contrast.css"

/-- Looks up a theme CSS string by name. Returns `none` for unknown themes. -/
public def themeCSS (name : String) : Option String :=
  match name with
  | "black" => some themeBlack
  | "white" => some themeWhite
  | "league" => some themeLeague
  | "beige" => some themeBeige
  | "night" => some themeNight
  | "moon" => some themeMoon
  | "serif" => some themeSerif
  | "simple" => some themeSimple
  | "sky" => some themeSky
  | "solarized" => some themeSolarized
  | "blood" => some themeBlood
  | "dracula" => some themeDracula
  | "black-contrast" => some themeBlackContrast
  | "white-contrast" => some themeWhiteContrast
  | _ => none

/-!
## Theme fonts

Several `reveal.js` themes import their typefaces over the network:
* `white` / `white-contrast` / `black` / `black-contrast` import a sibling
  `fonts/source-sans-pro/source-sans-pro.css`, expecting upstream's local font files alongside.
* `beige` / `league` / `moon` / `solarized` similarly use `league-gothic`, plus a Google Fonts
  `@import` of Lato.
* `blood`, `night`, `simple`, `sky` each `@import` one or two Google Fonts CSS URLs.

Upstream reveal.js's `dist/theme/` ships only the bare `.css` files (no `fonts/` subdir), and
Google-Fonts `@import` URLs require network access. For decks to render correctly offline, we vendor
every required font and:

  1. Bundle the woff/woff2 plus a sibling CSS with relative URLs under
     `vendor/reveal.js/dist/theme/fonts/<slug>/` (see `scripts/vendor-fonts.sh`).
  2. Look up which subset of those bundles each theme needs (`themeFonts`).
  3. Strip the network `@import` lines from the theme CSS at copy time and replace them with local
     imports (`rewriteGoogleFontImports`).

The vendored theme CSS files in `vendor/reveal.js/dist/theme/*.css` stay byte-for-byte identical to
upstream so `reveal.js` bumps refresh cleanly.
-/

private def stripFontsPrefix (xs : Array (String × ByteArray)) : Array (String × ByteArray) :=
  xs.map fun (name, c) =>
    (name.dropPrefix "vendor/reveal.js/dist/theme/" |>.copy, c)

private def sourceSansProFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/source-sans-pro")
private def leagueGothicFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/league-gothic")
private def latoFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/lato")
private def ubuntuFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/ubuntu")
private def montserratFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/montserrat")
private def openSansFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/open-sans")
private def newsCycleFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/news-cycle")
private def quicksandFiles : Array (String × ByteArray) :=
  stripFontsPrefix (include_bin_dir "vendor/reveal.js/dist/theme/fonts/quicksand")

/--
The font files needed for a built-in theme. Each entry is a path relative to
`dist/theme/` (e.g. `"fonts/lato/lato.css"`) paired with the file's bytes.
Unknown theme names yield an empty array.

Custom themes added to this repo (`white_contrast_compact_verbatim_headers`)
also map to the appropriate upstream fonts.
-/
public def themeFonts (name : String) : Array (String × ByteArray) :=
  match name with
  | "black" | "black-contrast"
  | "white" | "white-contrast"
  | "white_contrast_compact_verbatim_headers" =>
      sourceSansProFiles
  | "beige" | "league" | "moon" | "solarized" =>
      leagueGothicFiles ++ latoFiles
  | "blood" => ubuntuFiles
  | "night" => montserratFiles ++ openSansFiles
  | "simple" => newsCycleFiles ++ latoFiles
  | "sky" => quicksandFiles ++ openSansFiles
  | "dracula" => #[]
  | "serif" => #[]
  | _ => #[]

/--
Each entry pairs a Google Fonts family spec (the `family=` query value) with the slug of the locally
vendored copy. Both `@import "https://..."` and `@import url(https://...)` syntaxes appear across
reveal.js versions, so `rewriteGoogleFontImports` strips both for every spec listed here.
-/
private def googleFontReplacements : List (String × String) := [
  ("Lato:400,700,400italic,700italic", "lato"),
  ("Ubuntu:300,700,300italic,700italic", "ubuntu"),
  ("Montserrat:700", "montserrat"),
  ("Open+Sans:400,700,400italic,700italic", "open-sans"),
  ("Open+Sans:400italic,700italic,400,700", "open-sans"),
  ("News+Cycle:400,700", "news-cycle"),
  ("Quicksand:400,700,400italic,700italic", "quicksand")
]

/--
Replace every Google-Fonts `@import` line in a reveal.js theme CSS string
with an `@import` of the locally vendored copy, so decks render correctly
without network access.

Handles both `@import "https://fonts.googleapis.com/...";` and the
`@import url(https://fonts.googleapis.com/...);` form.
-/
public def rewriteGoogleFontImports (css : String) : String := Id.run do
  let mut out := css
  for (spec, slug) in googleFontReplacements do
    let dst := s!"@import url(./fonts/{slug}/{slug}.css);"
    out := out.replace s!"@import \"https://fonts.googleapis.com/css?family={spec}\";" dst
    out := out.replace s!"@import url(https://fonts.googleapis.com/css?family={spec});" dst
  return out

public def notesJs := include_str "vendor/reveal.js/plugin/notes/notes.js"
public def highlightJs := include_str "vendor/reveal.js/plugin/highlight/highlight.js"
public def monokaiCss := include_str "vendor/reveal.js/plugin/highlight/monokai.css"

public def markedJs := include_str "vendor/marked/marked.min.js"

public def katexCss := Verso.Output.Html.katex.css
public def katexJs := Verso.Output.Html.katex.js
public def katexFonts := Verso.Output.Html.katexFonts

end VersoSlides.Vendor

namespace VersoSlides

/--
A highlight.js stylesheet for non-Lean code blocks. The `filename` is both
the output path (relative to the slideshow output directory) and the
`href` of the emitted `<link>` tag. Pick one of the bundled
`HighlightTheme` values with dot notation (e.g. `.githubDark`) or build
your own `Verso.Genre.Manual.CssFile`.
-/
public abbrev HighlightTheme := Verso.Genre.Manual.CssFile

namespace HighlightTheme

/-- Each bundled hl.js theme is written under `lib/{name}.css`. Only one
resolves per build, so the named outputs don't collide. Keeping the name
in the path makes the active theme obvious when inspecting the output
directory. -/
private def mk (name content : String) : HighlightTheme :=
  { filename := s!"lib/{name}.css", contents := ⟨content⟩ }

public def monokai := mk "monokai" (include_str "vendor/highlight.js/styles/monokai.css")
public def github := mk "github" (include_str "vendor/highlight.js/styles/github.css")
public def githubDark := mk "github-dark" (include_str "vendor/highlight.js/styles/github-dark.css")
public def atomOneLight := mk "atom-one-light" (include_str "vendor/highlight.js/styles/atom-one-light.css")
public def atomOneDark := mk "atom-one-dark" (include_str "vendor/highlight.js/styles/atom-one-dark.css")
public def tomorrow := mk "tomorrow" (include_str "vendor/highlight.js/styles/tomorrow.css")
public def solarizedLight := mk "solarized-light" (include_str "vendor/highlight.js/styles/solarized-light.css")
public def solarizedDark := mk "solarized-dark" (include_str "vendor/highlight.js/styles/solarized-dark.css")

/-- The default highlight.js theme paired with a built-in `reveal.js` theme. -/
public def forRevealTheme (name : String) : HighlightTheme :=
  match name with
  | "black" | "black-contrast" | "blood" | "dracula"
  | "league" | "moon" | "night" => monokai
  | "solarized" => solarizedLight
  | "white" | "white-contrast" | "beige"
  | "serif" | "simple" | "sky" => github
  | _ => monokai

end HighlightTheme

public instance : Inhabited HighlightTheme := ⟨.monokai⟩

end VersoSlides
