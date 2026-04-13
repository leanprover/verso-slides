/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

import VersoSlides.Basic
import VersoSlides.Diagram
import Verso.Doc.ArgParse
import Verso.Doc.Elab.Monad
import VersoManual.InlineLean
import Illuminate

open Verso ArgParse Doc Elab
open Lean Elab
open Verso.SyntaxUtils (parserInputString)
open Verso.Genre.Manual.InlineLean.Scopes (runWithOpenDecls runWithVariables)
open Verso (withoutAsync)
open Lean.Doc.Syntax

namespace VersoSlides

private structure AnimateConfig where
  fps : Nat := 60
  background : Option String := none

section
variable [Monad m] [MonadInfoTree m] [MonadLiftT CoreM m] [MonadEnv m] [MonadError m]

private def AnimateConfig.parse : ArgParse m AnimateConfig :=
  AnimateConfig.mk <$> .namedD `fps .nat 60 <*> .named `background .string true

instance : FromArgs AnimateConfig m where
  fromArgs := AnimateConfig.parse
end

private initialize animContainerCounter : IO.Ref Nat ← IO.mkRef 0

/-- Recursively peels `open ... in` wrappers from a syntax node.
    Returns the collected open-decl syntaxes (outermost first) and the innermost term. -/
private partial def peelOpens (stx : Syntax) : Array Syntax × Syntax :=
  if stx.getKind == ``Lean.Parser.Term.open then
    let args := stx.getArgs
    if h : args.size ≥ 4 then
      let openDecl := args[1]
      let body := args[3]
      let (inner, rest) := peelOpens body
      (#[openDecl] ++ inner, rest)
    else
      (#[], stx)
  else
    (#[], stx)

open Lean.Widget Lean.Elab.Term Lean.Meta Illuminate in
private meta unsafe def animateExpanderUnsafe (config : AnimateConfig) (str : StrLit) :
    DocElabM Term := withoutAsync do
  let altStr ← parserInputString str

  -- Parse the body as `term:max term`. The first term may be wrapped in
  -- `open ... in` prefixes that should scope over the whole `compileAnimation` call.
  let env ← getEnv
  let fileName ← getFileName

  -- Parse the body as a single term via `runParserCategory`, then peel off any
  -- `open ... in` prefix so the opens scope over the entire `compileAnimation` call.
  match Parser.runParserCategory env `term altStr fileName with
  | .error e => throwErrorAt str e
  | .ok parsed =>
  -- Peel `open ... in` wrappers: the innermost term should be `steps renderFn`
  -- which the parser sees as function application `steps(renderFn)`.
  let (openDecls, innerStx) := peelOpens parsed

  -- The inner term is an application node `steps renderFn`. The parser sees
  -- `[steps] fun v => ...` as `Term.app` with args[0] = list, args[1] = null(renderFn).
  let (stepsStx, renderStx) ←
    if innerStx.getKind == ``Lean.Parser.Term.app then
      let args := innerStx.getArgs
      if h : args.size ≥ 2 then
        let fnArgs := args[1].getArgs
        if h2 : fnArgs.size ≥ 1 then
          pure (args[0], fnArgs[0])
        else
          throwErrorAt str "expected two terms: step list and render function"
      else
        throwErrorAt str "expected two terms: step list and render function"
    else
      throwErrorAt str "expected two terms: step list and render function"

  -- Build: `open X in open Y in compileAnimation steps render (fps := N)`
  let fpsLit := Syntax.mkNumLit (toString config.fps)
  let mut callStx ← ``(Illuminate.compileAnimation $(⟨stepsStx⟩) $(⟨renderStx⟩) (fps := $fpsLit))
  for decl in openDecls.reverse do
    callStx ← `(open $(⟨decl⟩) in $callStx)

  let (animDataJson, cssWidth) ← runWithOpenDecls <| runWithVariables fun _vars => do
    let compiledAnimTy := Lean.mkConst ``Illuminate.CompiledAnimation
    let e ← Elab.Term.elabTerm callStx (some compiledAnimTy)
    Term.synthesizeSyntheticMVarsNoPostponing
    let e ← instantiateMVars e

    -- Don't evaluate if elaboration produced errors
    if (← Core.getMessageLog).hasErrors then
      return ("", "")

    let ca ← evalExpr Illuminate.CompiledAnimation compiledAnimTy e (safety := .unsafe)

    -- Serialize animation data
    let animJson := Illuminate.compiledAnimationToJson ca

    -- Extract viewBox width from first segment's sync frame
    let firstSvg := ca.segments[0]?.map (·.syncFrame) |>.getD ""
    let viewBoxW := svgViewBoxWidth firstSvg
    let vw := viewBoxW * 0.1
    if vw > 95.0 then
      logWarning m!"animation is {vw}vw wide, which exceeds the 95vw slide width"
    let cssWidth := s!"{vw}vw"

    -- Widget for infoview
    let animLeanJson := Illuminate.compiledAnimationToLeanJson ca
    let props : Json := .mkObj [("animData", animLeanJson)]
    savePanelWidgetInfo Illuminate.animateWidget.javascriptHash.val (pure props) str

    pure (animJson, cssWidth)

  -- Generate unique container ID
  let containerId ← animContainerCounter.modifyGet fun n =>
    (s!"illuminate-anim-{n}", n + 1)

  let bg := config.background
  ``(Verso.Doc.Block.other
      (VersoSlides.BlockExt.animate $(quote containerId) $(quote animDataJson) $(quote cssWidth) $(quote bg))
      #[Verso.Doc.Block.code $(quote str.getString)])

open Lean.Widget Lean.Elab.Term Lean.Meta Illuminate in
@[implemented_by animateExpanderUnsafe]
private opaque animateExpanderImpl (config : AnimateConfig) (str : StrLit) : DocElabM Term

@[code_block]
def «animate» : CodeBlockExpanderOf AnimateConfig
  | config, str => animateExpanderImpl config str

end VersoSlides
