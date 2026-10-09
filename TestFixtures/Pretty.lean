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

-- Name, document, available columns, and initial indentation.
public def corpusCases : Array (String × Format × Nat × Nat) :=
  #[("empty", .nil, 80, 0),
    ("wide group", groupedLineDoc, 80, 0),
    ("narrow group", groupedLineDoc, 8, 0),
    ("hard newline", hardLineDoc, 80, 0),
    ("nested align", nestedDoc, 5, 0),
    ("fill paragraph", paragraphDoc, 16, 0),
    ("tagged segment", taggedDoc, 80, 0),
    ("nested tag stack", nestedTaggedDoc, 80, 0),
    ("initial indentation", groupedLineDoc, 8, 3),
    ("forced alignment", .nest 2 ("." ++ .align true ++ "a" ++ .line ++ "b"), 5, 0),
    ("tagged newline", .tag 7 ("left" ++ .line ++ "right"), 80, 0),
    ("after tag", .tag 7 "x" ++ "plain", 80, 0),
    ("Unicode wrapping", .group ("α😀" ++ .line ++ "βγ"), 4, 0),
    ("negative nesting", .nest 4 ("a" ++ .line ++ .nest (-2) ("b" ++ .line ++ "c")), 8, 0)]

private def segmentsJson (segments : Array Segment) : Lean.Json := .arr <| segments.map
  fun segment => Lean.Json.mkObj [
    ("text", .str segment.text),
    ("tags", .arr <| segment.tags.map fun tag => .str (toString tag))]

private def resultJson (segments : Array Segment) : Lean.Json :=
  Lean.Json.mkObj [("segments", segmentsJson segments)]

private def nativeCorpus : Lean.Json := .arr <| corpusCases.map
    fun (name, format, width, indent) => Lean.Json.mkObj [
      ("name", .str name), ("format", SubVerso.Highlighting.formatToJson format),
      ("width", Lean.toJson width), ("indent", Lean.toJson indent),
      ("result", resultJson <| VersoSlides.VirPrettyM.formatSegments format width indent)]

public def nativeCorpusJson : String := nativeCorpus.compress

/-- Test fixture consumed by the ordinary Playwright native/Wasm comparison. -/
public def writeNativeCorpus (path : System.FilePath) : IO Unit :=
  IO.FS.writeFile path nativeCorpusJson

end TestFixtures.Pretty
