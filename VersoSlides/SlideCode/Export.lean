/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import SubVerso.Highlighting.Export
public import VersoSlides.SlideCode

open Lean

/-!
De-duplicating serialization for {name}`SlideCode`, following the pattern of SubVerso's
{name}`ExportCode` for {name}`Highlighted`.
-/

open SubVerso Highlighting
open Lean

namespace VersoSlides.Export

/--
Parallel {name}`VersoSlides.SlideCode` with {name}`SubVerso.Highlighting.Export.Key` references for
{name}`Highlighted`, {name}`Highlighted.Goal`, and {name}`Highlighted.MessageContents` subtrees.
-/
public inductive SlideCode where
  | hl (content : SubVerso.Highlighting.Export.Key)
  | seq (parts : Array SlideCode)
  | tactics (info : Array SubVerso.Highlighting.Export.Key) (startPos endPos : Nat) (content : SlideCode)
  | span (info : Array (Highlighted.Span.Kind × SubVerso.Highlighting.Export.Key)) (content : SlideCode)
  | fragment (wrapper : FragmentData) (isBlock : Bool) (content : SlideCode)
  | click (target : SlideCode) (index : Option Nat)
  | commandOutput (info : Array (Highlighted.Span.Kind × SubVerso.Highlighting.Export.Key))
deriving Repr, Inhabited, BEq, ToJson, FromJson

end VersoSlides.Export

namespace VersoSlides

/-- Serialized {name}`SlideCode` with de-duplicated SubVerso data tables. -/
public structure ExportSlideCode extends Highlighting.Export where
  top : Export.SlideCode

public def ExportSlideCode.toJson (data : ExportSlideCode) : Json :=
  data.toExport.toJson |>.setObjVal! "top" (Lean.toJson data.top)

instance : ToJson ExportSlideCode := ⟨ExportSlideCode.toJson⟩

public def ExportSlideCode.fromJson? (json : Json) : Except String ExportSlideCode := do
  let e ← Highlighting.Export.fromJson? json
  let top ← json.getObjValAs? Export.SlideCode "top"
  return {e with top}

instance : FromJson ExportSlideCode := ⟨ExportSlideCode.fromJson?⟩

/--
Exports a {name}`SlideCode` into a de-duplicated {name}`Export.SlideCode`, reusing SubVerso's export
monad for {name}`Highlighted`, {name}`Highlighted.Goal`, and {name}`Highlighted.MessageContents`
subtrees.
-/
public partial def SlideCode.export (sc : SlideCode) : Highlighting.ExportM Export.SlideCode :=
  match sc with
  | .hl content => Export.SlideCode.hl <$> content.export
  | .seq parts => Export.SlideCode.seq <$> parts.mapM SlideCode.export
  | .tactics info s e content => do
    let info ← info.mapM (·.export)
    let content ← content.export
    return Export.SlideCode.tactics info s e content
  | .span info content => do
    let info ← info.mapM fun (k, msg) => do return (k, ← msg.export)
    let content ← content.export
    return Export.SlideCode.span info content
  | .fragment w b content => Export.SlideCode.fragment w b <$> content.export
  | .click target idx => do
    let target ← target.export
    return Export.SlideCode.click target idx
  | .commandOutput info =>
    Export.SlideCode.commandOutput <$> info.mapM fun (k, msg) => do return (k, ← msg.export)

/--
Packs a {name}`SlideCode` into an {name}`ExportSlideCode` with de-duplicated tables.
-/
public def SlideCode.exportCode (sc : SlideCode) : ExportSlideCode :=
  let (top, state) := sc.export.run {}
  {state with top}

/--
Reconstructs a {name}`SlideCode` from its exported form using the de-duplication tables.
-/
public partial def importSlideCode
    (data : Highlighting.Export) (esc : Export.SlideCode) : Except String SlideCode :=
  match esc with
  | .hl key => .hl <$> data.toHighlighted key
  | .seq parts => .seq <$> parts.mapM (importSlideCode data ·)
  | .tactics info s e content => do
    let info ← info.mapM data.toGoal
    let content ← importSlideCode data content
    return .tactics info s e content
  | .span info content => do
    let info ← info.mapM fun (k, key) => do return (k, ← data.toMessageContents key)
    let content ← importSlideCode data content
    return .span info content
  | .fragment w b content => .fragment w b <$> importSlideCode data content
  | .click target idx => do
    let target ← importSlideCode data target
    return .click target idx
  | .commandOutput info =>
    .commandOutput <$> info.mapM fun (k, key) => do return (k, ← data.toMessageContents key)

/-- Unpacks an {name}`ExportSlideCode` back to a {name}`SlideCode`. -/
public def ExportSlideCode.toSlideCode (data : ExportSlideCode) : Except String SlideCode :=
  importSlideCode data.toExport data.top

/-- Serializes a {name}`SlideCode` to a compact JSON string with de-duplicated subtrees. -/
public def scToExport (sc : SlideCode) : String :=
  sc.exportCode.toJson.compress

/-- Deserializes a {name}`SlideCode` from its JSON export string. Panics on malformed input. -/
public def scFromExport! (s : String) : SlideCode :=
  match Json.parse s with
  | .error e => panic! s!"Failed to parse SlideCode export as JSON: {e}"
  | .ok v =>
    match ExportSlideCode.fromJson? v with
    | .error e => panic! s!"Failed to deserialize SlideCode export: {e}"
    | .ok ec =>
      match ec.toSlideCode with
      | .error e => panic! s!"Failed to reconstruct SlideCode from export: {e}"
      | .ok sc => sc
