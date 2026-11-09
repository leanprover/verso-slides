/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

module

public import VersoSlides.VirPrettyM
import SubVerso.Highlighting.Highlighted

open Std
open VersoSlides.Pretty

namespace TestFixtures.Pretty

public def groupedLineDoc : Format :=
  Format.group ("hello" ++ Format.line ++ "world")

public def hardLineDoc : Format :=
  "αβ" ++ Format.text "\n" ++ "γ"

public def nestedDoc : Format :=
  Format.nest 2 ("." ++ Format.align false ++ "a" ++ Format.line ++ "b")

public def paragraphDoc : Format :=
  Format.fill <|
    "lean" ++ Format.line ++
    "ir" ++ Format.line ++
    "runs" ++ Format.line ++
    "format.pretty" ++ Format.line ++
    "inside wasm"

public def taggedDoc : Format :=
  Format.tag 7 "hello"

public def nestedTaggedDoc : Format :=
  Format.tag 7 ("outer" ++ Format.tag 8 "inner" ++ "tail")

private def corpusCases : Array (String × Format × Nat) :=
  #[("empty", .nil, 80), ("wide group", groupedLineDoc, 80), ("narrow group", groupedLineDoc, 8),
     ("hard newline", hardLineDoc, 80), ("nested align", nestedDoc, 5),
     ("fill paragraph", paragraphDoc, 16), ("tagged segment", taggedDoc, 80),
     ("nested tag stack", nestedTaggedDoc, 80)]

private def segmentsJson (segments : Array Segment) : Lean.Json := .arr <| segments.map
  fun segment => Lean.Json.mkObj [
    ("text", .str segment.text),
    ("tags", .arr <| segment.tags.map fun tag => .str (toString tag))]

private def resultJson (segments : Array Segment) : Lean.Json :=
  Lean.Json.mkObj [("segments", segmentsJson segments)]

private def nativeCorpus : Lean.Json := .arr <| corpusCases.map
    fun (name, format, width) => Lean.Json.mkObj [
      ("name", .str name), ("format", SubVerso.Highlighting.formatToJson format),
      ("width", Lean.toJson width), ("indent", Lean.toJson (0 : Nat)),
      ("result", resultJson <| VersoSlides.VirPrettyM.formatSegments format width 0)]

public def nativeCorpusJson : String := nativeCorpus.compress

/-- Test fixture consumed by the ordinary Playwright native/Wasm comparison. -/
public def writeNativeCorpus (path : System.FilePath) : IO Unit :=
  IO.FS.writeFile path nativeCorpusJson

end TestFixtures.Pretty
