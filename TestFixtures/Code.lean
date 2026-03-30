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

# No Panel

```lean -panel
def noPanelDef : Nat := 99
```

# Replace

```lean
def replaced : Nat :=
  /- !replace ... -/ List.length [1, 2, 3] /- !end replace -/
```

# Comments

```lean
-- A line comment
def commented : Nat := 42
/- A block comment -/
```

# Eval Ordering

```lean
#eval s!"It is {1 + 1} first"
def evalMiddle := 5
#eval s!"Then it is {2 + 2}"
#eval s!"Then it is {4 + 4}"
```

# Eval Multiline

```lean
#eval 1 +

  2 +

3
```

# Check Ordering

```lean
def checkTarget := 42
#check checkTarget
def checkMiddle := "hi"
#check checkMiddle
```

# Print Ordering

```lean
def printTarget := 100
#print printTarget
def printMiddle := true
#print printMiddle
```

# Reduce Ordering

```lean
#reduce 2 + 3
def reduceMiddle := 10
#reduce 10 * 2
```

# Expected Error

```lean +error
#check (42 : String)
```

# Rust Code

```code rust
fn main() {
    let nums = vec![3, 1, 4, 1, 5];
    for n in &nums {
        println!("{n}");
    }
}
```
