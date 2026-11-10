/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

-- ANCHOR: double
def double (n : Nat) : Nat :=
  n + n
-- ANCHOR_END: double

-- ANCHOR: steps
def one : Nat := 1
-- !fragment
def two : Nat := 2
-- ANCHOR_END: steps

-- ANCHOR: proof
theorem double_eq (n : Nat) : double n = n + n := by
  rfl
-- ANCHOR_END: proof

-- ANCHOR: evalDouble
#eval double 21
-- ANCHOR_END: evalDouble

-- ANCHOR: brokenHide
def visible : Nat := 1
-- !hide
def hidden : Nat := 2
-- ANCHOR_END: brokenHide
