/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
  Tests for the magic comment parsers.
-/
import VersoSlides.SlideCode.CommentParsers

open VersoSlides


structure TestState where
  passed : Nat := 0
  failed : Nat := 0
  errors : Array String := #[]

def TestState.report (s : TestState) : IO UInt32 := do
  if s.errors.isEmpty then
    IO.println s!"All {s.passed} tests passed."
    return 0
  else
    for e in s.errors do
      IO.eprintln e
    IO.eprintln s!"\n{s.failed} of {s.passed + s.failed} tests FAILED."
    return 1

abbrev TestM := StateRefT TestState IO

def testFrag (name : String) (input : String) (expected : Option FragmentData) : TestM Unit := do
  let actual := parseFragmentBreak input
  if actual == expected then
    modify fun s => { s with passed := s.passed + 1 }
  else
    modify fun s => { s with
      failed := s.failed + 1
      errors := s.errors.push s!"FAIL: {name}\n  expected: {repr expected}\n  actual:   {repr actual}"
    }

def testClick (name : String) (input : String) (expected : Option (Nat × Option Nat)) : TestM Unit := do
  let actual := parseClickComment input
  if actual == expected then
    modify fun s => { s with passed := s.passed + 1 }
  else
    modify fun s => { s with
      failed := s.failed + 1
      errors := s.errors.push s!"FAIL: {name}\n  expected: {repr expected}\n  actual:   {repr actual}"
    }


def main : IO UInt32 := do
  let ((), s) ← tests.run {}
  s.report
where
  tests : TestM Unit := do

    ---- parseFragmentBreak ----

    testFrag "empty string" "" none
    testFrag "bare comment" "-- " none
    testFrag "plain fragment" "-- !fragment" (some ⟨none, none⟩)
    testFrag "fragment with trailing alpha" "-- !fragmentx" none
    testFrag "fragment with style" "-- !fragment x" (some ⟨some "x", none⟩)
    testFrag "fragment with style and index" "-- !fragment x 5" (some ⟨some "x", some 5⟩)
    testFrag "fragment with index only" "-- !fragment 5" (some ⟨none, some 5⟩)
    testFrag "fragment with index then alpha" "-- !fragment 5 x" none

    ---- parseClickComment ----

    testClick "empty string" "" none
    testClick "bare comment" "-- " none
    testClick "click without caret" "-- !click" none
    testClick "basic click" "-- ^ !click" (some (3, none))
    testClick "click with trailing alpha" "-- ^ !clicky" none
    testClick "click with index" "-- ^ !click 5" (some (3, some 5))
    testClick "click extra spaces" "--  ^  !click    5" (some (4, some 5))
    testClick "click with leading indent" "  -- ^ !click" (some (5, none))
    testClick "click extra space before caret" "--  ^  !click" (some (4, none))
    testClick "double caret rejected" "-- ^^ !click" none
    testClick "click with index then junk" "-- ^ !click 5 x" none
