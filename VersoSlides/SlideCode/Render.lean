/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import VersoSlides.SlideCode
public import Verso.Code.Highlighted
import Verso.Output.Html

set_option doc.verso true

/-!
Renders SlideCode trees to HTML for `reveal.js`.
-/


open Verso Output Html
open SubVerso.Highlighting (Highlighted)
open Verso.Code (HighlightHtmlM)
open Lean (Json toJson)

namespace VersoSlides

/--
Extracts format data from goals as a JSON string for the {lit}`data-rich-format` attribute. Returns
{name}`none` if no format data is present in any goal.
-/
private def goalsFormatJson (goals : Array (Highlighted.Goal Highlighted)) : Option String := Id.run do
  let mut hasAny := false
  let mut goalJsons : Array Json := #[]
  for g in goals do
    let mut hypJsons : Array Json := #[]
    for h in g.hypotheses do
      let nameStrs := h.names.map fun t => Json.str (toString t.content)
      let ppType := match h.ppType with
        | some s => Json.str s
        | none => Json.null
      if h.ppType.isSome then hasAny := true
      hypJsons := hypJsons.push (Json.mkObj [
        ("names", Json.arr nameStrs),
        ("ppType", ppType)
      ])
    let ppConcl := match g.ppConclusion with
      | some s => Json.str s
      | none => Json.null
    if g.ppConclusion.isSome then hasAny := true
    goalJsons := goalJsons.push (Json.mkObj [
      ("name", match g.name with | some n => Json.str n | none => Json.null),
      ("goalPrefix", Json.str g.goalPrefix),
      ("hypotheses", Json.arr hypJsons),
      ("ppConclusion", ppConcl)
    ])
  if hasAny then some (Json.compress (Json.arr goalJsons))
  else none

/-- Renders a {name}`FragmentData` style as a CSS class string. -/
private def fragClass (w : FragmentData) : String :=
  match w.style with
  | none => "fragment"
  | some s => "fragment " ++ s

/-- Renders the optional {lit}`data-fragment-index` attribute. -/
private def fragIndexAttr (w : FragmentData) : Array (String × String) :=
  match w.index with
  | some i => #[("data-fragment-index", toString i)]
  | none => #[]

/-- Computes the combined CSS class for a span's severity info. -/
private def spanInfoClass (infos : Array (SubVerso.Highlighting.Highlighted.Span.Kind × α)) : Option String := Id.run do
  let mut k : Option SubVerso.Highlighting.Highlighted.Span.Kind := none
  for (k', _) in infos do
    match k with
    | none => k := some k'
    | some prev =>
      k := some (match prev, k' with
        | .error, _ => .error
        | .warning, .error => .error
        | .warning, _ => .warning
        | .info, other => other)
  k.map (·.«class»)

/-- Renders a {name}`SlideCode` tree to HTML. -/
public def SlideCode.toHtml : SlideCode → HighlightHtmlM g Html
  | .hl content => content.toHtml
  | .seq parts => Html.seq <$> parts.mapM toHtml
  | .tactics info startPos endPos content => do
    let contentHtml ← content.toHtml
    let goalsHtml ←
      if info.isEmpty then
        pure {{ "All goals completed! 🐙" }}
      else
        Html.seq <$> info.mapIdxM (fun i x => x.toHtml Highlighted.toHtml i)
    let fmtAttr := match goalsFormatJson info with
      | some json => #[("data-rich-format", json)]
      | none => #[]
    pure {{
      <span class="tactic" "data-tactic-range"={{s!"{startPos}-{endPos}"}}>
        {{contentHtml}}
        {{Html.tag "span" (#[("class", "tactic-state"), ("style", "display:none")] ++ fmtAttr) goalsHtml}}
      </span>
    }}
  | .span info content => do
    let cls := match spanInfoClass info with
      | some c => "has-info " ++ c
      | none => "has-info"
    let contentHtml ← content.toHtml
    let messagesHtml ← info.mapM fun (s, msg) => do
      pure {{ <code class={{"verso-message " ++ s.«class»}}>
        {{← msg.toHtml [] 10 Highlighted.toHtml}}
      </code> }}
    pure {{
      <span class={{cls}}>
        {{contentHtml}}
        <span class="hover-info messages" style="display:none">
          {{messagesHtml}}
        </span>
      </span>
    }}
  | .fragment w true content => do
    let contentHtml ← content.toHtml
    pure (Html.tag "div" (#[("class", fragClass w)] ++ fragIndexAttr w) contentHtml)
  | .fragment w false content => do
    let contentHtml ← content.toHtml
    pure (Html.tag "span" (#[("class", fragClass w)] ++ fragIndexAttr w) contentHtml)
  | .click target index => do
    let targetHtml ← target.toHtml
    let cls := "fragment slide-click-only"
    let attrs := match index with
      | some i => #[("class", cls), ("data-fragment-index", toString i)]
      | none => #[("class", cls)]
    pure (Html.tag "span" attrs targetHtml)
  | .commandOutput info => do
    -- Use the highest severity for the wrapper class
    let severity := info.foldl (fun acc (s, _) => match acc, s with
      | .error, _ => .error | .warning, .error => .error | .warning, _ => .warning
      | _, other => other) Highlighted.Span.Kind.info
    let messagesHtml ← info.mapM fun (s, msg) => do
      pure {{ <code class={{"verso-message " ++ s.«class»}}>
        {{← msg.toHtml [] 10 Highlighted.toHtml}}
      </code> }}
    pure {{ <div class={{"command-output " ++ severity.«class»}}> {{messagesHtml}} </div> }}
