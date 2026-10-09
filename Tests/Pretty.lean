/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

module

import TestFixtures.Pretty

open Std
open VersoSlides.Pretty TestFixtures.Pretty

namespace Tests.Pretty

private def oraclePlain (format : Format) (width : Nat) : String :=
  String.join <| (VersoSlides.VirPrettyM.formatSegments format width 0).toList.map (·.text)

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

def main (args : List String) : IO UInt32 := do
  if args == ["--host-abi-corpus"] then
    IO.println nativeCorpusJson
    return 0
  if !args.isEmpty then
    IO.eprintln "usage: test-pretty [--host-abi-corpus]"
    return 1
  let ((), state) ← tests.run {}
  state.report
where
  tests : TestM Unit := do
    testEq "empty array" (VersoSlides.VirPrettyM.formatSegments .nil 80 0) #[]
    testEq "wide group" (oraclePlain groupedLineDoc 80) "hello world"
    testEq "narrow group" (oraclePlain groupedLineDoc 8) "hello\nworld"
    testEq "hard newline" (oraclePlain hardLineDoc 80) "αβ\nγ"
    testEq "nested align" (oraclePlain nestedDoc 5) ". a\n  b"
    testEq "fill paragraph" (oraclePlain paragraphDoc 16)
      "lean ir runs\nformat.pretty\ninside wasm"
    testEq "tagged segment" (VersoSlides.VirPrettyM.formatSegments taggedDoc 80 0)
      #[{ text := "hello", tags := #[7] }]
    testEq "nested tag stack" (VersoSlides.VirPrettyM.formatSegments nestedTaggedDoc 80 0)
      #[
        { text := "outer", tags := #[7] },
        { text := "inner", tags := #[7, 8] },
        { text := "tail", tags := #[7] }
      ]

end Tests.Pretty

public def main (args : List String) : IO UInt32 :=
  Tests.Pretty.main args
