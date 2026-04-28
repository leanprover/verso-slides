/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

import Lean.Elab.Term

import Verso.Code.Highlighted
import Verso.Code.External
import Verso.Doc.Elab
import Verso.Doc.ArgParse
import Verso.Doc.Helpers
import Verso.ExpectString
import Verso.Log
import SubVerso.Highlighting.Code
import SubVerso.Module

import VersoSlides.Basic
import VersoSlides.InlineLean
import VersoSlides.ModuleExample
import VersoSlides.SlideCode
import VersoSlides.SlideCode.Export

open Verso.Doc.Elab
open Verso.ArgParse
open Verso.Log
open Verso.Code.External (withNl)
open Lean
open SubVerso.Highlighting
open SubVerso.Module

namespace VersoSlides

/-- Arguments accepted by `leanLibCode`. -/
structure LibModuleConfig where
  /-- The external library module to pull code from. -/
  «module» : Ident
  /-- Lake package name. Use this to disambiguate when multiple packages contain a module
  with the same name, or when the module is not reachable without a package qualifier. -/
  «package» : Option Ident := none
  /-- A declaration name — extracts the `ModuleItem` whose `defines` contains this name. -/
  decl : Option Ident := none
  /-- 1-based inclusive start line for a line-range extraction. -/
  startLine : Option Nat := none
  /-- 1-based inclusive end line for a line-range extraction. -/
  endLine : Option Nat := none
  /-- Whether to show the interactive info panel below the slide. -/
  panel : Bool := true

section

variable [Monad m] [MonadError m]

instance : FromArgs LibModuleConfig m where
  fromArgs :=
    LibModuleConfig.mk
      <$> .positional `module .ident
      <*> .named `package .ident true
      <*> .named `decl .ident true
      <*> .named `startLine .nat true
      <*> .named `endLine .nat true
      <*> .flag `panel true
end

/-- Cached extracted module JSON, keyed by fully-qualified module name. -/
private structure LoadedLibModule where
  /-- Hash of the JSON file's bytes at load time. -/
  fileHash : UInt64
  items : Array ModuleItem

/--
Environment extension holding parsed external-library modules for the current Lean session. Keyed by
module name; invalidated across sessions when the env resets, and invalidated within a session by a
file-hash check in `loadLibModule`.
-/
private initialize loadedLibModulesExt :
    EnvExtension (Std.HashMap Name LoadedLibModule) ←
  registerEnvExtension (pure {})

/--
Queries Lake for the bytes of the `highlighted` facet for `modName`. Uses `--no-build`: if the facet
hasn't been built, this fails fast instead of silently triggering a full dep build from inside
elaboration.

If `package?` is given, targets the module within that package (`@pkg/+mod:highlighted`); otherwise
queries across the workspace (`+mod:highlighted`).
-/
private def queryFacetBytes (modName : Name) (package? : Option Name) :
    IO (Option ByteArray) := do
  let tgt :=
    match package? with
    | some p => s!"@{p}/+{modName}:highlighted"
    | none => s!"+{modName}:highlighted"
  let out ← IO.Process.output {
    cmd := "lake",
    args := #["query", "--no-build", "--text", tgt]
  }
  if out.exitCode != 0 then return none
  let path := out.stdout.trimAscii.copy
  if path.isEmpty then return none
  some <$> IO.FS.readBinFile (System.FilePath.mk path)

/--
Fallback for modules that aren't Lake modules (prelude, stdlib): invoke `subverso-extract-mod`
directly on a temp-file output. Used only when `queryFacetBytes` fails. The temp file is
auto-deleted by `withTempFile`.

`subverso-extract-mod`'s default source-search path is computed from its own binary location, which
doesn't include the toolchain's `src/lean` directory. We override `LEAN_SRC_PATH` with the toolchain
sysroot (via `Lean.findSysroot`) so prelude and stdlib modules are reachable.
-/
private def fallbackExtractBytes (modName : Name) : IO (Option ByteArray) := do
  let exeOut ← IO.Process.output {
    cmd := "lake",
    args := #["query", "--text", "subverso-extract-mod"]
  }
  if exeOut.exitCode != 0 then return none
  let exePath := exeOut.stdout.trimAscii.copy
  if exePath.isEmpty then return none
  let sysroot ← Lean.findSysroot
  let srcPath : System.SearchPath :=
    [sysroot / "src" / "lean" / "lake", sysroot / "src" / "lean"]
  IO.FS.withTempFile fun _h jsonFile => do
    let runOut ← IO.Process.output {
      cmd := exePath,
      args := #[modName.toString, jsonFile.toString],
      env := #[("LEAN_SRC_PATH", some srcPath.toString)]
    }
    if runOut.exitCode != 0 then return none
    some <$> IO.FS.readBinFile jsonFile

/-- Diagnostic-friendly guidance when neither the facet nor the fallback can find the module. -/
private def noModuleError (modName : Name) (package? : Option Name) : MessageData :=
  let qual :=
    match package? with
    | some p => s!"@{p}/+{modName}:highlighted"
    | none => s!"+{modName}:highlighted"
  let tomlHint :=
    "In lakefile.toml, add the library's highlighted facet to your slides lib's needs:\n\n" ++
    "    [[lean_lib]]\n" ++
    "    name = \"YourSlidesLib\"\n" ++
    s!"    needs = [\"{qual}\"]"
  let leanHint :=
    "In lakefile.lean:\n\n" ++
    "    lean_lib YourSlidesLib where\n" ++
    s!"      needs := #[`{qual}]"
  m!"Couldn't locate highlighted JSON for module `{modName}`.\n\n{tomlHint}\n\n{leanHint}"

/--
Loads the parsed `ModuleItem`s for `modName`, hitting the env-extension cache when possible. If the
cache has a stale entry (file hash changed mid-session), asks the user to restart rather than
silently handing out a mix of old and new data.
-/
private def loadLibModule [Monad m] [MonadEnv m] [MonadError m] [MonadLiftT IO m]
    (modName : Name) (package? : Option Name) (blame : Syntax) : m (Array ModuleItem) := do
  let bytes ←
    match ← (queryFacetBytes modName package? : IO _) with
    | some b => pure b
    | none =>
      match ← (fallbackExtractBytes modName : IO _) with
      | some b => pure b
      | none => throwErrorAt blame (noModuleError modName package?)
  let currentHash := hash bytes
  if let some entry := (loadedLibModulesExt.getState (← getEnv))[modName]? then
    if entry.fileHash == currentHash then
      return entry.items
    else
      throwErrorAt blame
        m!"The highlighted JSON for `{modName}` changed mid-session. Please restart the current file to re-read the library."
  let text := String.fromUTF8! bytes
  let json ← IO.ofExcept (Json.parse text)
  let mod ←
    match Module.fromJson? json with
    | .ok m => pure m
    | .error e => throwErrorAt blame m!"Failed to parse highlighted JSON for `{modName}`: {e}"
  modifyEnv fun env => loadedLibModulesExt.modifyState env fun m =>
    m.insert modName { fileHash := currentHash, items := mod.items }
  return mod.items

private inductive Ctx where
  | tactics (goals : Array (Highlighted.Goal Highlighted)) (s e : Nat)
  | span (info : Array (Highlighted.Span.Kind × Highlighted.MessageContents Highlighted))

/--
Gets the indicated line range, on the assumption that the code in question starts at line `line`.
-/
def getLines (line : Nat) (startLine endLine : Nat) (hl : Highlighted) : Highlighted := Id.run do
  let mut line := line
  let mut ctx : List (Highlighted × Ctx × List Highlighted) := []
  let mut doc : List Highlighted := [hl]
  let mut out : Highlighted := .empty
  repeat
    if line > endLine then break
    match doc with
    | [] =>
      match ctx with
      | [] => break
      | (o', .tactics goals s e, next) :: ctx' =>
        out := o' ++ .tactics goals s e out
        doc := next
        ctx := ctx'
      | (o', .span info, next) :: ctx' =>
        out := o' ++ .span info out
        doc := next
        ctx := ctx'
    | .text s :: next =>
      for l in s.splitInclusive '\n' do
        if line ≥ startLine then out := out ++ .text l.copy
        if l.endsWith '\n' then line := line + 1
        if line > endLine then break
      doc := next
    | .unparsed s :: next =>
      for l in s.splitInclusive '\n' do
        if line ≥ startLine then out := out ++ .unparsed l.copy
        if l.endsWith '\n' then line := line + 1
        if line > endLine then break
      doc := next
    | .seq xs :: next =>
      doc := xs.toList ++ next
    | .token tok :: next =>
      let mut keep := ""
      for l in tok.content.splitInclusive '\n' do
        if line ≥ startLine then keep := keep ++ l.copy
        if l.endsWith '\n' then line := line + 1
        if line > endLine then break
      unless keep.isEmpty do
        out := out ++ .token { tok with content := keep }
      doc := next
    | .tactics goals s e hl :: next =>
      ctx := (out, .tactics goals s e, next) :: ctx
      out := .empty
      doc := [hl]
    | .span info hl :: next =>
      ctx := (out, .span info, next) :: ctx
      out := .empty
      doc := [hl]
    | .point kind info :: next =>
      if line ≥ startLine then
        out := out ++ .point kind info
      doc := next
  return ctx.foldl (init := out) fun
    | o, (o', .tactics goals s e, _) => o' ++ .tactics goals s e o
    | o, (o', .span info, _) => o' ++ .span info o

/--
Extracts the content of a `ModuleItem` clipped to source lines `[sl, el]`,
or `none` if the item lies entirely outside the range. Items entirely inside
the range pass through without traversal; only items straddling a boundary
are walked.
-/
private def sliceItem (sl el : Nat) (item : ModuleItem) : Option Highlighted := do
  let (s, e) ← item.range
  if e.line < sl ∨ s.line > el then none
  else if sl ≤ s.line ∧ e.line ≤ el then some item.code
  else
    -- Straddles a boundary. The item's `code` begins with whitespace from
    -- the gap before `s.line`, so trim leading blanks before slicing so the
    -- line counter starts at `s.line` of the first real character.
    some (getLines s.line sl el (dropBlanks item.code))

/--
Searches the source of `items` for the closest substring to `body`, anchored at line boundaries.
Returns the matched source line range and the matched text, or `none` when no candidate is close
enough — concretely, when the Levenshtein distance exceeds
`max(body.length, matchedText.length) / 2`. An exact match returns its location with distance 0.

The returned text contains complete source lines, snapped at both ends and suitable for use directly
as the body of a quickfix replacement.
-/
def findBodyLineRange (body : String) (items : Array ModuleItem) :
    Option (Nat × Nat × String) := Id.run do
  if body.isEmpty then return none
  let modText : String := items.foldl (init := "") fun s i => s ++ i.code.toString
  if modText.isEmpty then return none
  let fm := FileMap.ofString modText
  let bArr := body.toList.toArray
  let bLen := bArr.size
  let infty : Nat := body.length + modText.length + 1
  let mut prev : Vector (Nat × String.Pos.Raw) (bLen + 1) := .ofFn fun j => (j.val, 0)
  let mut curr : Vector (Nat × String.Pos.Raw) (bLen + 1) := .replicate _ (0, 0)
  let mut bestDist : Nat := infty
  let mut bestStart : String.Pos.Raw := 0
  let mut bestEnd : String.Pos.Raw := 0
  -- Initial `prev[0] = (0, 0)` covers the line-1 free start at byte 0.
  -- Within the loop, we set `curr[0] = (0, nextPos)` only when `m == '\n'`, so
  -- `DP[i+1][0]` (which has notional `start = i+1 = nextPos`) is only available
  -- as a free-start cell when `nextPos` is a line boundary.
  let mut iPos : String.Pos.Raw := 0
  while h : !iPos.atEnd modText do
    let m := iPos.get' modText (by grind)
    let nextPos := iPos.next' modText (by grind)
    if m == '\n' then
      curr := curr.set 0 (0, nextPos)
    else
      curr := curr.set 0 (infty, 0)
    for h : j in 0...bLen do
      let b := bArr[j]
      let cost := if m == b then 0 else 1
      let (dSub, sSub) := prev[j]
      let (dDel, sDel) := prev[j + 1]
      let (dIns, sIns) := curr[j]
      let sub := (dSub + cost, sSub)
      let del := (dDel + 1, sDel)
      let ins := (dIns + 1, sIns)
      let pick :=
        if sub.1 ≤ del.1 ∧ sub.1 ≤ ins.1 then sub
        else if del.1 ≤ ins.1 then del else ins
      curr := curr.set (j + 1) pick
    let (d, s) := curr[bLen]
    if d < bestDist then
      bestDist := d
      bestStart := s
      bestEnd := nextPos
    let tmp := prev
    prev := curr
    curr := tmp
    iPos := nextPos
  -- Cutoff scales with the larger of body and candidate length so that noise-line
  -- insertions in the library (which inflate candidate length) don't exclude an
  -- otherwise-good match. Lengths are in bytes; close enough to chars for ASCII.
  let candidateLen := bestEnd.byteIdx - bestStart.byteIdx
  let cutoff := max body.length candidateLen / 2
  if bestDist > cutoff then return none
  let endLast := bestEnd.prev modText
  let startLine := (fm.toPosition bestStart).line
  let endLine := (fm.toPosition endLast).line
  let found :=
    modText.splitInclusive '\n' |>.drop (startLine - 1) |>.take (endLine - startLine + 1)
      |>.joinString
  return some (startLine, endLine, found)

/--
Picks the highlighted code to include based on the user's config (decl, line range, or all). For
line ranges, slices each overlapping item to the requested lines via `sliceItem`.
-/
private def selectCode (items : Array ModuleItem) (cfg : LibModuleConfig)
    : Except String Highlighted := do
  match cfg.decl, cfg.startLine, cfg.endLine with
  | some _, some _, _ | some _, _, some _ =>
    throw "Cannot combine `decl` with `startLine`/`endLine`."
  | none, some _, none | none, none, some _ =>
    throw "Both `startLine` and `endLine` must be provided together."
  | some declName, none, none =>
    match items.find? (·.defines.contains declName.getId) with
    | some item => return item.code
    | none =>
      let input := declName.getId.toString
      let candidates := items.flatMap (·.defines) |>.map toString
      let threshold (name : String) : Nat :=
        if input.length < 5 then 1
        else if input.length < 10 then 2
        else max 3 (max input.length name.length / 5)
      let scored := candidates.filterMap fun c =>
        Lean.EditDistance.levenshtein c input (threshold c) |>.map (c, ·)
      let sorted := scored.qsort fun x y =>
        x.2 < y.2 || (x.2 == y.2 && x.1 < y.1)
      let suggestions := sorted.take 10 |>.map (·.1)
      if suggestions.isEmpty then
        throw s!"No declaration named `{input}` in module."
      else
        throw s!"No declaration named `{input}` in module. \
                Did you mean: {suggestions.toList}?"
  | none, some sl, some el =>
    if sl > el then throw s!"startLine ({sl}) is greater than endLine ({el})."
    let combined := items.filterMap (sliceItem sl el)
      |>.foldl (init := Highlighted.empty) (· ++ ·)
    if combined.isEmpty then
      let total := items.filterMap (·.range.map (·.2.line)) |>.foldl max 0
      throw s!"No items in module overlap lines {sl}..{el} (module has {total} lines)."
    return combined
  | none, none, none =>
    return items.foldl (init := Highlighted.empty) fun acc item => acc ++ item.code

/--
Builds a quickfix replacement string for the code block at `stx`. Returns the entire
code block as a single string, with leading whitespace from the opening line preserved as
indentation on every line of the new body.

If `newArgs?` is `some args`, the directive's arguments are replaced with `args` (the directive
name is kept); if `none`, the original argument list is left intact and only the body is rewritten
to `newContents`.

The opening and closing delimiters are sized to be longer than any run of backticks in
`newContents`, so a body containing nested code blocks still produces a valid block.

Returns `none` when the syntax has no source range, or when the opening line at that range does
not start with a backtick.
-/
private meta def editCodeBlock [Monad m] [MonadFileMap m] (stx : Syntax) (newArgs? : Option String) (newContents : String) : m (Option String) := do
  let txt ← getFileMap
  let some rng := stx.getRange?
    | pure none
  let { start := {line := l1, ..}, .. } := txt.utf8RangeToLspRange rng
  let line1 := (txt.lineStart (l1 + 1)).extract txt.source (txt.lineStart (l1 + 2))
  let line1ws := line1.takeWhile (· == ' ') |>.copy
  let line1rest := line1.drop line1ws.length
  let newContents := line1ws ++ (withNl newContents).replace "\n" ("\n" ++ line1ws)
  if line1rest.startsWith "```" then
    match newArgs? with
    | none =>
      return some s!"{delims}{line1rest.dropWhile (· == '`') |>.trimAscii}\n{withNl newContents}{delims}"
    | some newArgs =>
      let name := line1rest.dropWhile (· == '`') |>.trimAscii |>.takeWhile (!·.isWhitespace) |>.copy
      let newArgs := newArgs.trimAscii
      let newArgs := if newArgs.isEmpty then "" else " " ++ newArgs.copy
      return some s!"{delims}{name}{newArgs}\n{withNl newContents}{delims}"
  else
    return none
where
  delims : String := Id.run do
    let mut n := 3
    let mut run := none
    let mut iter := newContents.startPos
    while h : iter ≠ newContents.endPos do
      let c := iter.get h
      iter := iter.next h
      if c == '`' then
        run := some (run.getD 0 + 1)
      else if let some k := run then
        if k ≥ n then n := k + 1
        run := none
    if let some k := run then
      if k ≥ n then n := k + 1
    n.fold (fun _ _ s => s.push '`') ""

/--
A code block that shows syntax-highlighted source from an external library module.

Requires a Lake `needs` entry so the library's `highlighted` facet is built before the
slides library. The block body is the expected text of the extracted code — if it drifts
from the library, a quickfix suggestion offers the current source.

Examples:

```
```leanLibCode MyLib.Foo (decl := MyLib.Foo.bar)
def bar : Nat := 42
```
```

```
```leanLibCode MyLib.Foo (startLine := 10) (endLine := 30)
-- lines 10..30 verbatim
```
```
-/
@[code_block]
def leanLibCode : CodeBlockExpanderOf LibModuleConfig
  | cfg, str => do
    let modName := cfg.«module».getId
    let pkgName? := cfg.«package».map (·.getId)
    let items ← loadLibModule modName pkgName? cfg.«module».raw
    let hl ←
      match selectCode items cfg with
      | .ok v => pure v
      | .error msg => throwErrorAt str.raw msg
    let hl := dropBlanks hl
    let hlString := hl.toString
    let replacement := withNl hlString
    let useLine (l : String) : Bool := !l.trimAscii.isEmpty
    if let some diff ← Verso.ExpectString.expectStringOrDiff str replacement (useLine := useLine) then
      let ref ← getRef
      let lineHint? : Option String ←
        match cfg.startLine, cfg.endLine with
        | some sl, some el =>
          match findBodyLineRange str.getString items with
          | some (newSl, newEl, newContents) =>
            if newSl != sl || newEl != el then
              let newArgs := [
                some s!"{cfg.module.getId}",
                cfg.package.map (s!"(package := {·.getId})"),
                some s!"(startLine := {newSl})",
                some s!"(endLine := {newEl})",
                if !cfg.panel then some "-panel" else none
              ]
              editCodeBlock ref (some (" ".intercalate (newArgs.filterMap id))) newContents
            else pure none
          | none => pure none
        | _, _ => pure none
      if let some edit ← editCodeBlock ref none replacement then
        let h ←
          if let some lineHint := lineHint? then
            m!"Update the line range or replace with the current library code".hint (ref? := some ref) #[
              { suggestion := lineHint, preInfo? := some "Update line numbers:" },
              { suggestion := edit, preInfo? := some "Update expected code:" }
            ]
          else
            m!"Replace with the current library code".hint (ref? := some ref) #[edit]
        logError m!"Code block does not match the current library code:\n{diff}{h}"
      else
        logError m!"Code block does not match the current library code:\n{diff}"
    match fragmentize hl.trim with
    | .ok sc =>
      let exported := scToExport sc
      ``(Verso.Doc.Block.other
           (VersoSlides.BlockExt.slideCode $(quote exported) $(quote cfg.panel))
           #[Verso.Doc.Block.code $(quote str.getString)])
    | .error msg =>
      throwErrorAt str.raw msg
