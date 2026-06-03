/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

-- Setting this option to `false` makes flag-less code boxes render without a
-- panel; individual boxes can still opt back in with `+panel`.
set_option verso.slides.panel false

#doc (Slides) "Panel Option Fixture" =>

# Panel Off By Default

```lean
def optNoPanelDef : Nat := 1
```

```lean +panel -stretch
def optPanelDef : Nat := 2
```
