/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

import VersoSlides.Basic
import Verso.Doc.Elab.Monad

/-!
Code block handlers for external (non-Lean) languages.

These produce `BlockExt.externalCode` blocks whose HTML rendering includes
a `language-*` class so that the bundled reveal.js highlight.js plugin
applies syntax highlighting at presentation time.
-/

open Lean Elab
open Verso Doc Elab
open Lean.Doc.Syntax

namespace VersoSlides

/-- Helper that builds a `Block.other (BlockExt.externalCode lang)` term. -/
private def externalCodeBlock (language : String) (str : StrLit) : DocElabM Term :=
  ``(Verso.Doc.Block.other (BlockExt.externalCode $(quote language) $(quote str.getString)) #[])

@[code_block]
def cpp : CodeBlockExpanderOf Unit
  | (), str => externalCodeBlock "cpp" str

@[code_block]
def c : CodeBlockExpanderOf Unit
  | (), str => externalCodeBlock "c" str

@[code_block]
def rust : CodeBlockExpanderOf Unit
  | (), str => externalCodeBlock "rust" str

end VersoSlides
