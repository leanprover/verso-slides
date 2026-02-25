/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
  Tests for the `SlideCode.toHtml` rendering.
-/
import SubVerso.Highlighting.Highlighted
import VersoSlides.SlideCode
import VersoSlides.SlideCode.Render
import VersoSlides.Basic
import Verso.Code.Highlighted
import Verso.Output.Html

open SubVerso.Highlighting Highlighted
open Verso.Code (HighlightHtmlM)
open Verso.Code.Hover (State)
open Verso Output Html
open VersoSlides


def kw (s : String) : Highlighted := .token ⟨.keyword none none none, s⟩
def id' (s : String) : Highlighted := .token ⟨.unknown, s⟩
def u (s : String) : Highlighted := .unparsed s

def dummyGoal (conclusion : String) : Goal Highlighted :=
  { name := none, goalPrefix := "⊢ ", hypotheses := #[], conclusion := .token ⟨.unknown, conclusion⟩ }


/-- Checks if `needle` is a substring of `haystack`. -/
def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

/-- Runs `HighlightHtmlM Slides` with minimal context suitable for testing. -/
def runHighlightHtml (act : HighlightHtmlM Slides Html) : Html :=
  let ctx : HighlightHtmlM.Context Slides := {
    linkTargets := {}
    traverseContext := (show Slides.TraverseContext from ())
    definitionIds := {}
    options := {}
  }
  let (result, _state) := act ctx ({} : State Html)
  result

/-- Renders a `SlideCode` to an HTML string. -/
def renderStr (sc : SlideCode) : String :=
  (runHighlightHtml (sc.toHtml (g := Slides))).asString


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

/-- Asserts that the rendered HTML contains the given substring. -/
def testHas (name : String) (sc : SlideCode) (needle : String) : TestM Unit := do
  let html := renderStr sc
  if hasSubstr html needle then
    modify fun s => { s with passed := s.passed + 1 }
  else
    modify fun s => { s with
      failed := s.failed + 1
      errors := s.errors.push s!"FAIL (has): {name}\n  expected to contain: {repr needle}\n  actual: {repr html}"
    }

/-- Asserts that the rendered HTML does NOT contain the given substring. -/
def testLacks (name : String) (sc : SlideCode) (needle : String) : TestM Unit := do
  let html := renderStr sc
  if hasSubstr html needle then
    modify fun s => { s with
      failed := s.failed + 1
      errors := s.errors.push s!"FAIL (lacks): {name}\n  expected NOT to contain: {repr needle}\n  actual: {repr html}"
    }
  else
    modify fun s => { s with passed := s.passed + 1 }


def main : IO UInt32 := do
  let ((), s) ← tests.run {}
  s.report
where
  tests : TestM Unit := do

    -- ---- Fragment: line-level produces <div> ----
    testHas "fragment line-level produces div"
      (.fragment ⟨none, none⟩ true (.hl (u "hello")))
      "<div class=\"fragment\">"

    -- ---- Fragment: inline produces <span> ----
    testHas "fragment inline produces span"
      (.fragment ⟨none, none⟩ false (.hl (u "hello")))
      "<span class=\"fragment\">"

    -- ---- Fragment: style becomes CSS class ----
    testHas "fragment style becomes CSS class"
      (.fragment ⟨some "highlight-current-blue", none⟩ true (.hl (u "hello")))
      "class=\"fragment highlight-current-blue\""

    -- ---- Fragment: explicit index becomes data-fragment-index ----
    testHas "fragment explicit index"
      (.fragment ⟨none, some 3⟩ true (.hl (u "hello")))
      "data-fragment-index=\"3\""

    -- ---- Fragment: no index means no data-fragment-index ----
    testLacks "fragment no index"
      (.fragment ⟨none, none⟩ true (.hl (u "hello")))
      "data-fragment-index"

    -- ---- Click: produces slide-click-only ----
    testHas "click produces slide-click-only"
      (.click (.hl (kw "by")) none)
      "slide-click-only"

    -- ---- Click: with index ----
    testHas "click with index"
      (.click (.hl (kw "by")) (some 2))
      "data-fragment-index=\"2\""

    -- ---- Nested fragments produce nested wrappers ----
    testHas "nested fragments outer"
      (.fragment ⟨none, none⟩ true
        (.fragment ⟨some "highlight-current-blue", none⟩ true
          (.hl (u "hello"))))
      "<div class=\"fragment\">"

    testHas "nested fragments inner"
      (.fragment ⟨none, none⟩ true
        (.fragment ⟨some "highlight-current-blue", none⟩ true
          (.hl (u "hello"))))
      "<div class=\"fragment highlight-current-blue\">"

    -- ---- Tactics: produces hidden .tactic-state ----
    testHas "tactics produces tactic-state"
      (.tactics #[dummyGoal "P"] 0 5 (.hl (kw "by")))
      "tactic-state"

    testHas "tactics tactic-state is hidden"
      (.tactics #[dummyGoal "P"] 0 5 (.hl (kw "by")))
      "display:none"

    -- ---- Tactics: has data-tactic-range ----
    testHas "tactics has data-tactic-range"
      (.tactics #[dummyGoal "P"] 10 20 (.hl (kw "by")))
      "data-tactic-range=\"10-20\""

    -- ---- Tactics: no tactic-toggle checkbox (no <input> or <label>) ----
    testLacks "tactics no tactic-toggle"
      (.tactics #[dummyGoal "P"] 0 5 (.hl (kw "by")))
      "tactic-toggle"

    testLacks "tactics no input"
      (.tactics #[dummyGoal "P"] 0 5 (.hl (kw "by")))
      "<input"

    testLacks "tactics no label"
      (.tactics #[dummyGoal "P"] 0 5 (.hl (kw "by")))
      "<label"

    -- ---- Span: produces has-info error class ----
    testHas "span produces has-info error"
      (.span #[(.error, .text "type mismatch")] (.hl (u "bad")))
      "has-info error"

    -- ---- Span: contains hidden hover-info ----
    testHas "span contains hover-info"
      (.span #[(.error, .text "type mismatch")] (.hl (u "bad")))
      "hover-info"

    testHas "span hover-info is hidden"
      (.span #[(.error, .text "type mismatch")] (.hl (u "bad")))
      "display:none"

    -- ---- .hl passthrough: delegates to Highlighted.toHtml ----
    testHas "hl passthrough produces token class"
      (.hl (kw "def"))
      "token"

    -- ---- commandOutput: produces command-output div ----
    testHas "commandOutput produces div"
      (.commandOutput #[(.info, .text "Nat")])
      "command-output"

    -- ---- Fragment with style and index ----
    testHas "fragment style and index class"
      (.fragment ⟨some "fade-in", some 5⟩ false (.hl (u "hello")))
      "class=\"fragment fade-in\""

    testHas "fragment style and index attr"
      (.fragment ⟨some "fade-in", some 5⟩ false (.hl (u "hello")))
      "data-fragment-index=\"5\""

    -- ---- Seq: renders all children ----
    testHas "seq renders children"
      (.seq #[.hl (kw "def"), .hl (u " "), .hl (id' "foo")])
      "foo"
