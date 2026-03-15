/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
  Tests for the `fragmentize` transformation.
-/
import SubVerso.Highlighting.Highlighted
import VersoSlides.SlideCode

open SubVerso.Highlighting Highlighted
open VersoSlides


def kw (s : String) : Highlighted := .token ⟨.keyword none none none, s⟩
def id' (s : String) : Highlighted := .token ⟨.unknown, s⟩
def u (s : String) : Highlighted := .unparsed s

def dummyGoal (conclusion : String) : Goal Highlighted :=
  { name := none, goalPrefix := "⊢ ", hypotheses := #[], conclusion := .token ⟨.unknown, conclusion⟩ }

def tac (conclusion : String) (s e : Nat) (content : Highlighted) : Highlighted :=
  .tactics #[dummyGoal conclusion] s e content

def errSpan (msg : String) (content : Highlighted) : Highlighted :=
  .span #[(.error, .text msg)] content


instance [BEq ε] [BEq α] : BEq (Except ε α) where
  beq
    | .ok a, .ok b => a == b
    | .error e1, .error e2 => e1 == e2
    | _, _ => false

instance [Repr ε] [Repr α] : Repr (Except ε α) where
  reprPrec
    | .ok a, p => Repr.addAppParen (repr a) p
    | .error e, p => Repr.addAppParen ("error: " ++ repr e) p


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

def test (name : String) (input : Highlighted) (expected : Except String SlideCode) : TestM Unit := do
  let actual := fragmentize input
  let norm := fun | Except.ok sc => Except.ok sc.normalize | Except.error e => Except.error e
  if norm actual == norm expected then
    modify fun s => { s with passed := s.passed + 1 }
  else
    modify fun s => { s with
      failed := s.failed + 1
      errors := s.errors.push s!"FAIL: {name}\n  expected: {repr (norm expected)}\n  actual:   {repr (norm actual)}"
    }

def testOk (name : String) (input : Highlighted) (expected : SlideCode) : TestM Unit :=
  test name input (Except.ok expected)

def testErr (name : String) (input : Highlighted) : TestM Unit := do
  match fragmentize input with
  | Except.error _ => modify fun s => { s with passed := s.passed + 1 }
  | Except.ok actual => modify fun s => { s with
      failed := s.failed + 1
      errors := s.errors.push s!"FAIL: {name}\n  expected: error\n  actual:   {repr actual}"
    }


def main : IO UInt32 := do
  let ((), s) ← tests.run {}
  s.report
where
  tests : TestM Unit := do

    ---- Basic: no magic comments ----
    testOk "no magic comments"
      (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1"])
      (.hl (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1"]))

    ---- Single fragment break ----
    testOk "single fragment break"
      (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1",
              u "\n-- !fragment\n",
              kw "def", u " ", id' "bar", u " := ", id' "2"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1", u "\n"]),
        .fragment ⟨none, none⟩ true
          (.hl (.seq #[kw "def", u " ", id' "bar", u " := ", id' "2"]))
      ])

    ---- Fragment with style ----
    testOk "fragment with style"
      (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1",
              u "\n-- !fragment highlight-current-blue\n",
              kw "def", u " ", id' "bar", u " := ", id' "2"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1", u "\n"]),
        .fragment ⟨some "highlight-current-blue", none⟩ true
          (.hl (.seq #[kw "def", u " ", id' "bar", u " := ", id' "2"]))
      ])

    ---- Fragment with explicit index ----
    testOk "fragment with explicit index"
      (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1",
              u "\n-- !fragment 3\n",
              kw "def", u " ", id' "bar", u " := ", id' "2"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1", u "\n"]),
        .fragment ⟨none, some 3⟩ true
          (.hl (.seq #[kw "def", u " ", id' "bar", u " := ", id' "2"]))
      ])

    ---- Multiple fragment breaks ----
    testOk "multiple fragment breaks"
      (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1",
              u "\n-- !fragment\n",
              kw "def", u " ", id' "bar", u " := ", id' "2",
              u "\n-- !fragment\n",
              kw "def", u " ", id' "baz", u " := ", id' "3"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1", u "\n"]),
        .fragment ⟨none, none⟩ true
          (.hl (.seq #[kw "def", u " ", id' "bar", u " := ", id' "2", u "\n"])),
        .fragment ⟨none, none⟩ true
          (.hl (.seq #[kw "def", u " ", id' "baz", u " := ", id' "3"]))
      ])

    ---- Stacking rule: consecutive breaks nest ----
    testOk "stacking rule"
      (.seq #[u "-- !fragment\n-- !fragment highlight-current-blue\n",
              kw "def", u " ", id' "foo", u " := ", id' "1"])
      (.fragment ⟨none, none⟩ true
        (.fragment ⟨some "highlight-current-blue", none⟩ true
          (.hl (.seq #[kw "def", u " ", id' "foo", u " := ", id' "1"]))))

    ---- Click on tactic (standalone, pre-visible code) ----
    testOk "standalone click on tactic"
      (.seq #[kw "theorem", u " ", id' "foo", u " : ", id' "P", u " := ",
              tac "P" 21 23 (kw "by"),
              u "\n--                 ^ !click\n"])
      (.seq #[
        .hl (.seq #[kw "theorem", u " ", id' "foo", u " : ", id' "P", u " := "]),
        .click
          (.tactics #[dummyGoal "P"] 21 23 (.hl (kw "by")))
          none,
        .hl (u "\n")
      ])

    ---- Click inside fragment ----
    testOk "click inside fragment"
      (.seq #[kw "theorem", u " ", id' "foo", u " : ", id' "P", u " := ",
              tac "P" 21 23 (kw "by"),
              u "\n--                 ^ !click\n-- !fragment\n",
              u "  ", tac "no goals" 26 33 (kw "exact h"),
              u "\n--^ !click\n"])
      (.seq #[
        .hl (.seq #[kw "theorem", u " ", id' "foo", u " : ", id' "P", u " := "]),
        .click (.tactics #[dummyGoal "P"] 21 23 (.hl (kw "by"))) none,
        .hl (u "\n"),
        .fragment ⟨none, none⟩ true
          (.seq #[
            .hl (u "  "),
            .click (.tactics #[dummyGoal "no goals"] 26 33 (.hl (kw "exact h"))) none,
            .hl (u "\n")
          ])
      ])

    ---- Inline fragment ----
    testOk "inline fragment"
      (.seq #[kw "def", u " ", id' "bar", u " (x : String) := ",
              u "/- !fragment -/ ", id' "s!\"{x}{x}\"", u " /- !end fragment -/"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "bar", u " (x : String) := "]),
        .fragment ⟨none, none⟩ false
          (.seq #[.hl (u " "), .hl (id' "s!\"{x}{x}\""), .hl (u " ")])
      ])

    ---- Inline fragment with style ----
    testOk "inline fragment with style"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/- !fragment highlight-current-blue -/ ", id' "1", u " /- !end fragment -/"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := "]),
        .fragment ⟨some "highlight-current-blue", none⟩ false
          (.seq #[.hl (u " "), .hl (id' "1"), .hl (u " ")])
      ])

    ---- Inline fragment with extra whitespace ----
    testOk "inline fragment extra whitespace"
      (.seq #[kw "def", u " ", id' "bar", u " := ",
              u "/-  !fragment  -/ ", id' "x", u " /-  !end fragment  -/"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "bar", u " := "]),
        .fragment ⟨none, none⟩ false
          (.seq #[.hl (u " "), .hl (id' "x"), .hl (u " ")])
      ])

    ---- No space after /- means not a marker (avoids moduledoc conflict) ----
    testOk "no space after /- is not a marker"
      (.seq #[kw "def", u " ", id' "bar", u " := ",
              u "/-!fragment-/ ", id' "x", u " /-!end fragment-/"])
      (.hl (.seq #[kw "def", u " ", id' "bar", u " := ",
              u "/-!fragment-/ ", id' "x", u " /-!end fragment-/"]))

    ---- Fragment inside .tactics node ----
    testOk "fragment inside tactics"
      (.seq #[kw "theorem", u " ", id' "foo", u " : ", id' "P", u " := ",
              tac "P" 21 23
                (.seq #[kw "by", u "\n-- !fragment\n  ", kw "exact h"])])
      (.seq #[
        .hl (.seq #[kw "theorem", u " ", id' "foo", u " : ", id' "P", u " := "]),
        .tactics #[dummyGoal "P"] 21 23
          (.seq #[
            .hl (.seq #[kw "by", u "\n"]),
            .fragment ⟨none, none⟩ true (.hl (.seq #[u "  ", kw "exact h"]))
          ])
      ])

    ---- Diagnostic span passthrough ----
    testOk "diagnostic span passthrough"
      (errSpan "type mismatch" (.seq #[kw "def", u " ", id' "foo", u " := ", id' "true"]))
      (.span #[(.error, .text "type mismatch")]
        (.hl (.seq #[kw "def", u " ", id' "foo", u " := ", id' "true"])))

    ---- Magic comment in .text node ----
    testOk "magic comment in .text node"
      (.seq #[kw "def", .text " ", id' "foo", .text " := ", id' "1",
              .text "\n-- !fragment\n",
              kw "def", .text " ", id' "bar", .text " := ", id' "2"])
      (.seq #[
        .hl (.seq #[kw "def", .text " ", id' "foo", .text " := ", id' "1", .text "\n"]),
        .fragment ⟨none, none⟩ true
          (.hl (.seq #[kw "def", .text " ", id' "bar", .text " := ", id' "2"]))
      ])

    ---- Plain text with newlines but no magic comments ----
    testOk "plain text with newlines"
      (.seq #[kw "def", u " ", id' "foo", u "\n  ", u ":= ", id' "1"])
      (.hl (.seq #[kw "def", u " ", id' "foo", u "\n  ", u ":= ", id' "1"]))

    ---- Error cases ----

    testErr "error: fragment break inside inline fragment"
      (.seq #[u "/- !fragment -/ ", u "-- !fragment\n", id' "foo", u " /- !end fragment -/"])

    testErr "error: end fragment without open"
      (.seq #[kw "def", u " ", id' "foo", u " /- !end fragment -/"])

    testErr "error: unclosed inline fragment"
      (.seq #[kw "def", u " ", id' "foo", u " /- !fragment -/ ", id' "bar"])

    testErr "error: click with no preceding line"
      (.seq #[u "-- ^ !click\n", kw "def", u " ", id' "foo"])

    ---- Click on whitespace inside tactic range ----
    testOk "click on whitespace inside tactic range"
      (.seq #[tac "P" 0 10 (.seq #[kw "by", u "  ", kw "exact h"]),
              u "\n--  ^ !click\n"])
      (.seq #[
        .click (.tactics #[dummyGoal "P"] 0 10 (.hl (.seq #[kw "by", u "  ", kw "exact h"]))) none,
        .hl (u "\n")
      ])

    ---- Click past end of line ----
    testErr "error: click past end of line"
      (.seq #[kw "theorem", u " ", id' "foo", u " : ", id' "P", u " := ",
              tac "P" 21 23 (kw "by"),
              u "\n--                    ^ !click\n"])

    ---- Click on column with no tactic/span/token ----
    testErr "error: click on column with no tactic/span/token"
      (.seq #[kw "def", u " ", id' "foo",
              u "\n--       ^ !click\n"])

    ---- Hide: basic inline hide ----
    testOk "inline hide"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/- !hide -/ ", id' "secret", u " /- !end hide -/",
              id' "1"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := "]),
        .hl (id' "1")
      ])

    ---- Hide: hide removes tokens between markers ----
    testOk "hide removes tokens"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/- !hide -/",
              kw "have", u " ", id' "h", u " := ", id' "sorry", u "\n",
              u "/- !end hide -/",
              id' "h"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := "]),
        .hl (id' "h")
      ])

    ---- Hide: hide with extra whitespace ----
    testOk "hide extra whitespace"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/-  !hide  -/ ", id' "secret", u " /-  !end  hide  -/",
              id' "1"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := "]),
        .hl (id' "1")
      ])

    ---- Hide: hide with no space doesn't match ----
    testOk "hide no space is not a marker"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/-!hide-/ ", id' "x"])
      (.hl (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/-!hide-/ ", id' "x"]))

    ---- Hide errors ----
    testErr "error: end hide without open"
      (.seq #[kw "def", u " ", id' "foo", u " /- !end hide -/"])

    testErr "error: unclosed hide"
      (.seq #[kw "def", u " ", id' "foo", u " /- !hide -/ ", id' "bar"])

    ---- Replace: basic inline replace ----
    testOk "inline replace"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/- !replace ... -/", id' "some_large_term", u " /- !end replace -/"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := ", u "..."]),
      ])

    ---- Replace: replace removes tokens between markers ----
    testOk "replace removes tokens"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/- !replace ... -/",
              kw "have", u " ", id' "h", u " := ", id' "sorry", u "\n",
              u "/- !end replace -/",
              id' "h"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := ", u "..."]),
        .hl (id' "h")
      ])

    ---- Replace: replace with multi-word text ----
    testOk "replace with multi-word text"
      (.seq #[kw "def", u " ", id' "foo", u " := ",
              u "/- !replace <large proof> -/", id' "sorry", u " /- !end replace -/"])
      (.seq #[
        .hl (.seq #[kw "def", u " ", id' "foo", u " := ", u "<large proof>"]),
      ])

    ---- Replace errors ----
    testErr "error: end replace without open"
      (.seq #[kw "def", u " ", id' "foo", u " /- !end replace -/"])

    testErr "error: unclosed replace"
      (.seq #[kw "def", u " ", id' "foo", u " /- !replace ... -/ ", id' "bar"])
