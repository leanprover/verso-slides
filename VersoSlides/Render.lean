/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides.Basic
import VersoSlides.Attributes
import VersoSlides.SlideCode.Render
import VersoSlides.SlideCode.Export
import VersoSlidesVendored
import Verso.Doc.Html
import Verso.Output.Html
import Verso.Code.Highlighted
import Verso.Code.Highlighted.WebAssets

set_option doc.verso true

open Verso Doc Output Html
open Verso.Doc.Html (HtmlT GenreHtml ToHtml mkPartHeader)
open SubVerso.Highlighting (Highlighted hlFromExport!)
open Verso.Code (HighlightHtmlM highlightingStyle highlightingJs)

/-
HTML generation for {lit}`reveal.js` slides
-/

namespace VersoSlides

/-- Pushes a CSS class onto all top-level HTML tags in a fragment. -/
partial def addClassToHtml (cls : String) : Html → Html
  | .tag name attrs children =>
    let attrs :=
      if let some i := attrs.findFinIdx? (·.1 == "class") then
        attrs.set i ("class", attrs[i].2 ++ " " ++ cls)
      else
        attrs.push ("class", cls)
    .tag name attrs children
  | .seq elts => .seq (elts.map (addClassToHtml cls))
  | other => other

/--
Pushes a single attribute onto an HTML tag, appending for {lit}`class`, replacing otherwise.
-/
private def pushOneAttr (attrs : Array (String × String)) (k v : String) : Array (String × String) :=
  if let some i := attrs.findFinIdx? (·.1 == k) then
    if k == "class" then
      attrs.set i (k, attrs[i].2 ++ " " ++ v)
    else
      attrs.set i (k, v)
  else
    attrs.push (k, v)

/-- Pushes arbitrary attributes onto all top-level HTML tags in a fragment. -/
partial def pushAttrsOntoHtml (newAttrs : Array (String × String)) : Html → Html
  | .tag name attrs children =>
    let attrs := newAttrs.foldl (fun acc (k, v) => pushOneAttr acc k v) attrs
    .tag name attrs children
  | .seq elts => .seq (elts.map (pushAttrsOntoHtml newAttrs))
  | other => other

/-- Converts camelCase to kebab-case for reveal.js class names. -/
def camelToKebab (s : String) : String := Id.run do
  let mut result := ""
  for c in s.toList do
    if c.isUpper then
      if !result.isEmpty then
        result := result.push '-'
      result := result.push c.toLower
    else
      result := result.push c
  result

/-- Builds the fragment CSS class string from style name. -/
def fragmentClass (style : Option String) : String :=
  match style with
  | none => "fragment"
  | some s => "fragment " ++ camelToKebab s


instance [Monad m] : GenreHtml Slides m where
  part partHtml _metadata contents := partHtml contents
  block _inlineHtml blockHtml container contents := do
    match container with
    | .notes =>
      let inner ← contents.mapM blockHtml
      pure {{ <aside class="notes"> {{inner}} </aside> }}
    | .fragment style index =>
      -- Push-down: push fragment class onto the single child block
      let inner ← contents.mapM blockHtml
      let cls := fragmentClass style
      let html := addClassToHtml cls (.seq inner)
      match index with
      | some i => pure (pushAttrsOntoHtml #[("data-fragment-index", toString i)] html)
      | none => pure html
    | .attr attrs =>
      -- Push-down: push arbitrary attributes onto the single child block
      let inner ← contents.mapM blockHtml
      pure (pushAttrsOntoHtml attrs (.seq inner))
    | .wrap attrs =>
      let inner ← contents.mapM blockHtml
      pure (.tag "div" attrs (.seq inner))
    | .slideCode scExport =>
      let sc := scFromExport! scExport
      let codeHtml ← pure {{ <code class="hl lean block"> {{ ← sc.toHtml (g := Slides) }} </code> }}
      pure {{
        <div class="code-with-panel">
          {{codeHtml}}
          <div class="panel-divider"></div>
          <div class="panel-cell">
            <div class="info-panel"></div>
          </div>
        </div>
      }}
    | .leanCode hlExport =>
      let hl := (hlFromExport! hlExport).trim
      let codeHtml ← match fragmentize hl with
        | .error _msg => hl.blockHtml (g := Slides) "lean"
        | .ok sc => pure {{ <code class="hl lean block"> {{ ← sc.toHtml (g := Slides) }} </code> }}
      pure {{
        <div class="code-with-panel">
          {{codeHtml}}
          <div class="panel-divider"></div>
          <div class="panel-cell">
            <div class="info-panel"></div>
          </div>
        </div>
      }}
  inline inlineHtml container contents := do
    match container with
    | .fragment style index =>
      let inner ← contents.mapM inlineHtml
      let cls := fragmentClass style
      let mut attrs : Array (String × String) := #[("class", cls)]
      if let some i := index then
        attrs := attrs.push ("data-fragment-index", toString i)
      pure (.tag "span" attrs (.seq inner))
    | .styled attrs =>
      let inner ← contents.mapM inlineHtml
      pure (.tag "span" attrs (.seq inner))
    | .slideCode scExport =>
      let sc := scFromExport! scExport
      pure {{ <code class="hl lean inline"> {{ ← sc.toHtml (g := Slides) }} </code> }}
    | .leanCode hlExport =>
      let hl := (hlFromExport! hlExport).trim
      match fragmentize hl with
      | .error _msg => hl.inlineHtml (g := Slides) (some "lean")
      | .ok sc => pure {{ <code class="hl lean inline"> {{ ← sc.toHtml (g := Slides) }} </code> }}


section
variable [Monad m] [GenreHtml Slides m]

/-- Renders inline content to HTML. -/
private def inlToHtml (i : Inline Slides) : HtmlT Slides m Html :=
  ToHtml.toHtml i

/-- Renders block content to HTML. -/
private def blkToHtml (b : Block Slides) : HtmlT Slides m Html :=
  ToHtml.toHtml b

/-- Renders an array of inlines as a heading at the given level. -/
private def renderHeading (level : Nat) (title : Array (Inline Slides)) : HtmlT Slides m Html := do
  let titleHtml ← title.mapM inlToHtml
  pure (.tag s!"h{level}" #[] (.seq titleHtml))

/-- Returns {name}`true` if a {name}`Part` has any non-empty direct content blocks. -/
private def hasDirectContent (p : Part Slides) : Bool :=
  p.content.any (!·.isEmpty)

/--
Custom {name}`Part` rendering for slides. Bypasses the standard HTML generator in order to control
which parts get {lit}`<section>` wrappers and which are flattened.
-/
partial def renderSlidePart (config : Config) (level : Nat) (parentVertical : Bool)
    (p : Part Slides) : HtmlT Slides m Html := do
  let isVertical := p.metadata.bind (·.vertical) |>.getD config.vertical
  let attrs := sectionAttrs p.metadata
  let heading ← renderHeading (level + 2) p.title
  let contentHtml ← p.content.mapM blkToHtml

  if level == 0 then
    -- Top-level `#` section: always a horizontal slide (<section>)
    if isVertical && p.subParts.size > 0 then
      -- Vertical slide group: wrap in outer <section>, each sub-part is a vertical sub-slide
      let mut slides := #[]
      -- If there's direct content, create implicit first vertical sub-slide
      if hasDirectContent p then
        slides := slides.push (.tag "section" #[] (.seq (#[heading] ++ contentHtml)))
      -- Render each ## sub-part as a vertical sub-slide
      for sub in p.subParts do
        slides := slides.push (← renderSlidePart config 1 true sub)
      pure (.tag "section" attrs (.seq slides))
    else
      -- Single horizontal slide (no vertical sub-slides)
      let subContent ← p.subParts.mapM (renderSlidePart config 1 false)
      pure (.tag "section" attrs (.seq (#[heading] ++ contentHtml ++ subContent)))
  else if level == 1 && parentVertical then
    -- `##` section under vertical parent: emit as vertical sub-slide (<section>)
    let subContent ← p.subParts.mapM (renderSlidePart config 2 false)
    pure (.tag "section" attrs (.seq (#[heading] ++ contentHtml ++ subContent)))
  else
    -- `##` under non-vertical parent, or `###` and deeper: flatten (no <section> wrapper)
    let subContent ← p.subParts.mapM (renderSlidePart config (level + 1) false)
    pure (.seq (#[heading] ++ contentHtml ++ subContent))

end


/-- Extracts plain text from an inline element. -/
partial def Inline.toPlainText : Inline Slides → String
  | .text s | .code s | .linebreak s => s
  | .math _ s => s
  | .image alt _ => alt
  | .emph content | .bold content | .link content _
  | .footnote _ content | .concat content | .other _ content =>
    content.foldl (· ++ Inline.toPlainText ·) ""

/-- Extracts plain text from an array of inlines. -/
def inlinesToPlainText (inlines : Array (Inline Slides)) : String :=
  inlines.foldl (· ++ Inline.toPlainText ·) ""


/-- Generates the complete reveal.js HTML document. -/
def renderDocument (config : Config) (doc : Part Slides) [Monad m] [GenreHtml Slides m] :
    HtmlT Slides m Html := do
  -- Render all top-level sections as slides
  let slides ← doc.subParts.mapM (renderSlidePart config 0 false)
  -- Also render any direct content of the top-level part (before first #)
  let preambleContent ← doc.content.mapM blkToHtml

  let slidesHtml := Html.seq (preambleContent ++ slides)
  pure slidesHtml

/-- Converts a {name}`Bool` to a JavaScript boolean string. -/
private def jsBool (b : Bool) : String := if b then "true" else "false"

/-- CSS for the interactive info panel layout. -/
private def slideCodePanelCss : String := include_str "../panel/panel.css"

/-- JS for the pretty-printer (reflowable format rendering). -/
private def prettyJs : String := include_str "../panel/pretty.js"

/-- JS for the interactive info panel. -/
private def slideCodePanelJs : String := include_str "../panel/panel.js"

/-- Wraps the global {lit}`tippy` function to skip elements inside {lit}`.code-with-panel`.
    Must be injected after the Tippy library but before {name}`highlightingJs`. -/
private def tippyPanelFilterJs : String := include_str "../panel/tippy-panel-filter.js"

/-- CSS for the inline Lean term lightbox overlay. -/
private def lightboxCss : String := include_str "../panel/lightbox.css"

/-- JS for the inline Lean term lightbox overlay. -/
private def lightboxJs : String := include_str "../panel/lightbox.js"

/-- CSS overrides for Verso highlighted code within reveal.js slides. -/
private def slidesHighlightCss : String := include_str "../panel/slides-highlight.css"

/--
JS that adapts code block styling based on the computed background luminance of each slide. Sets
{lit}`.slide-light-bg` on light sections (toggles CSS variable palette) and applies appropriate code
block / panel background overlays.
-/
private def codeBlockBgJs : String := include_str "../panel/code-block-bg.js"

/-- Relative path prefix for vendored libraries in the output directory. -/
private def libPrefix : String := "lib"

/-- Renders the full standalone HTML page. -/
def renderFullHtml (config : Config) (title : String) (slidesBody : Html) : Html :=
  let extraCssLinks := config.extraCss.map fun url =>
    {{ <link rel="stylesheet" href={{url}} /> }}
  let extraJsScripts := config.extraJs.map fun url =>
    {{ <script src={{url}}></script> }}
  let revealBase := s!"{libPrefix}/reveal.js"
  let initScript := s!"
      Reveal.initialize(\{
        hash: {jsBool config.hash},
        controls: {jsBool config.controls},
        progress: {jsBool config.progress},
        slideNumber: {jsBool config.slideNumber},
        center: {jsBool config.center},
        transition: '{config.transition}',
        width: {config.width},
        height: {config.height},
        margin: {config.margin},
        navigationMode: '{config.navigationMode}',
        math: \{ local: '{libPrefix}/katex' },
        plugins: [ RevealNotes, RevealHighlight, RevealMath.KaTeX ]
      });
    "
  {{ <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>{{title}}</title>
      <link rel="stylesheet" href={{s!"{revealBase}/dist/reset.css"}} />
      <link rel="stylesheet" href={{s!"{revealBase}/dist/reveal.css"}} />
      <link rel="stylesheet" href={{s!"{revealBase}/dist/theme/{config.theme}.css"}} />
      <link rel="stylesheet" href={{s!"{revealBase}/plugin/highlight/monokai.css"}} />
      {{extraCssLinks}}
      <link rel="stylesheet" href={{s!"{libPrefix}/highlighting.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/tippy-border.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/slides-highlight.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/panel.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/lightbox.css"}} />
    </head>
    <body>
      <div class="reveal">
        <div class="slides">
          {{slidesBody}}
        </div>
      </div>
      <script src={{s!"{revealBase}/dist/reveal.js"}}></script>
      <script src={{s!"{revealBase}/plugin/notes/notes.js"}}></script>
      <script src={{s!"{revealBase}/plugin/highlight/highlight.js"}}></script>
      <script src={{s!"{revealBase}/plugin/math/math.js"}}></script>
      {{extraJsScripts}}
      <script>{{Html.text false initScript}}</script>
      <script src={{s!"{libPrefix}/marked.min.js"}}></script>
      <script src={{s!"{libPrefix}/popper.js"}}></script>
      <script src={{s!"{libPrefix}/tippy.js"}}></script>
      <script src={{s!"{libPrefix}/tippy-panel-filter.js"}}></script>
      <script src={{s!"{libPrefix}/highlighting.js"}}></script>
      <script src={{s!"{libPrefix}/code-block-bg.js"}}></script>
      <script src={{s!"{libPrefix}/pretty.js"}}></script>
      <script src={{s!"{libPrefix}/panel.js"}}></script>
      <script src={{s!"{libPrefix}/lightbox.js"}}></script>
    </body>
  </html> }}


/-- Writes a file, creating parent directories as needed. -/
private def writeFileWithDirs (path : System.FilePath) (content : String) : IO Unit := do
  let dir := path.parent.getD "."
  if !(← dir.pathExists) then IO.FS.createDirAll dir
  IO.FS.writeFile path content

/-- Writes a binary file, creating parent directories as needed. -/
private def writeBinFileWithDirs (path : System.FilePath) (content : ByteArray) : IO Unit := do
  let dir := path.parent.getD "."
  if !(← dir.pathExists) then IO.FS.createDirAll dir
  IO.FS.writeBinFile path content

/-- Writes all vendored library assets to the output directory. -/
def writeVendoredAssets (outputDir : System.FilePath) (theme : String) : IO Unit := do
  let libDir := outputDir / libPrefix
  let revealDir := libDir / "reveal.js"
  -- Reveal.js core
  writeFileWithDirs (revealDir / "dist" / "reset.css") Vendor.resetCss
  writeFileWithDirs (revealDir / "dist" / "reveal.css") Vendor.revealCss
  writeFileWithDirs (revealDir / "dist" / "reveal.js") Vendor.revealJs
  -- Selected theme
  let themeCss := Vendor.themeCSS theme |>.getD Vendor.themeBlack
  writeFileWithDirs (revealDir / "dist" / "theme" / s!"{theme}.css") themeCss
  -- Plugins
  writeFileWithDirs (revealDir / "plugin" / "notes" / "notes.js") Vendor.notesJs
  writeFileWithDirs (revealDir / "plugin" / "highlight" / "highlight.js") Vendor.highlightJs
  writeFileWithDirs (revealDir / "plugin" / "highlight" / "monokai.css") Vendor.monokaiCss
  writeFileWithDirs (revealDir / "plugin" / "math" / "math.js") Vendor.mathJs
  -- Marked
  writeFileWithDirs (libDir / "marked.min.js") Vendor.markedJs
  -- KaTeX
  let katexDist := libDir / "katex" / "dist"
  writeFileWithDirs (katexDist / "katex.min.css") Vendor.katexCss
  writeFileWithDirs (katexDist / "katex.min.js") Vendor.katexJs
  let fontsDir := katexDist / "fonts"
  if !(← fontsDir.pathExists) then IO.FS.createDirAll fontsDir
  for (name, data) in Vendor.katexFonts do
    let fileName := System.FilePath.fileName name |>.getD name
    IO.FS.writeBinFile (fontsDir / fileName) data
  -- Verso highlighting CSS/JS
  writeFileWithDirs (libDir / "highlighting.css") highlightingStyle
  writeFileWithDirs (libDir / "tippy-border.css") Verso.Code.Highlighted.WebAssets.tippy.border.css
  writeFileWithDirs (libDir / "popper.js") Verso.Code.Highlighted.WebAssets.popper
  writeFileWithDirs (libDir / "tippy.js") Verso.Code.Highlighted.WebAssets.tippy
  writeFileWithDirs (libDir / "highlighting.js") highlightingJs
  -- VersoSlides CSS/JS
  writeFileWithDirs (libDir / "slides-highlight.css") slidesHighlightCss
  writeFileWithDirs (libDir / "panel.css") slideCodePanelCss
  writeFileWithDirs (libDir / "tippy-panel-filter.js") tippyPanelFilterJs
  writeFileWithDirs (libDir / "code-block-bg.js") codeBlockBgJs
  writeFileWithDirs (libDir / "pretty.js") prettyJs
  writeFileWithDirs (libDir / "panel.js") slideCodePanelJs
  writeFileWithDirs (libDir / "lightbox.css") lightboxCss
  writeFileWithDirs (libDir / "lightbox.js") lightboxJs

/-- Generates a reveal.js slide presentation from a Verso document. -/
def slidesMain (config : Config := {}) (doc : Part Slides) (args : List String := []) : IO UInt32 := do
  let config ← parseArgs config args
  -- Override config from document-level metadata block
  let config := match doc.metadata with
    | some md => Config.fromMetadata md config
    | none => config
  let hasError ← IO.mkRef false
  let logError (msg : String) : IO Unit := do hasError.set true; IO.eprintln msg

  -- Run the trivial traversal pass
  let (doc, ()) ← (Slides.traverse doc : TraverseM (Part Slides)) () ()

  -- Set up HtmlT context
  let ctx : HtmlT.Context Slides IO := {
    options := { logError := logError }
    traverseContext := ()
    traverseState := ()
    definitionIds := {}
    linkTargets := {}
    codeOptions := {}
  }

  -- Generate slide HTML
  let (slidesHtml, hoverState) ← (renderDocument config doc).run ctx |>.run {}

  -- Produce full HTML document
  let title := inlinesToPlainText doc.title
  let fullHtml := renderFullHtml config title slidesHtml

  -- Write output
  let dir := config.outputDir
  if !(← dir.pathExists) then
    IO.FS.createDirAll dir
  let indexPath := dir / "index.html"
  IO.FS.writeFile indexPath ("<!doctype html>\n" ++ fullHtml.asString)

  -- Write hover data JSON for highlighted code tooltips
  let docsJsonPath := dir / "-verso-docs.json"
  IO.FS.writeFile docsJsonPath (toString hoverState.dedup.docJson)

  -- Write vendored library assets to the output directory
  writeVendoredAssets dir config.theme

  IO.println s!"Slides written to {indexPath}"

  if ← hasError.get then
    IO.eprintln "Errors were encountered!"
    return 1
  return 0
where
  parseArgs (cfg : Config) : List String → IO Config
    | "--output" :: path :: rest => parseArgs { cfg with outputDir := path } rest
    | "--theme" :: theme :: rest => parseArgs { cfg with theme := theme } rest
    | other :: _ => throw (IO.userError s!"Unknown option: {other}")
    | [] => pure cfg

end VersoSlides
