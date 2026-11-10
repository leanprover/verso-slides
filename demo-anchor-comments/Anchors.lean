import Anchors.CheckMsgs

-- ANCHOR: double
def double (n : Nat) : Nat :=
-- ANCHOR: body
  n + n
-- ANCHOR_END: body
-- ANCHOR_END: double

-- ANCHOR: reveal
def one : Nat := 1
-- !fragment
def two : Nat := double one
-- ANCHOR_END: reveal

-- ANCHOR: proof
theorem double_eq (n : Nat) : double n = 2 * n := by
  simp only [double]
  omega
-- ANCHOR_END: proof

-- ANCHOR: evalDouble
#eval double 21
-- ANCHOR_END: evalDouble

-- ANCHOR: unfinished
theorem unfinished : double 1 = 2 := by
  sorry
-- ANCHOR_END: unfinished

/-- error: Unknown identifier `missing` -/
#check_msgs in
-- ANCHOR: broken
def broken : Nat := missing
-- ANCHOR_END: broken
