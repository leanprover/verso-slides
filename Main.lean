/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

-- Don't enable modules yet: SubVerso doesn't report missing Lean Code
-- Blocks hovers caused by missing `import all`.

-- module

import VersoSlides
import Demo

open VersoSlides

public def main : IO UInt32 :=
  slidesMain
    (config := { theme := "black", slideNumber := true, transition := "slide" })
    (doc := %doc Demo)
