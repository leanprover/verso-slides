/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import Verso.Doc
public import VersoSlides.ImgSrc
public import VersoManual.Html.CssFile
import Std.Data.HashMap

open Lean

set_option doc.verso true
/-!
A Verso genre for `reveal.js` slide presentations
-/

--open Verso Doc

namespace VersoSlides

/--
Extra CSS file to bundle alongside the slideshow.

The {lit}`filename` is used both as the output path (relative to the slideshow
output directory) and as the {lit}`href` of the emitted {lit}`<link>` tag, and
{lit}`contents` is written verbatim to that path.
-/
public abbrev CssFile := Verso.Genre.Manual.CssFile

/--
A single binary file bundled with a custom theme.

The {lit}`filename` is the output path relative to the slideshow output
directory (subdirectories are created on demand). Use {lit}`include_bin` or
{lit}`include_bin_dir` from {lit}`VersoUtil.BinFiles` to embed assets at
compile time.
-/
public structure ThemeAsset where
  filename : String
  contents : ByteArray
deriving Inhabited

/--
Convert the output of {lit}`include_bin_dir` into a {name}`ThemeAsset` array.

{lit}`include_bin_dir "dir"` returns an array of {lit}`(path, contents)`
pairs whose paths begin with {lit}`"dir/"`. Passing the array through this
helper writes every file under that same prefix in the slideshow output
directory.
-/
public def ThemeAsset.fromDir (files : Array (String × ByteArray)) : Array ThemeAsset :=
  files.map fun (path, contents) => { filename := path, contents }

/--
A user-supplied `reveal.js` theme: a stylesheet plus any companion assets
(fonts, background images, logos, …) that the stylesheet references.

The {lit}`stylesheet` is written and linked in place of the bundled
reveal.js theme. Each entry in {lit}`assets` is written verbatim to its
{lit}`filename` under the output directory. All filenames (the stylesheet's
and every asset's) must be distinct from each other and from every
{lit}`extraCss` entry; {lit}`slidesMain` raises an error otherwise.
-/
public structure CustomTheme where
  stylesheet : CssFile
  assets : Array ThemeAsset := #[]

public instance : Inhabited CustomTheme where
  default := { stylesheet := { filename := "theme.css", contents := ⟨""⟩ } }

/--
Selects the `reveal.js` theme for a slideshow.

Either a string naming one of the vendored `reveal.js` themes (such as
{lit}`"black"` or {lit}`"white"`), or a user-supplied {name}`CustomTheme`
that replaces the theme stylesheet entirely and may bundle companion
assets. A string coerces to {name}`Theme.builtin` automatically, so
existing callers using {lit}`theme := "black"` continue to work, and a
{name}`CssFile` coerces to a bare {name}`CustomTheme` so
{lit}`theme := .custom myCss` also continues to work when no asset bundle
is needed.
-/
public inductive Theme where
  /-- One of the `reveal.js` themes bundled with VersoSlides, selected by name. -/
  | builtin (name : String)
  /--
  A user-supplied theme that fully replaces the bundled theme. The
  stylesheet and every asset file are written alongside {lit}`index.html`
  in the output directory.
  -/
  | custom (theme : CustomTheme)
deriving Inhabited

public instance : Coe String Theme := ⟨.builtin⟩
public instance : Coe CssFile CustomTheme := ⟨fun css => { stylesheet := css }⟩

/--
Which `reveal.js` navigation method to call when auto-sliding advances the
deck. Corresponds to the `reveal.js` {lit}`autoSlideMethod` config option,
which it accepts as a JavaScript function. We expose the handful of
navigation methods that make sense for auto-advancing, each mapped to the
matching `reveal.js` call at render time.
-/
public inductive AutoSlideMethod where
  /-- The `reveal.js` default: {lit}`Reveal.navigateNext()` — advances through fragments, then horizontal and vertical slides in order. -/
  | next
  /-- {lit}`Reveal.navigateRight()` — advance only along the horizontal axis. -/
  | right
  /-- {lit}`Reveal.navigateDown()` — advance only through vertical sub-slides of the current stack. -/
  | down
  /--
  Escape hatch for an arbitrary JavaScript expression. The string is emitted
  verbatim as the value of the {lit}`autoSlideMethod` config option, so it
  must evaluate to a function — for example
  {lit}`"() => Reveal.left()"` or {lit}`"() => Reveal.slide(0)"`.
  -/
  | js (code : String)
deriving Inhabited, BEq, Repr, ToJson, FromJson

/-- Document-level presentation configuration -/
public structure Config where
  vertical : Bool := false
  theme : Theme := "black"
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
  /--
  Auto-advance interval in milliseconds. {lit}`0` (the `reveal.js` default)
  disables the feature; any positive value advances slides every N ms and
  exposes a play/pause control. Individual slides can override this through
  the per-slide {lit}`autoSlide` field on {lit}`SlideMetadata`.
  -/
  autoSlide : Nat := 0
  /--
  When {lit}`true` (the `reveal.js` default), auto-sliding pauses as soon as
  the audience interacts with the deck (click, key press, etc.). Set to
  {lit}`false` for unattended kiosk-style playback that keeps advancing
  through user input. This is a global option only — `reveal.js` has no
  per-slide override.
  -/
  autoSlideStoppable : Bool := true
  /--
  Which navigation method `reveal.js` uses when auto-sliding advances. See
  {name}`AutoSlideMethod`. Global only.
  -/
  autoSlideMethod : AutoSlideMethod := .next
  extraCss : Array CssFile := #[]
  extraJs : Array String := #[]
  outputDir : System.FilePath := "_slides"
deriving Inhabited

/--
Per-slide metadata for `reveal.js` presentations, used in {lit}`%%%` blocks.

Every field maps to a per-slide `reveal.js` feature — either a {lit}`data-*`
attribute on the slide's {lit}`<section>` or a structural flag like
{lit}`vertical`. Global {lit}`Reveal.initialize` options live on
{name}`Config` instead and are passed to {lit}`slidesMain` in Lean, not via
{lit}`%%%` blocks.

All fields are optional so unspecified values fall back to document-level
defaults or `reveal.js` defaults.
-/
public structure SlideMetadata where
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
  /-- Per-slide override of the auto-advance interval in milliseconds (`reveal.js` {lit}`data-autoslide`). -/
  autoSlide : Option Nat := none
deriving Inhabited, BEq, Repr, ToJson, FromJson

/-- Style options for the {lit}`:::table` directive. All features are off by default. -/
public structure TableStyle where
  /-- If true, the first row is rendered as {lit}`<thead>` with {lit}`<th scope="col">` cells. -/
  colHeaders  : Bool          := false
  /-- If true, the first cell of each body row is rendered as {lit}`<th scope="row">`. -/
  rowHeaders  : Bool          := false
  /-- If true, alternating body rows get distinct background colors. -/
  stripedRows : Bool          := false
  /-- If true, alternating columns get distinct background colors. -/
  stripedCols : Bool          := false
  /-- If true, horizontal separator lines are drawn between data rows. -/
  rowSeps     : Bool          := false
  /-- If true, vertical separator lines are drawn between data columns. -/
  colSeps     : Bool          := false
  /-- If true, a thicker separator is drawn after the header row and/or column. -/
  headerSep   : Bool          := false
  /-- If true, separator lines are added to the outer edges of the table. -/
  border      : Bool          := false
  /-- If set, overrides the cell padding, e.g. {lit}`"0.4em 0.6em"`. -/
  cellGap     : Option String := none
deriving BEq, Repr, ToJson, FromJson, Inhabited

public instance : Quote TableStyle where
  quote s := Syntax.mkApp (mkCIdent ``TableStyle.mk) #[
    quote s.colHeaders,  quote s.rowHeaders,  quote s.stripedRows, quote s.stripedCols,
    quote s.rowSeps,     quote s.colSeps,     quote s.headerSep,   quote s.border,
    quote s.cellGap
  ]

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
  /-- Non-Lean code block with a language tag for highlight.js. -/
  | otherLanguage (language : String) (code : String)
  /-- Custom CSS block to be injected into the page header. -/
  | css (content : String)
  /-- Illuminate diagram rendered to SVG. -/
  | diagram (svg : String) (cssWidth : String) (background : Option String)
  /-- Illuminate animation compiled to JSON for `reveal.js` fragment-driven playback. -/
  | animate (containerId : String) (animDataJson : String) (cssWidth : String) (background : Option String) (fragmentIndices : Array (Option Nat)) (autoplay : Bool)
  /-- Table rendered from a nested list of lists. -/
  | table (columns : Nat) (style : TableStyle)
deriving BEq, Repr, ToJson, FromJson


/-- Custom inline elements for the Slides genre -/
public inductive InlineExt where
  /-- Inline fragment: wraps content in `<span class="fragment ...">`. -/
  | fragment (style : Option String) (index : Option Nat)
  /-- Wraps content in a `<span>` with the given attributes. -/
  | styled (attrs : Array (String × String))
  /-- Image with configurable dimensions. All fields determined at elaboration time. -/
  | image (src : ImgSrc) (alt : String) (width : Option String) (height : Option String) (cssClass : Option String)
  /-- Elaborated inline Lean code with syntax highlighting (fallback when fragmentize fails). -/
  | leanCode (hlExport : String)
  /-- Fragmentized inline Lean code, serialized via {lit}`ExportSlideCode`. -/
  | slideCode (scExport : String)
  /-- A reference to a Lean name (constant), with syntax highlighting and hover info. -/
  | name (hlExport : String)
deriving BEq, Repr, ToJson, FromJson

/-- State accumulated during the traversal pass. -/
public structure TraverseState where
  /-- CSS blocks collected from {lit}`css` code blocks, injected into the page header. -/
  cssBlocks : Array String := #[]
  /-- Map from project-root-relative source path to output filename in {lit}`images/`. -/
  imageFiles : Std.HashMap String String := {}
  /-- Set of already-used output filenames for dedup. -/
  imageOutputNames : Std.HashSet String := {}
deriving Inhabited

/-- The Slides genre for `reveal.js` presentations -/
@[expose]
public def Slides : Verso.Doc.Genre where
  PartMetadata := SlideMetadata
  Block := BlockExt
  Inline := InlineExt
  TraverseContext := Unit
  TraverseState := TraverseState

-- Type alias instances
public instance : Repr Slides.PartMetadata := inferInstanceAs (Repr SlideMetadata)
public instance : Repr Slides.Block := inferInstanceAs (Repr BlockExt)
public instance : Repr Slides.Inline := inferInstanceAs (Repr InlineExt)
public instance : BEq Slides.PartMetadata := inferInstanceAs (BEq SlideMetadata)
public instance : BEq Slides.Block := inferInstanceAs (BEq BlockExt)
public instance : BEq Slides.Inline := inferInstanceAs (BEq InlineExt)
public instance : ToJson Slides.PartMetadata := inferInstanceAs (ToJson SlideMetadata)
public instance : ToJson Slides.Block := inferInstanceAs (ToJson BlockExt)
public instance : ToJson Slides.Inline := inferInstanceAs (ToJson InlineExt)
public instance : FromJson Slides.PartMetadata := inferInstanceAs (FromJson SlideMetadata)
public instance : FromJson Slides.Block := inferInstanceAs (FromJson BlockExt)
public instance : FromJson Slides.Inline := inferInstanceAs (FromJson InlineExt)

-- Trivial traversal instances
public instance : Verso.Doc.TraversePart Slides where
public instance : Verso.Doc.TraverseBlock Slides where

public abbrev TraverseM := ReaderT Unit (StateT TraverseState IO)

/-- Find an unused output filename, deduplicating with {lit}`-1`, {lit}`-2`, etc. if needed. -/
public def dedupName (base : String) (used : Std.HashSet String) : String :=
  if !used.contains base then base
  else
    let path : System.FilePath := ⟨base⟩
    let stem := path.fileStem.getD base
    let ext := path.extension.map (s!".{·}") |>.getD ""
    Id.run do
      let mut i := 1
      while used.contains s!"{stem}-{i}{ext}" do
        i := i + 1
      return s!"{stem}-{i}{ext}"

public instance : Verso.Doc.Traverse Slides TraverseM where
  part _ := pure none
  block _ := pure ()
  inline _ := pure ()
  genrePart _ _ := pure none
  genreBlock container _content := do
    match container with
    | .css content => modify fun st => { st with cssBlocks := st.cssBlocks.push content }; pure none
    | _ => pure none
  genreInline container _content := do
    match container with
    | .image (.projectRelative resolved) .. =>
      modify fun st =>
        if st.imageFiles.contains resolved then st
        else
          let base := System.FilePath.fileName ⟨resolved⟩ |>.getD resolved
          let outputName := dedupName base st.imageOutputNames
          { st with
            imageFiles := st.imageFiles.insert resolved outputName
            imageOutputNames := st.imageOutputNames.insert outputName }
      pure none
    | _ => pure none
