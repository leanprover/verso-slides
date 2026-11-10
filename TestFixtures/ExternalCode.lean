/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

module

public import VersoSlides

open VersoSlides

set_option verso.exampleProject "TestFixtures/external-example"
set_option verso.exampleModule "Example"

#doc (Slides) "External Code Fixture" =>

# External Anchor

```anchor double
def double (n : Nat) : Nat :=
  n + n
```

# External No Layout

```anchor double -panel -stretch
def double (n : Nat) : Nat :=
  n + n
```

# External Fragments

```anchor steps
def one : Nat := 1
-- !fragment
def two : Nat := 2
```

# External No Proof States

```anchor proof -showProofStates
theorem double_eq (n : Nat) : double n = n + n := by
  rfl
```

# External Roles

The function {anchorName double}`double` has the body {anchorTerm double}`n + n`.

# External Output

```anchorInfo evalDouble
42
```
