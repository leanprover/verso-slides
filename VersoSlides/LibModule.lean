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

/-- Environment extension holding parsed external-library modules for the current Lean session.
Keyed by module name; invalidated across sessions when the env resets, and
invalidated within a session by a file-hash check in `loadLibModule`. -/
private initialize loadedLibModulesExt :
    EnvExtension (Std.HashMap Name LoadedLibModule) ←
  registerEnvExtension (pure {})

/-- Query Lake for the bytes of the `highlighted` facet for `modName`.
Uses `--no-build`: if the facet hasn't been built, this fails fast instead of
silently triggering a full dep build from inside elaboration.

If `package?` is given, targets the module within that package (`@pkg/+mod:highlighted`);
otherwise queries across the workspace (`+mod:highlighted`). -/
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

/-- Fallback for modules that aren't Lake modules (prelude, stdlib): invoke
`subverso-extract-mod` directly on a temp-file output. Used only when
`queryFacetBytes` fails. The temp file is auto-deleted by `withTempFile`.

`subverso-extract-mod`'s default source-search path is computed from its own
binary location, which doesn't include the toolchain's `src/lean` directory.
We override `LEAN_SRC_PATH` with the toolchain sysroot (via `Lean.findSysroot`)
so prelude and stdlib modules are reachable. -/
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

/-- Load the parsed `ModuleItem`s for `modName`, hitting the env-extension cache when possible.
If the cache has a stale entry (file hash changed mid-session), asks the user to restart
rather than silently handing out a mix of old and new data. -/
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

/-- Pick the `ModuleItem`s to include based on the user's config (decl, line range, or all). -/
private def selectItems (items : Array ModuleItem) (cfg : LibModuleConfig)
    : Except String (Array ModuleItem) := do
  match cfg.decl, cfg.startLine, cfg.endLine with
  | some _, some _, _ | some _, _, some _ =>
    throw "Cannot combine `decl` with `startLine`/`endLine`."
  | none, some _, none | none, none, some _ =>
    throw "Both `startLine` and `endLine` must be provided together."
  | some declName, none, none =>
    match items.find? (·.defines.contains declName.getId) with
    | some item => return #[item]
    | none =>
      let input := declName.getId.toString
      let candidates := items.flatMap (·.defines) |>.map toString
      let threshold (name : String) : Nat :=
        if input.length < 5 then 1
        else if input.length < 10 then 2
        else 3 |>.max (max input.length name.length / 5)
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
    let overlapping := items.filter fun item =>
      match item.range with
      | some (s, e) => s.line ≤ el && sl ≤ e.line
      | none => false
    if overlapping.isEmpty then
      let total := items.filterMap (·.range.map (·.2.line)) |>.foldl max 0
      throw s!"No items in module overlap lines {sl}..{el} (module has {total} lines)."
    return overlapping
  | none, none, none =>
    return items

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
    let selected ←
      match selectItems items cfg with
      | .ok v => pure v
      | .error msg => throwErrorAt str.raw msg
    let hl := selected.foldl (init := Highlighted.empty) fun acc item => acc ++ item.code
    let hl := dropBlanks hl
    let hlString := hl.toString
    let replacement := withNl hlString
    let useLine (l : String) : Bool := !l.trimAscii.isEmpty
    if let some diff ← Verso.ExpectString.expectStringOrDiff str replacement (useLine := useLine) then
      let h : MessageData ←
        MessageData.hint "Replace with the current library source"
          #[{ suggestion := .string replacement }] (ref? := some str)
      logErrorAt str m!"Code block does not match the current library source:\n{diff}{h}"
    match fragmentize hl.trim with
    | .ok sc =>
      let exported := scToExport sc
      ``(Verso.Doc.Block.other
           (VersoSlides.BlockExt.slideCode $(quote exported) $(quote cfg.panel))
           #[Verso.Doc.Block.code $(quote str.getString)])
    | .error msg =>
      throwErrorAt str.raw msg

end VersoSlides
