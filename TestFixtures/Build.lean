/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import TestFixtures.Markup
import TestFixtures.Code
import TestFixtures.DiagramAnim

open VersoSlides

def main : IO UInt32 := do
  let rc ← slidesMain { theme := "black" } (%doc TestFixtures.Markup)
    ["--output", "_test/markup"]
  if rc != 0 then return rc
  let rc ← slidesMain { theme := "black" } (%doc TestFixtures.Code)
    ["--output", "_test/code"]
  if rc != 0 then return rc
  slidesMain { theme := "black" } (%doc TestFixtures.DiagramAnim)
    ["--output", "_test/diagramanim"]
