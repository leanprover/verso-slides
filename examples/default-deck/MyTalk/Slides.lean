/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

module

public import VersoSlides

open VersoSlides

#doc (Slides) "A deck with built-in VIR prettyM" =>

# No application runtime declaration

Click a tactic to render its goal using the built-in VIR formatter.

```lean
example (p q : Prop) (h : p ∧ q) : q ∧ p := by
  obtain ⟨hp, hq⟩ := h
  exact ⟨hq, hp⟩
```
