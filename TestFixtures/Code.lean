/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

#doc (Slides) "Code Fixture" =>

# Dark Code

```lean
def hello : IO Unit := do
  IO.println "Hello from VersoSlides!"
```

```lean
#check hello
```

# Light Code
%%%
backgroundColor := some "#f5f5f5"
%%%

```lean
def greet (name : String) : String :=
  s!"Hello, {name}!"

#eval greet "Lean"
```

# Proof

```lean
theorem and_comm_ex (p q : Prop) (h : p ∧ q) : q ∧ p := by
  obtain ⟨hp, hq⟩ := h
  exact ⟨hq, hp⟩
```

# Inline Lean

The function {lean}`hello` was defined above.
Also try {lean}`Nat.add`.

# Fragment Effects

```lean
-- !fragment grow
def growDef : Nat := 1
-- !fragment highlight-current-red
def redDef : Nat := 2
```
