/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

module

import TestFixtures.Pretty

open Std
open VersoSlides.Pretty TestFixtures.Pretty

namespace Tests.Pretty

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

private def testEq [BEq α] [Repr α] (name : String) (actual expected : α) : TestM Unit := do
  if actual == expected then
    modify fun s => { s with passed := s.passed + 1 }
  else
    modify fun s => { s with
      failed := s.failed + 1
      errors := s.errors.push
        s!"FAIL: {name}\n  expected: {reprStr expected}\n  actual:   {reprStr actual}" }

def main : IO UInt32 := do
  let ((), state) ← tests.run {}
  state.report
where
  tests : TestM Unit := do
    testEq "empty array" (VersoSlides.VirPrettyM.formatSegments .nil 80 0) #[]
    for (name, format, width, indent) in corpusCases do
      let segments := VersoSlides.VirPrettyM.formatSegments format width indent
      testEq name (String.join <| segments.toList.map (·.text))
        (format.pretty width indent)
    testEq "tagged segment" (VersoSlides.VirPrettyM.formatSegments taggedDoc 80 0)
      #[{ text := "hello", tags := #[7] }]
    testEq "nested tag stack" (VersoSlides.VirPrettyM.formatSegments nestedTaggedDoc 80 0)
      #[
        { text := "outer", tags := #[7] },
        { text := "inner", tags := #[7, 8] },
        { text := "tail", tags := #[7] }
      ]
    testEq "tagged newline"
      (VersoSlides.VirPrettyM.formatSegments (.tag 7 ("left" ++ .line ++ "right")) 80 0)
      #[{ text := "left", tags := #[7] }, { text := "\n", tags := #[7] },
        { text := "right", tags := #[7] }]
    testEq "after tag"
      (VersoSlides.VirPrettyM.formatSegments (.tag 7 "x" ++ "plain") 80 0)
      #[{ text := "x", tags := #[7] }, { text := "plain", tags := #[] }]

end Tests.Pretty

public def main : IO UInt32 :=
  Tests.Pretty.main
