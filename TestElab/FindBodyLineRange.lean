/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

/-
Unit tests for `VersoSlides.findBodyLineRange`. Each test wraps a chunk of fake "module source" in a
single `ModuleItem` (range/kind/defines are irrelevant — the function only reads
`item.code.toString`) and asserts that the returned 1-based source line range matches expectation,
or `none` when the body is too far from anything in the module.
-/
import SubVerso.Module
import SubVerso.Highlighting.Highlighted
import VersoSlides.LibModule

open SubVerso.Module
open SubVerso.Highlighting (Highlighted)
open VersoSlides

/--
Wraps a string as a single `ModuleItem`. The function under test only looks at `item.code.toString`,
so the other fields are placeholders.
-/
private def mkItem (text : String) : ModuleItem :=
  { range := none, kind := `command, defines := #[], code := .text text }

/-- Convenience wrapper that searches `body` against a single-item array built from `modText`. -/
private def find (body modText : String) : Option (Nat × Nat × String) :=
  findBodyLineRange body #[mkItem modText]

private def mod5 : String := "module Foo\n\nimport Bar\n\ndef hello := 42\n"

-- Exact one-line match.
/-- info: some (5, 5, "def hello := 42\n") -/
#guard_msgs in
#eval find "def hello := 42" mod5

-- Exact match at first line.
/-- info: some (1, 1, "module Foo\n") -/
#guard_msgs in
#eval find "module Foo" mod5

-- Exact match in middle.
/-- info: some (3, 3, "import Bar\n") -/
#guard_msgs in
#eval find "import Bar" mod5

-- Multi-line exact match across consecutive non-blank lines (blanks are filtered).
/-- info: some (1, 5, "module Foo\n\nimport Bar\n\ndef hello := 42\n") -/
#guard_msgs in
#eval find "module Foo\nimport Bar\ndef hello := 42" mod5

-- Body has an extra line (`x`) not in the module. Char-level DP absorbs it
-- as a single-char body skip and still finds the right region.
/-- info: some (1, 5, "module Foo\n\nimport Bar\n\ndef hello := 42\n") -/
#guard_msgs in
#eval find "module Foo\nimport Bar\nx\ndef hello := 42" mod5


-- Renamed identifier: char-level edits within a line, well within `body.length / 2`.
/-- info: some (5, 5, "def hello := 42\n") -/
#guard_msgs in
#eval find "def hello := 99" mod5

/-- info: some (5, 5, "def hello := 42\n") -/
#guard_msgs in
#eval find "def yellow := 'x'" mod5

/-- info: some (5, 5, "def hello := 42\n") -/
#guard_msgs in
#eval find "def cea := 'x'" mod5

/-- info: none -/
#guard_msgs in
#eval find "def x := 'x'" mod5

-- Char-level edits across multiple lines, one or two per line.
/-- info: some (1, 5, "module Foo\n\nimport Bar\n\ndef hello := 42\n") -/
#guard_msgs in
#eval find "module Bar\nimport Baz\ndef hello := 42" mod5

-- Body bears no resemblance — distance exceeds cutoff.
/-- info: none -/
#guard_msgs in
#eval find "this body has nothing to do with the module at all" mod5

-- Empty body returns `none`.
/-- info: none -/
#guard_msgs in
#eval find "" mod5

-- Empty module returns `none`.
/-- info: none -/
#guard_msgs in
#eval find "anything" ""

-- Module has two `def` lines; the body matches the second more closely.
/-- info: some (3, 3, "def hello := 42\n") -/
#guard_msgs in
#eval
  find "def hello := 42"
    "def x := 1\ndef hello := 99\ndef hello := 42\n"

-- Module has a noise line between two body matches; line-level DP absorbs it via delete-mod (cost =
-- noise line length). The body needs to be long enough relative to the noise line for the
-- `body.length / 2` cutoff to admit it.
/--
info: some (1, 3, "module Foo with a long-enough body to admit one inserted noise line\nx\nimport Bar")
-/
#guard_msgs in
#eval
  find
    "module Foo with a long-enough body to admit one inserted noise line\nimport Bar"
    "module Foo with a long-enough body to admit one inserted noise line\nx\nimport Bar"

-- Small typo on a keyword (`def` → `deff`).
/-- info: some (5, 5, "def hello := 42\n") -/
#guard_msgs in
#eval find "deff hello := 42" mod5

-- Whitespace-only lines in body are filtered before matching. (Use a tight module so the only
-- sensible alignment is the obvious one — `mod5` has an intermediate `import Bar` line that the DP
-- would otherwise prefer to substitute against, since char-distance is cheaper than the line skip.)
/-- info: some (1, 2, "module Foo\ndef hello := 42\n") -/
#guard_msgs in
#eval find "module Foo\n\n\ndef hello := 42" "module Foo\ndef hello := 42\n"

-- Body longer than the module — body lines that can't be matched force the cutoff to fail, so we
-- report no match instead of a misleading partial.
/-- info: none -/
#guard_msgs in
#eval
  find (.ofList (.replicate 50 'x') ++ "\n" ++
        .ofList (.replicate 50 'y'))
       "short"
