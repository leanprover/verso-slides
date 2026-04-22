/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import VersoUtil.BinFiles
import TestFixtures.Markup
import TestFixtures.Code
import TestFixtures.DiagramAnim
import TestFixtures.Theme

open VersoSlides
open Verso.BinFiles

/-- Markup fixture uses a subdirectory in the extraCss filename. -/
def markupBannerCss : CssFile where
  filename := "themes/custom-banner.css"
  contents := ⟨include_str "custom-theme.css"⟩

/--
Theme fixture uses a subdirectory in the custom theme filename AND
bundles an image asset pulled in via `include_bin_dir`.
-/
def themeFixtureTheme : CustomTheme where
  stylesheet := { filename := "theme/custom.css"
                  contents := ⟨include_str "theme-base.css"⟩ }
  assets := ThemeAsset.fromDir (include_bin_dir "theme-assets")

/-- Theme fixture also carries a subdirectory extraCss entry. -/
def themeFixtureExtra : CssFile where
  filename := "css/extra.css"
  contents := ⟨include_str "theme-extra.css"⟩

def main : IO UInt32 := do
  let rc ← slidesMain
    { theme := "black", outputDir := "_test/markup", extraCss := #[markupBannerCss]
      mathPrelude := "\\def\\RR{\\mathbb{R}}\n\\newcommand{\\Hom}[2]{\\mathrm{Hom}(#1, #2)}\n" }
    (%doc TestFixtures.Markup)
  if rc != 0 then return rc
  let rc ← slidesMain
    { theme := "black", outputDir := "_test/code" }
    (%doc TestFixtures.Code)
  if rc != 0 then return rc
  let rc ← slidesMain
    { theme := "black", outputDir := "_test/diagramanim" }
    (%doc TestFixtures.DiagramAnim)
  if rc != 0 then return rc
  slidesMain
    { theme := .custom themeFixtureTheme, outputDir := "_test/theme",
      extraCss := #[themeFixtureExtra] }
    (%doc TestFixtures.Theme)
