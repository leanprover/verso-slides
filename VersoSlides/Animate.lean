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

/-- A step in a slide animation. Extends {name}`Illuminate.Step` with an optional
    reveal.js fragment index for interleaving with other slide fragments. -/
public structure SlideStep extends Illuminate.Step where
  /-- When set, the hidden fragment created for this pause step gets an explicit
      {lit}`data-fragment-index`, allowing it to interleave with other slide fragments. -/
  fragmentIndex : Option Nat := none
deriving Inhabited, BEq, Repr

/-- A slide animation definition. The code block body should be an expression of this type. -/
public structure SlideAnimation where
  /-- The animation steps, with optional fragment indices for interleaving. -/
  steps : List SlideStep
  /-- The render function, mapping per-step progress values to a diagram. -/
  render : Vector Float steps.length → Illuminate.Diagram Illuminate.SVG

/-- The result of compiling a {name}`SlideAnimation` for embedding in a slide. -/
structure CompiledSlideAnimation where
  /-- The compiled animation data. -/
  compiled : Illuminate.CompiledAnimation
  /-- Fragment indices for pause steps (one per pause step, in order). -/
  fragmentIndices : Array (Option Nat)

/-- Compiles a {name}`SlideAnimation` into a {name}`CompiledSlideAnimation`. -/
def SlideAnimation.compile (sa : SlideAnimation) (fps : Nat := 60) : CompiledSlideAnimation where
  compiled :=
    let steps := sa.steps.map SlideStep.toStep
    have : steps.length = sa.steps.length := List.length_map ..
    Illuminate.compileAnimation steps (this ▸ sa.render) (fps := fps)
  fragmentIndices :=
    (sa.steps.filterMap fun s =>
      if s.pause then some s.fragmentIndex else none).toArray

private structure AnimateConfig where
  fps : Nat := 60
  background : Option String := none
  autoplay : Bool := false

section
variable [Monad m] [MonadInfoTree m] [MonadLiftT CoreM m] [MonadEnv m] [MonadError m]

private def AnimateConfig.parse : ArgParse m AnimateConfig :=
  AnimateConfig.mk <$> .namedD `fps .nat 60 <*> .named `background .string true <*> .flag `autoplay false

instance : FromArgs AnimateConfig m where
  fromArgs := AnimateConfig.parse
end

private initialize animContainerCounter : IO.Ref Nat ← IO.mkRef 0

open Lean.Widget Lean.Elab.Term Lean.Meta Illuminate in
private meta unsafe def animateExpanderUnsafe (config : AnimateConfig) (str : StrLit) :
    DocElabM Term := withoutAsync do
  let altStr ← parserInputString str

  let env ← getEnv
  let fileName ← getFileName
  match Parser.runParserCategory env `term altStr fileName with
  | .error e => throwErrorAt str e
  | .ok bodyStx =>

  let fpsLit := Syntax.mkNumLit (toString config.fps)
  let callStx ← ``(SlideAnimation.compile $(⟨bodyStx⟩) (fps := $fpsLit))

  let (animDataJson, cssWidth, fragmentIndices) ← runWithOpenDecls <| runWithVariables fun _vars => do
    let compiledTy := Lean.mkConst ``CompiledSlideAnimation
    let e ← Elab.Term.elabTerm callStx (some compiledTy)
    Term.synthesizeSyntheticMVarsNoPostponing
    let e ← instantiateMVars e

    if (← Core.getMessageLog).hasErrors then
      return ("", "", #[])

    let csa ← evalExpr CompiledSlideAnimation compiledTy e (safety := .unsafe)

    -- Validate: explicit indices must be strictly increasing
    let mut lastIdx : Option Nat := none
    for idx in csa.fragmentIndices do
      if let some i := idx then
        if let some last := lastIdx then
          if i ≤ last then
            throwErrorAt str m!"animation fragment indices must be strictly increasing, but got {last} followed by {i}"
        lastIdx := some i

    let ca := csa.compiled

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

    pure (animJson, cssWidth, csa.fragmentIndices)

  -- Generate unique container ID
  let containerId ← animContainerCounter.modifyGet fun n =>
    (s!"illuminate-anim-{n}", n + 1)

  let bg := config.background
  let autoplay := config.autoplay
  ``(Verso.Doc.Block.other
      (VersoSlides.BlockExt.animate $(quote containerId) $(quote animDataJson) $(quote cssWidth) $(quote bg) $(quote fragmentIndices) $(quote autoplay))
      #[Verso.Doc.Block.code $(quote str.getString)])

open Lean.Widget Lean.Elab.Term Lean.Meta Illuminate in
@[implemented_by animateExpanderUnsafe]
private opaque animateExpanderImpl (config : AnimateConfig) (str : StrLit) : DocElabM Term

@[code_block]
def «animate» : CodeBlockExpanderOf AnimateConfig
  | config, str => animateExpanderImpl config str

end VersoSlides
