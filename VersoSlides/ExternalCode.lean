/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

module

-- The expanders below refer to declarations from `VersoSlides.Basic` inside generated
-- quotations. These references are not currently recorded as dependencies for Shake.
meta import VersoSlides.Basic -- shake: keep
public import VersoSlides.Basic
public import Verso.Code.External
import Verso.Code.Highlighted
public meta import Verso.Code.External
public import VersoSlides.SlideCode
public meta import VersoSlides.SlideCode
public import VersoSlides.SlideCode.Export
public meta import VersoSlides.InlineLean

open Lean
open Verso.ArgParse
open Verso.Doc (Arg)
open Verso.Doc.Elab
open Verso.Code.External (CodeConfig CodeContext ExternalCode anchored)
open SubVerso.Highlighting (Highlighted hlToExport)

public section

namespace VersoSlides

/-- Removes all proof states from highlighted code. -/
private partial def dropProofStates : Highlighted → Highlighted
  | .tactics _ _ _ x => dropProofStates x
  | .span info x => .span info (dropProofStates x)
  | .seq xs => .seq (xs.map dropProofStates)
  | hl => hl

/-- Removes proof states from highlighted code when the configuration disables them. -/
private def applyCodeConfig (hl : Highlighted) (cfg : CodeConfig) : Highlighted :=
  if cfg.showProofStates then hl else dropProofStates hl

/-- Builds a Lean code box from highlighted code. -/
private def codeBox (hl : Highlighted) (panel stretch : Bool) : Verso.Doc.Block Slides :=
  let hl := hl.trim
  let contents := #[Verso.Doc.Block.code hl.toString]
  match fragmentize hl with
  | .ok sc => .other (BlockExt.slideCode (scToExport sc) panel stretch) contents
  | .error _ => .other (BlockExt.leanCode (hlToExport hl) panel) contents

/-- Builds inline Lean code from highlighted code. -/
private def inlineCode (hl : Highlighted) : Verso.Doc.Inline Slides :=
  let hl := hl.trim
  let contents := #[Verso.Doc.Inline.code hl.toString]
  match fragmentize hl with
  | .ok sc => .other (InlineExt.slideCode (scToExport sc)) contents
  | .error _ => .other (InlineExt.leanCode (hlToExport hl)) contents

/--
Renders external code with the slide code renderer.

Code boxes have an info panel and stretch to fill the slide. Message blocks render as command output
sized to their content, and inline messages render as plain code.
-/
@[no_expose] instance : ExternalCode Slides where
  leanBlock hl cfg := codeBox (applyCodeConfig hl cfg) true true
  leanInline hl cfg := inlineCode (applyCodeConfig hl cfg)
  leanOutputBlock message _ _ := codeBox (.point message.severity message.contents) false false
  leanOutputInline message _ expandTraces :=
    .code (message.toString (expandTraces := expandTraces)).trimAscii.copy

/-- Sets the info panel and stretch behavior of a Lean code box, leaving other blocks unchanged. -/
def setCodeBoxLayout (panel stretch : Bool) : Verso.Doc.Block Slides → Verso.Doc.Block Slides
  | .other (.slideCode e _ _) xs => .other (.slideCode e panel stretch) xs
  | .other (.leanCode e _) xs => .other (.leanCode e panel) xs
  | b => b

meta section

/--
Consumes the {lit}`panel` and {lit}`stretch` flags, runs {name}`expand` on the remaining arguments,
and applies the flags to the code boxes that it produces.
-/
private def withCodeBoxLayout (args : Array Arg) (expand : Array Arg → DocElabM (Array Term)) :
    DocElabM (Array Term) := do
  let (panel, stretch, rest) ← Verso.ArgParse.run
    ((·, ·, ·) <$> panelFlag <*> .flag `stretch true <*> .remaining) args
  (← expand rest).mapM fun t =>
    ``(VersoSlides.setCodeBoxLayout $(quote panel) $(quote stretch) $t)

/--
Reports malformed slide magic comments in the code that {name}`args` select.

Failures to load the code or find the anchor are ignored because the code's expander reports them.
-/
private def checkMagicComments (args : Array Arg) : DocElabM Unit := do
  try
    let cfg ← parseThe CodeContext args
    let { anchors, code, .. } ← anchored cfg.project cfg.module cfg.module
    let hl? := match cfg.anchor? with
      | some a => anchors[a.getId.toString]?
      | none => some code
    if let some hl := hl? then
      if let .error msg := fragmentize hl.trim then logError msg
  catch _ => pure ()

/-- Rewrites a positional anchor name to the named {lit}`anchor` argument. -/
private def namedAnchorArg (args : Array Arg) : Array Arg :=
  if let some (Verso.Doc.Arg.anon a) := args[0]? then
    #[Verso.Doc.Arg.named .missing (mkIdent `anchor) a] ++ args.drop 1
  else args

/--
Includes the contents of an example module in a code box.

The {lit}`panel` and {lit}`stretch` flags control the box's layout.
-/
@[code_block_expander «module»]
def «module» : CodeBlockExpander
  | args, code => withCodeBoxLayout args fun rest => do
    let terms ← Verso.Code.External.module rest code
    checkMagicComments rest
    return terms

/--
Includes the contents of an anchor from an example module in a code box.

The {lit}`panel` and {lit}`stretch` flags control the box's layout.
-/
@[code_block_expander anchor]
def anchor : CodeBlockExpander
  | args, code => withCodeBoxLayout args fun rest => do
    let terms ← Verso.Code.External.anchor rest code
    checkMagicComments (namedAnchorArg rest)
    return terms

/--
Shows the first term of an example module that matches the provided string.

As a code block, it accepts the {lit}`panel` and {lit}`stretch` flags.
-/
@[code_block_expander moduleTerm]
def moduleTerm : CodeBlockExpander
  | args, term => withCodeBoxLayout args (Verso.Code.External.moduleTermBlockExp · term)

/--
Shows the first term of an anchor that matches the provided string.

As a code block, it accepts the {lit}`panel` and {lit}`stretch` flags.
-/
@[code_block_expander anchorTerm]
def anchorTerm : CodeBlockExpander
  | args, term => withCodeBoxLayout args (Verso.Code.External.anchorTermBlockExp · term)

@[role_expander «module», inherit_doc «module»]
def moduleRole : RoleExpander := Verso.Code.External.moduleInlineRole

@[role_expander anchor, inherit_doc anchor]
def anchorRole : RoleExpander := Verso.Code.External.anchorInlineRole

@[role_expander moduleTerm, inherit_doc moduleTerm]
def moduleTermRole : RoleExpander := Verso.Code.External.moduleTerm

@[role_expander anchorTerm, inherit_doc anchorTerm]
def anchorTermRole : RoleExpander := Verso.Code.External.anchorTerm

end

export Verso.Code.External (moduleName anchorName moduleOut moduleInfo moduleError moduleWarning
  anchorInfo anchorError anchorWarning)

end VersoSlides
