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
import Verso.Output.Html.KaTeX

namespace VersoSlides.Vendor

def resetCss  := include_str "vendor/reveal.js/dist/reset.css"
def revealCss := include_str "vendor/reveal.js/dist/reveal.css"
def revealJs  := include_str "vendor/reveal.js/dist/reveal.js"

def themeBlack     := include_str "vendor/reveal.js/dist/theme/black.css"
def themeWhite     := include_str "vendor/reveal.js/dist/theme/white.css"
def themeLeague    := include_str "vendor/reveal.js/dist/theme/league.css"
def themeBeige     := include_str "vendor/reveal.js/dist/theme/beige.css"
def themeNight     := include_str "vendor/reveal.js/dist/theme/night.css"
def themeMoon      := include_str "vendor/reveal.js/dist/theme/moon.css"
def themeSerif     := include_str "vendor/reveal.js/dist/theme/serif.css"
def themeSimple    := include_str "vendor/reveal.js/dist/theme/simple.css"
def themeSky       := include_str "vendor/reveal.js/dist/theme/sky.css"
def themeSolarized := include_str "vendor/reveal.js/dist/theme/solarized.css"
def themeBlood     := include_str "vendor/reveal.js/dist/theme/blood.css"
def themeDracula   := include_str "vendor/reveal.js/dist/theme/dracula.css"
def themeBlackContrast := include_str "vendor/reveal.js/dist/theme/black-contrast.css"
def themeWhiteContrast := include_str "vendor/reveal.js/dist/theme/white-contrast.css"

/-- Looks up a theme CSS string by name. Returns `none` for unknown themes. -/
def themeCSS (name : String) : Option String :=
  match name with
  | "black"          => some themeBlack
  | "white"          => some themeWhite
  | "league"         => some themeLeague
  | "beige"          => some themeBeige
  | "night"          => some themeNight
  | "moon"           => some themeMoon
  | "serif"          => some themeSerif
  | "simple"         => some themeSimple
  | "sky"            => some themeSky
  | "solarized"      => some themeSolarized
  | "blood"          => some themeBlood
  | "dracula"        => some themeDracula
  | "black-contrast" => some themeBlackContrast
  | "white-contrast" => some themeWhiteContrast
  | _                => none


def notesJs     := include_str "vendor/reveal.js/plugin/notes/notes.js"
def highlightJs := include_str "vendor/reveal.js/plugin/highlight/highlight.js"
def monokaiCss  := include_str "vendor/reveal.js/plugin/highlight/monokai.css"
def mathJs      := include_str "vendor/reveal.js/plugin/math/math.js"

def markedJs := include_str "vendor/marked/marked.min.js"

def katexCss   := Verso.Output.Html.katex.css
def katexJs    := Verso.Output.Html.katex.js
def katexFonts := Verso.Output.Html.katexFonts

end VersoSlides.Vendor
