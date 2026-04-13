/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

import VersoSlides.Basic
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

private structure DiagramConfig where
  background : Option String := none

section
variable [Monad m] [MonadInfoTree m] [MonadLiftT CoreM m] [MonadEnv m] [MonadError m]

private def DiagramConfig.parse : ArgParse m DiagramConfig :=
  DiagramConfig.mk <$> .named `background .string true

instance : FromArgs DiagramConfig m where
  fromArgs := DiagramConfig.parse
end

/-- Extracts the `viewBox` width from an SVG string produced by Illuminate.
    The viewBox format is `"minX minY width height"`. -/
private def svgViewBoxWidth (svg : String) : Float :=
  let go : Option Float := do
    let parts := (svg.splitOn "viewBox=\"").toArray
    if h : parts.size > 1 then
      let afterViewBox := parts[1]
      let valParts := (afterViewBox.splitOn "\"").toArray
      if h2 : valParts.size > 0 then
        let viewBoxVal := valParts[0]
        let fields := ((viewBoxVal.splitOn " ").filter (· != "")).toArray
        if h3 : fields.size > 2 then
          -- Parse via JSON number parser
          match Lean.Json.parse fields[2] with
          | .ok (.num n) => some n.toFloat
          | _ => failure
        else failure
      else failure
    else failure
  go.getD 640.0

open Lean.Widget Lean.Elab.Term Lean.Meta Illuminate in
private meta unsafe def diagramExpanderUnsafe (config : DiagramConfig) (str : StrLit) :
    DocElabM Term := withoutAsync do
  let altStr ← parserInputString str

  match Parser.runParserCategory (← getEnv) `term altStr (← getFileName) with
  | .error e => throwErrorAt str e
  | .ok stx =>
    let svgStr ← runWithOpenDecls <| runWithVariables fun _vars => do
      let diaTy ← Meta.mkAppM ``Illuminate.Diagram #[.const ``Illuminate.SVG []]
      let e ← Elab.Term.elabTerm stx (some diaTy)
      Term.synthesizeSyntheticMVarsNoPostponing
      let e ← instantiateMVars e

      -- Don't evaluate if elaboration produced errors
      if (← Core.getMessageLog).hasErrors then
        return ""

      -- Evaluate to get SVG string
      let svgExpr := mkApp (mkConst ``Illuminate.diagramToSvg) e
      let svgStr ← evalExpr String (mkConst ``String) svgExpr

      -- Store diagram for widget RPC re-evaluation
      let env ← getEnv
      let opts ← getOptions
      let id ← Illuminate.nextDiagramId.modifyGet fun n => (n, n + 1)
      let sd : Illuminate.StoredDiagram := {
        env, opts, expr := e, gadgets := #[], regions := {}, returnsDwi := false
      }
      Illuminate.diagramStore.modify (·.push (id, sd))

      -- Attach widget with CSS variable defaults for the infoview context
      let widgetSvg :=
        "<div style=\"--verso-text-font-family: sans-serif; --verso-code-font-family: monospace;\">" ++
        "<style>svg text[font-family=\"text\"] { font-family: var(--verso-text-font-family); } " ++
        "svg text[font-family=\"monospace\"] { font-family: var(--verso-code-font-family); }</style>" ++
        svgStr ++ "</div>"
      let props : Json := .mkObj [
        ("exprId", toJson id),
        ("initialSvg", .str widgetSvg),
        ("parameters", .arr #[])]
      savePanelWidgetInfo Illuminate.diagramWidget.javascriptHash.val (pure props) str

      pure svgStr

    -- Compute CSS width: 1 diagram unit = 0.1vw
    let viewBoxW := svgViewBoxWidth svgStr
    let vw := viewBoxW * 0.1
    if vw > 95.0 then
      logWarning m!"diagram is {vw}vw wide, which exceeds the 95vw slide width"
    let cssWidth := s!"{vw}vw"

    let bg := config.background
    ``(Verso.Doc.Block.other (VersoSlides.BlockExt.diagram $(quote svgStr) $(quote cssWidth) $(quote bg))
        #[Verso.Doc.Block.code $(quote str.getString)])

open Lean.Widget Lean.Elab.Term Lean.Meta Illuminate in
@[implemented_by diagramExpanderUnsafe]
private opaque diagramExpanderImpl (config : DiagramConfig) (str : StrLit) : DocElabM Term

@[code_block]
def diagram : CodeBlockExpanderOf DiagramConfig
  | config, str => diagramExpanderImpl config str

end VersoSlides
