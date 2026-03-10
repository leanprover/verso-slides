/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import Verso.Doc

set_option doc.verso true
/-!
A Verso genre for reveal.js slide presentations
-/

--open Verso Doc

namespace VersoSlides

/-- Document-level presentation configuration -/
public structure Config where
  vertical : Bool := false
  theme : String := "black"
  navigationMode : String := "default"
  transition : String := "slide"
  width : Nat := 960
  height : Nat := 700
  margin : Float := 0.04
  controls : Bool := true
  progress : Bool := true
  slideNumber : Bool := false
  hash : Bool := true
  center : Bool := true
  extraCss : Array String := #[]
  extraJs : Array String := #[]
  outputDir : System.FilePath := "_slides"
deriving Inhabited

/--
Per-slide metadata for reveal.js presentations, used in {lit}`%%%` blocks

All fields are optional so unspecified values fall back to document-level
defaults or reveal.js defaults.
-/
public structure SlideMetadata where
  /- Per-slide metadata (used on individual slides) -/
  vertical : Option Bool := none
  transition : Option String := none
  transitionSpeed : Option String := none
  backgroundColor : Option String := none
  backgroundImage : Option String := none
  backgroundSize : Option String := none
  backgroundPosition : Option String := none
  backgroundRepeat : Option String := none
  backgroundOpacity : Option Float := none
  backgroundVideo : Option String := none
  backgroundVideoLoop : Option Bool := none
  backgroundVideoMuted: Option Bool := none
  backgroundIframe : Option String := none
  autoAnimate : Option Bool := none
  autoAnimateId : Option String := none
  autoAnimateEasing : Option String := none
  autoAnimateDuration : Option Float := none
  autoAnimateUnmatched : Option Bool := none
  autoAnimateRestart : Option Bool := none
  backgroundGradient : Option String := none
  backgroundTransition : Option String := none
  backgroundInteractive: Option Bool := none
  timing : Option Nat := none
  visibility : Option String := none
  state : Option String := none
  /- Document-level configuration (only meaningful on the top-level Part's metadata block) -/
  theme : Option String := none
  slideNumber : Option Bool := none
  controls : Option Bool := none
  progress : Option Bool := none
  hash : Option Bool := none
  center : Option Bool := none
  width : Option Nat := none
  height : Option Nat := none
  margin : Option Float := none
  navigationMode : Option String := none
deriving Inhabited, BEq, Repr, Lean.ToJson, Lean.FromJson

/-- Extracts document-level {name}`Config` from the top-level {name}`SlideMetadata`. -/
public def Config.fromMetadata (md : SlideMetadata) (base : Config := {}) : Config where
  vertical := md.vertical.getD base.vertical
  theme := md.theme.getD base.theme
  navigationMode := md.navigationMode.getD base.navigationMode
  transition := md.transition.getD base.transition
  width := md.width.getD base.width
  height := md.height.getD base.height
  margin := md.margin.getD base.margin
  controls := md.controls.getD base.controls
  progress := md.progress.getD base.progress
  slideNumber := md.slideNumber.getD base.slideNumber
  hash := md.hash.getD base.hash
  center := md.center.getD base.center
  extraCss := base.extraCss
  extraJs := base.extraJs
  outputDir := base.outputDir

/-- Custom block-level elements for the Slides genre -/
public inductive BlockExt where
  /-- Speaker notes: wraps children in `<aside class="notes">`. -/
  | notes
  /-- Fragment with push-down semantics: pushes class onto each child block. -/
  | fragment (style : Option String) (index : Option Nat)
  /-- Generic attribute directive with push-down semantics. -/
  | attr (attrs : Array (String × String))
  /-- Wraps ALL children in a `<div>` with the given attributes. -/
  | wrap (attrs : Array (String × String))
  /-- Elaborated Lean code block with syntax highlighting (fallback when fragmentize fails). -/
  | leanCode (hlExport : String) (panel : Bool)
  /-- Fragmentized Lean code block, serialized via {lit}`ExportSlideCode`. -/
  | slideCode (scExport : String) (panel : Bool)
  /-- External (non-Lean) code block with a language tag for highlight.js. -/
  | externalCode (language : String) (code : String)
deriving BEq, Repr, Lean.ToJson, Lean.FromJson

/-- Custom inline elements for the Slides genre -/
public inductive InlineExt where
  /-- Inline fragment: wraps content in `<span class="fragment ...">`. -/
  | fragment (style : Option String) (index : Option Nat)
  /-- Wraps content in a `<span>` with the given attributes. -/
  | styled (attrs : Array (String × String))
  /-- Elaborated inline Lean code with syntax highlighting (fallback when fragmentize fails). -/
  | leanCode (hlExport : String)
  /-- Fragmentized inline Lean code, serialized via {lit}`ExportSlideCode`. -/
  | slideCode (scExport : String)
deriving BEq, Repr, Lean.ToJson, Lean.FromJson

/-- The Slides genre for reveal.js presentations -/
@[expose]
public def Slides : Verso.Doc.Genre where
  PartMetadata := SlideMetadata
  Block := BlockExt
  Inline := InlineExt
  TraverseContext := Unit
  TraverseState := Unit

-- Type alias instances
public instance : Repr Slides.PartMetadata := inferInstanceAs (Repr SlideMetadata)
public instance : Repr Slides.Block := inferInstanceAs (Repr BlockExt)
public instance : Repr Slides.Inline := inferInstanceAs (Repr InlineExt)
public instance : BEq Slides.PartMetadata := inferInstanceAs (BEq SlideMetadata)
public instance : BEq Slides.Block := inferInstanceAs (BEq BlockExt)
public instance : BEq Slides.Inline := inferInstanceAs (BEq InlineExt)
public instance : Lean.ToJson Slides.PartMetadata := inferInstanceAs (Lean.ToJson SlideMetadata)
public instance : Lean.ToJson Slides.Block := inferInstanceAs (Lean.ToJson BlockExt)
public instance : Lean.ToJson Slides.Inline := inferInstanceAs (Lean.ToJson InlineExt)
public instance : Lean.FromJson Slides.PartMetadata := inferInstanceAs (Lean.FromJson SlideMetadata)
public instance : Lean.FromJson Slides.Block := inferInstanceAs (Lean.FromJson BlockExt)
public instance : Lean.FromJson Slides.Inline := inferInstanceAs (Lean.FromJson InlineExt)

-- Trivial traversal instances
public instance : Verso.Doc.TraversePart Slides where
public instance : Verso.Doc.TraverseBlock Slides where

public abbrev TraverseM := ReaderT Unit (StateT Unit IO)

public instance : Verso.Doc.Traverse Slides TraverseM where
  part _ := pure none
  block _ := pure ()
  inline _ := pure ()
  genrePart _ _ := pure none
  genreBlock _ _ := pure none
  genreInline _ _ := pure none
