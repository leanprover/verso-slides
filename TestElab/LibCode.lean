/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
Tests for `leanLibCode`: the code block that shows source from an external
library module via the `highlighted` Lake facet.
-/
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

-- Decl mode: the happy path, extracting a declaration by name.
#guard_msgs in
#docs (Slides) libDecl "Lib Decl" :=
:::::::

# Lib Decl

```leanLibCode Verso.Code.External (package := verso) (decl := Verso.Code.External.withNl)
/--
Adds a newline to a string if it doesn't already end with one.
-/
public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
```
:::::::

-- Line range mode: same declaration extracted by line numbers.
#guard_msgs in
#docs (Slides) libLines "Lib Lines" :=
:::::::

# Lib Lines

```leanLibCode Verso.Code.External (package := verso) (startLine := 74) (endLine := 77)
/--
Adds a newline to a string if it doesn't already end with one.
-/
public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
```
:::::::

-- Panel toggle: `(panel := false)` suppresses the interactive info panel.
-- This pins the only public-facing knob with no other coverage.
#guard_msgs in
#docs (Slides) libNoPanel "Lib No Panel" :=
:::::::

# Lib No Panel

```leanLibCode Verso.Code.External (package := verso) (decl := Verso.Code.External.withNl) -panel
/--
Adds a newline to a string if it doesn't already end with one.
-/
public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
```
:::::::

-- Drift detection: when the body doesn't match the library source, the block
-- emits a diff and a quickfix suggestion with the current source. The
-- expected docstring below contains `/--` and `-/` from the diff; Lean's
-- lexer balances them as nested block comments inside the outer docstring.
/--
error: Code block does not match the current library source:
- public meta def withNl (s : String) : String := if s.endsWith "wrong" then s else s ++ "wrong"
+ /--
+ Adds a newline to a string if it doesn't already end with one.
+ -/
+ public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"


Hint: Replace with the current library source
  /̲-̲-̲
  ̲A̲d̲d̲s̲ ̲a̲ ̲n̲e̲w̲l̲i̲n̲e̲ ̲t̲o̲ ̲a̲ ̲s̲t̲r̲i̲n̲g̲ ̲i̲f̲ ̲i̲t̲ ̲d̲o̲e̲s̲n̲'̲t̲ ̲a̲l̲r̲e̲a̲d̲y̲ ̲e̲n̲d̲ ̲w̲i̲t̲h̲ ̲o̲n̲e̲.̲
  ̲-̲/̲
  ̲public meta def withNl (s : String) : String := if s.endsWith "̵w̵r̵o̵n̵g̵"̵"̲\̲n̲"̲ then s else s ++ "̵w̵r̵o̵n̵g̵"̵"̲\̲n̲"̲
-/
#guard_msgs in
#docs (Slides) libDrift "Lib Drift" :=
:::::::

# Lib Drift

```leanLibCode Verso.Code.External (package := verso) (startLine := 77) (endLine := 77)
public meta def withNl (s : String) : String := if s.endsWith "wrong" then s else s ++ "wrong"
```
:::::::

-- Decl name not found: a near-miss typo gets Levenshtein-bounded suggestions
-- ranked by edit distance, top 10. Snapshot is sensitive to nearby names in
-- `Verso.Code.External`; update if upstream Verso renames or adds adjacent
-- declarations.
/--
error: No declaration named `Verso.Code.External.withN` in module. Did you mean: [Verso.Code.External.withNl, Verso.Code.External.lit, Verso.Code.External.anchor]?
-/
#guard_msgs in
#docs (Slides) libNoDeclTypo "Lib No Decl Typo" :=
:::::::

# Lib No Decl Typo

```leanLibCode Verso.Code.External (package := verso) (decl := Verso.Code.External.withN)
-- typo for `withNl`
```
:::::::

-- Decl name with no near matches: error reports no suggestions.
/--
error: No declaration named `Verso.Code.External.totallyUnrelatedNameXYZ` in module.
-/
#guard_msgs in
#docs (Slides) libNoDeclFar "Lib No Decl Far" :=
:::::::

# Lib No Decl Far

```leanLibCode Verso.Code.External (package := verso) (decl := Verso.Code.External.totallyUnrelatedNameXYZ)
-- nothing close
```
:::::::

-- `decl` and `startLine`/`endLine` are mutually exclusive.
/--
error: Cannot combine `decl` with `startLine`/`endLine`.
-/
#guard_msgs in
#docs (Slides) libConflict "Lib Conflict" :=
:::::::

# Lib Conflict

```leanLibCode Verso.Code.External (package := verso) (decl := Verso.Code.External.withNl) (startLine := 74) (endLine := 77)
-- ignored
```
:::::::

-- Fallback path: `Init.Util` isn't a Lake module, so `leanLibCode` falls back
-- to invoking `subverso-extract-mod` directly. This exercises the fallback
-- branch, which sets `LEAN_SRC_PATH` to the toolchain's `src/lean`. Targets a
-- small stable declaration (`dbgTraceVal`); the body is captured from the live
-- source, so if Lean rewrites it, update the snapshot.
#guard_msgs in
#docs (Slides) libFallback "Lib Fallback" :=
:::::::

# Lib Fallback

```leanLibCode Init.Util (decl := dbgTraceVal)
def dbgTraceVal {α : Type u} [ToString α] (a : α) : α :=
  dbgTrace (toString a) (fun _ => a)
```
:::::::

-- Line range with no overlapping items: error mentions the module's line count.
/--
error: No items in module overlap lines 99000..99100 (module has 854 lines).
-/
#guard_msgs in
#docs (Slides) libNoOverlap "Lib No Overlap" :=
:::::::

# Lib No Overlap

```leanLibCode Verso.Code.External (package := verso) (startLine := 99000) (endLine := 99100)
-- out of range
```
:::::::


