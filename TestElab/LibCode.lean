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

-- When the body doesn't match the library code, the block emits a diff and a clickable quickfix
-- that replaces the entire `leanLibCode` block (directive line + body) with the current library
-- code. With line range `77..77` the slicer extracts only the def line, so the body diff is clean.
/--
error: Code block does not match the current library code:
- public meta def withNl (s : String) : String := if s.endsWith "wrong" then s else s ++ "wrong"
+ public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"


Hint: Replace with the current library code
  ```leanLibCode Verso.Code.External (package := verso) (startLine := 77) (endLine := 77)
  public meta def withNl (s : String) : String := if s.endsWith "w̵r̵o̵\̲ng̵" then s else s ++ "w̵r̵o̵\̲ng̵"
  ```
-/
#guard_msgs in
#docs (Slides) libDrift "Lib Drift" :=
:::::::

# Lib Drift

```leanLibCode Verso.Code.External (package := verso) (startLine := 77) (endLine := 77)
public meta def withNl (s : String) : String := if s.endsWith "wrong" then s else s ++ "wrong"
```
:::::::

-- Stale line numbers: body matches the library, but at a different line range
-- than the user wrote. Drift fires, and the hint offers TWO clickable fixes:
-- update the line range to where the body actually appears (51 → 77), or
-- replace the body with whatever line 51 currently contains.
/--
error: Code block does not match the current library code:
- public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
+ public class ExternalCode (genre : Genre) where


Hint: Update the line range or replace with the current library code
  • ```leanLibCode Verso.Code.External (package := verso) (startLine := 5̵1̵7̲7̲) (endLine := 5̵1̵7̲7̲)
    public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
    ```
  • ```leanLibCode Verso.Code.External (package := verso) (startLine := 51) (endLine := 51)
    public m̵e̵t̵a̵ ̵d̵e̵f̵ ̵w̵i̵t̵h̵N̵l̵ ̵(̵s̵c̲l̲a̲s̲s̲ ̲E̲x̲t̲e̲r̲n̲a̲l̲C̲o̲d̲e̲ ̲(̲g̲e̲n̲r̲e̲ : S̵t̵r̵i̵n̵g̵)̵ ̵:̵ ̵S̵t̵r̵i̵n̵g̵ ̵:̵=̵ ̵i̵f̵ ̵s̵.̵e̵n̵d̵s̵W̵i̵t̵h̵ ̵"̵\̵n̵"̵ ̵t̵h̵e̵n̵ ̵s̵ ̵e̵l̵s̵e̵ ̵s̵ ̵+̵+̵ ̵"̵\̵n̵"̵G̲e̲n̲r̲e̲)̲ ̲w̲h̲e̲r̲e̲
    ```
-/
#guard_msgs in
#docs (Slides) libStaleLines "Lib Stale Lines" :=
:::::::

# Lib Stale Lines

```leanLibCode Verso.Code.External (package := verso) (startLine := 51) (endLine := 51)
public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
```
:::::::

-- Renamed variable: body differs from the library by character-level edits
-- (here `s` → `t` throughout) AND the user wrote stale line numbers. The
-- fuzzy fallback in `findBodyLineRange` still finds the right line via
-- Levenshtein-bounded approximate substring match. The hint offers a
-- clickable line-range fix and a body replace.
/--
error: Code block does not match the current library code:
- public meta def withNl (t : String) : String := if t.endsWith "\n" then t else t ++ "\n"
+ -- TODO test thresholds/sorting


Hint: Update the line range or replace with the current library code
  • ```leanLibCode Verso.Code.External (package := verso) (startLine := 9̵9̵7̲7̲) (endLine := 9̵9̵7̲7̲)
    public meta def withNl (t̵s̲ : String) : String := if t̵s̲.endsWith "\n" then t̵s̲ e̵l̵e̲l̲se̵e̲ t̵ ̵s̲ ̲++ "\n"
    ```
  • ```leanLibCode Verso.Code.External (package := verso) (startLine := 99) (endLine := 99)
    p̵u̵b̵l̵i̵c̵ ̵m̵e̵t̵a̵ ̵d̵e̵f̵ ̵w̵i̵t̵h̵N̵l̵ ̵(̵t̵ ̵:̵ ̵S̵t̵r̵i̵n̵g̵)̵ ̵:̵ ̵S̵t̵r̵i̵n̵g̵ ̵:̵=̵ ̵i̵f̵ ̵t̵.̵e̵n̵d̵s̵W̵i̵t̵h̵ ̵"̵\̵n̵"̵ ̵t̵h̵e̵n̵ ̵t̵ ̵e̵l̵s̵e̵ ̵t̵ ̵+̵+̵ ̵"̵\̵n̵"̵-̲-̲ ̲T̲O̲D̲O̲ ̲t̲e̲s̲t̲ ̲t̲h̲r̲e̲s̲h̲o̲l̲d̲s̲/̲s̲o̲r̲t̲i̲n̲g̲
    ```
-/
#guard_msgs in
#docs (Slides) libRename "Lib Rename" :=
:::::::

# Lib Rename

```leanLibCode Verso.Code.External (package := verso) (startLine := 99) (endLine := 99)
public meta def withNl (t : String) : String := if t.endsWith "\n" then t else t ++ "\n"
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
