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
import Illuminate.Animation.Render

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

/-- Converts camelCase to kebab-case for {lit}`reveal.js` class names. -/
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


/-- Conditionally wraps a code block in the interactive info panel layout. -/
private def wrapWithPanel (codeHtml : Html) (panel : Bool) : Html :=
  if panel then
    {{ <div class="code-with-panel">
         {{codeHtml}}
         <div class="panel-divider"></div>
         <div class="panel-cell">
           <div class="info-panel"></div>
         </div>
       </div> }}
  else codeHtml

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
    | .slideCode scExport panel =>
      let sc := scFromExport! scExport
      let codeHtml ← pure {{ <code class="hl lean block"> {{ ← sc.toHtml (g := Slides) }} </code> }}
      pure (wrapWithPanel codeHtml panel)
    | .leanCode hlExport panel =>
      let hl := (hlFromExport! hlExport).trim
      let codeHtml ← match fragmentize hl with
        | .error _msg => hl.blockHtml (g := Slides) "lean"
        | .ok sc => pure {{ <code class="hl lean block"> {{ ← sc.toHtml (g := Slides) }} </code> }}
      pure (wrapWithPanel codeHtml panel)
    | .otherLanguage language code =>
      pure {{ <pre><code class=s!"language-{language}">{{code}}</code></pre> }}
    | .table columns style =>
      let #[.ul items] := contents | pure .empty
      -- Re-chunk the flat cell list back into rows
      let mut flatItems := items
      let mut rows : Array (Array (Array (Block Slides))) := #[]
      while flatItems.size > 0 do
        rows := rows.push (flatItems.take columns |>.map (·.contents))
        flatItems := flatItems.extract columns flatItems.size
      -- Build CSS class string from style flags
      let flagClasses : List String :=
        (if style.stripedRows then ["striped-rows"] else []) ++
        (if style.stripedCols then ["striped-cols"] else []) ++
        (if style.rowSeps     then ["row-seps"]     else []) ++
        (if style.colSeps     then ["col-seps"]     else []) ++
        (if style.headerSep   then ["header-sep"]   else []) ++
        (if style.border      then ["with-border"]  else [])
      let classes := " ".intercalate (["slide-table"] ++ flagClasses)
      -- cellGap overrides --slide-table-cell-padding via an inline CSS variable
      let tableAttrs : Array (String × String) :=
        match style.cellGap with
        | none     => #[("class", classes)]
        | some gap => #[("class", classes), ("style", s!"--slide-table-cell-padding: {gap}")]
      let headerRow := if style.colHeaders && rows.size > 0 then some rows[0]! else none
      let bodyRows  := if style.colHeaders && rows.size > 0 then rows.extract 1 rows.size else rows
      let mkCell (isColHdr : Bool) (colIdx : Nat) (cellBlocks : Array (Block Slides)) :
          HtmlT Slides m Html := do
        let inner : Html := .seq (← cellBlocks.mapM blockHtml)
        if isColHdr then
          pure {{ <th scope="col">{{inner}}</th> }}
        else if style.rowHeaders && colIdx == 0 then
          pure {{ <th scope="row">{{inner}}</th> }}
        else
          pure {{ <td>{{inner}}</td> }}
      let theadHtml : Html ← match headerRow with
        | none     => pure .empty
        | some row =>
          let cells := .seq (← row.mapIdxM (mkCell true ·))
          pure {{ <thead><tr>{{cells}}</tr></thead> }}
      let tbodyHtml : Html ← do
        let trs ← bodyRows.mapM fun row => do
          let cells := .seq (← row.mapIdxM (mkCell false ·))
          pure {{ <tr>{{cells}}</tr> }}
        pure {{ <tbody>{{.seq trs}}</tbody> }}
      pure (.tag "table" tableAttrs (.seq #[theadHtml, tbodyHtml]))
    | .css _ =>
      pure .empty
    | .diagram svgStr cssWidth background =>
      let bgStyle := match background with
        | some bg => s!"; background: {bg}; padding: 1em; border-radius: 0.5em"
        | none => ""
      let style := s!"width: {cssWidth}{bgStyle}"
      pure {{
        <div class="diagram" style={{style}}>
          {{Html.text false svgStr}}
        </div>
      }}
    | .animate containerId animDataJson cssWidth background fragmentIndices autoplay =>
      let bgStyle := match background with
        | some bg => s!"; background: {bg}; padding: 1em; border-radius: 0.5em"
        | none => ""
      let style := s!"width: {cssWidth}{bgStyle}"
      -- Emit hidden fragment spans for each pause step so Reveal sees them at init time.
      -- The JS finds these by data-illuminate-container instead of creating them dynamically.
      let fragSpans : Array Html := fragmentIndices.mapIdx fun i idx =>
        let baseAttrs : Array (String × String) :=
          #[("class", "fragment"),
            ("style", "display:none"),
            ("data-illuminate-container", containerId),
            ("data-illuminate-step-index", toString i)]
        let attrs := match idx with
          | some n => baseAttrs.push ("data-fragment-index", toString n)
          | none => baseAttrs
        .tag "span" attrs .empty
      let autoplayAttr := if autoplay then "true" else "false"
      pure {{
        <div class="illuminate-anim" id={{containerId}} style={{style}}
             data-illuminate-autoplay={{autoplayAttr}}>
        </div>
        {{fragSpans}}
        <script type="application/json" data-illuminate-anim={{containerId}}>
          {{Html.text false animDataJson}}
        </script>
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
    | .image imgSrcVal alt width height cssClass =>
      let imgSrc ← match imgSrcVal with
        | .projectRelative resolved => do
          let st ← HtmlT.state
          match st.imageFiles[resolved]? with
          | some outputName => pure s!"images/{outputName}"
          | none =>
            HtmlT.logError s!"internal error: image '{resolved}' was not collected during traversal"
            pure resolved
        | .remote url => pure url
      let mut attrs := #[("src", imgSrc), ("alt", alt)]
      let styleW := width.map (fun w => s!"width: {w};")
      let styleH := height.map (fun h => s!"height: {h};")
      let style := " ".intercalate ([styleW, styleH].filterMap id)
      if !style.isEmpty then attrs := attrs.push ("style", style)
      let explicitSize := width.isSome || height.isSome
      let classVal := match (explicitSize, cssClass) with
        | (true,  some c) => some s!"explicit-size {c}"
        | (true,  none)   => some "explicit-size"
        | (false, some c) => some c
        | (false, none)   => none
      if let some c := classVal then attrs := attrs.push ("class", c)
      pure (.tag "img" attrs .empty)
    | .slideCode scExport =>
      let sc := scFromExport! scExport
      pure {{ <code class="hl lean inline"> {{ ← sc.toHtml (g := Slides) }} </code> }}
    | .leanCode hlExport =>
      let hl := (hlFromExport! hlExport).trim
      match fragmentize hl with
      | .error _msg => hl.inlineHtml (g := Slides) (some "lean")
      | .ok sc => pure {{ <code class="hl lean inline"> {{ ← sc.toHtml (g := Slides) }} </code> }}
    | .name hlExport =>
      let hl := (hlFromExport! hlExport).trim
      hl.inlineHtml (g := Slides) (some "lean")


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


/-- Generates the complete {lit}`reveal.js` HTML document. -/
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
private def slideCodePanelCss : String := include_str "../web-lib/panel/panel.css"

/-- JS for the pretty-printer (reflowable format rendering). -/
private def prettyJs : String := include_str "../web-lib/panel/pretty.js"

/-- JS for the interactive info panel. -/
private def slideCodePanelJs : String := include_str "../web-lib/panel/panel.js"

/-- Wraps the global {lit}`tippy` function to skip elements inside {lit}`.code-with-panel`.
    Must be injected after the Tippy library but before {name}`highlightingJs`. -/
private def tippyPanelFilterJs : String := include_str "../web-lib/panel/tippy-panel-filter.js"

/-- CSS for the inline Lean term lightbox overlay. -/
private def lightboxCss : String := include_str "../web-lib/panel/lightbox.css"

/-- JS for the inline Lean term lightbox overlay. -/
private def lightboxJs : String := include_str "../web-lib/panel/lightbox.js"

/-- CSS for Illuminate diagrams. -/
private def diagramCss : String := include_str "../web-lib/diagrams/diagram.css"

/-- CSS for Illuminate animation containers. -/
private def illuminateAnimCss : String := include_str "../web-lib/animate/illuminate-anim.css"

/-- JS for Illuminate {lit}`reveal.js` animation integration.
    Combines the shared {lit}`anim_core.js` helpers with the multi-animation init script. -/
private def illuminateRevealJs : String :=
  Illuminate.animCoreJs ++ "\n" ++ include_str "../web-lib/animate/illuminate-reveal-init.js"

/-- CSS for the {lit}`:::table` directive. -/
private def tableCss : String := include_str "../web-lib/table/table.css"

/-- CSS overrides for Verso highlighted code within {lit}`reveal.js` slides. -/
private def slidesHighlightCss : String := include_str "../web-lib/panel/slides-highlight.css"

/--
JS that adapts code block styling based on the computed background luminance of each slide. Sets
{lit}`.slide-light-bg` on light sections (toggles CSS variable palette) and applies appropriate code
block / panel background overlays.
-/
-- TODO(verso#274): remove leanCommentsJs, its <script> tag in renderFullHtml,
-- its writeFileWithDirs call in writeVendoredAssets, and the .lean-comment CSS
-- rules in slides-highlight.css when SubVerso tokenizes comments natively.
private def leanCommentsJs : String := include_str "../web-lib/panel/lean-comments.js"

private def codeBlockBgJs : String := include_str "../web-lib/panel/code-block-bg.js"

/--
JS that renders Verso's {lit}`.math.inline` / {lit}`.math.display` elements with KaTeX.
{lit}`reveal.js`'s KaTeX plugin uses auto-render, which skips {lit}`<code>` tags — so these
Verso-emitted elements go unrendered without this script.
-/
private def mathJs : String := include_str "../web-lib/math/math.js"

/-- Relative path prefix for vendored libraries in the output directory. -/
private def libPrefix : String := "lib"

/--
Encode a string as a JavaScript double-quoted string literal safe to embed in
an HTML {lit}`<script>` element. Escapes the usual JS metacharacters, plus
{lit}`<` / {lit}`>` / {lit}`&` (so a payload containing {lit}`</script>` can't
break out of the tag) and the line-separator codepoints U+2028 / U+2029 (which
terminate string literals in older JS engines).
-/
private def jsString (s : String) : String := Id.run do
  let mut out := "\""
  for c in s.toList do
    out :=
      out ++
      match c with
      | '\\' => "\\\\"
      | '"'  => "\\\""
      | '\n' => "\\n"
      | '\r' => "\\r"
      | '\t' => "\\t"
      | '\x08' => "\\b"
      | '\x0c' => "\\f"
      | '<' => "\\x3C"
      | '>' => "\\x3E"
      | '&' => "\\x26"
      | '\u2028' => "\\u2028"
      | '\u2029' => "\\u2029"
      | c =>
        if c.val < 0x20 then
          let hex := String.ofList (Nat.toDigits 16 c.val.toNat)
          if hex.length = 1 then s!"\\u000{hex}" else s!"\\u00{hex}"
        else c.toString
  return out ++ "\""

/-- Renders the full standalone HTML page. -/
def renderFullHtml (config : Config) (title : String) (slidesBody : Html) (customCss : Array String := #[]) : Html :=
  let extraCssLinks := config.extraCss.map fun css =>
    {{ <link rel="stylesheet" href={{css.filename}} /> }}
  let extraJsScripts := config.extraJs.map fun url =>
    {{ <script src={{url}}></script> }}
  let mathPreludeScripts : Array Html :=
    if config.mathPrelude.isEmpty then #[]
    else
      let js := s!"window.__versoMathPrelude = {jsString config.mathPrelude};"
      #[{{ <script>{{Html.text false js}}</script> }}]
  let themeHref := match config.theme with
    | .builtin name => s!"{libPrefix}/reveal.js/dist/theme/{name}.css"
    | .custom theme => theme.stylesheet.filename
  let revealBase := s!"{libPrefix}/reveal.js"
  let autoSlideMethodJs : String :=
    match config.autoSlideMethod with
    | .next     => "null"
    | .right    => "() => Reveal.right()"
    | .down     => "() => Reveal.down()"
    | .js code  => code
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
        autoSlide: {config.autoSlide},
        autoSlideStoppable: {jsBool config.autoSlideStoppable},
        autoSlideMethod: {autoSlideMethodJs},
        plugins: [ RevealNotes, RevealHighlight ]
      });
    "
  {{ <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>{{title}}</title>
      <link rel="stylesheet" href={{s!"{revealBase}/dist/reset.css"}} />
      <link rel="stylesheet" href={{s!"{revealBase}/dist/reveal.css"}} />
      <link rel="stylesheet" href={{themeHref}} />
      <link rel="stylesheet" href={{s!"{revealBase}/plugin/highlight/monokai.css"}} />
      {{extraCssLinks}}
      <link rel="stylesheet" href={{s!"{libPrefix}/highlighting.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/tippy-border.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/slides-highlight.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/panel.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/lightbox.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/diagram.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/illuminate-anim.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/table.css"}} />
      <link rel="stylesheet" href={{s!"{libPrefix}/katex/dist/katex.min.css"}} />
      {{ customCss.map fun css => {{ <style>{{Html.text false css}}</style> }} }}
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
      <script src={{s!"{libPrefix}/katex/dist/katex.min.js"}}></script>
      {{mathPreludeScripts}}
      <script src={{s!"{libPrefix}/math.js"}}></script>
      {{extraJsScripts}}
      <script>{{Html.text false initScript}}</script>
      <script src={{s!"{libPrefix}/marked.min.js"}}></script>
      <script src={{s!"{libPrefix}/popper.js"}}></script>
      <script src={{s!"{libPrefix}/tippy.js"}}></script>
      <script src={{s!"{libPrefix}/tippy-panel-filter.js"}}></script>
      <script src={{s!"{libPrefix}/highlighting.js"}}></script>
      <!-- TODO(verso#274): remove lean-comments.js when SubVerso tokenizes comments -->
      <script src={{s!"{libPrefix}/lean-comments.js"}}></script>
      <script src={{s!"{libPrefix}/code-block-bg.js"}}></script>
      <script src={{s!"{libPrefix}/pretty.js"}}></script>
      <script src={{s!"{libPrefix}/panel.js"}}></script>
      <script src={{s!"{libPrefix}/lightbox.js"}}></script>
      <script src={{s!"{libPrefix}/illuminate-reveal.js"}}></script>
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
def writeVendoredAssets (outputDir : System.FilePath) (theme : Theme) : IO Unit := do
  let libDir := outputDir / libPrefix
  let revealDir := libDir / "reveal.js"
  -- Reveal.js core
  writeFileWithDirs (revealDir / "dist" / "reset.css") Vendor.resetCss
  writeFileWithDirs (revealDir / "dist" / "reveal.css") Vendor.revealCss
  writeFileWithDirs (revealDir / "dist" / "reveal.js") Vendor.revealJs
  -- Selected theme: write the vendored stylesheet (with Google-Fonts `@import` lines rewritten to
  -- local equivalents) and the font files it references, so slides render correctly without network
  -- access. Custom themes are written separately alongside index.html.
  if let .builtin name := theme then
    let themeCss := Vendor.themeCSS name |>.getD Vendor.themeBlack
    let themeDir := revealDir / "dist" / "theme"
    writeFileWithDirs (themeDir / s!"{name}.css") (Vendor.rewriteGoogleFontImports themeCss)
    for (relPath, data) in Vendor.themeFonts name do
      writeBinFileWithDirs (themeDir / relPath) data
  -- Plugins
  writeFileWithDirs (revealDir / "plugin" / "notes" / "notes.js") Vendor.notesJs
  writeFileWithDirs (revealDir / "plugin" / "highlight" / "highlight.js") Vendor.highlightJs
  writeFileWithDirs (revealDir / "plugin" / "highlight" / "monokai.css") Vendor.monokaiCss
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
  writeFileWithDirs (libDir / "lean-comments.js") leanCommentsJs  -- TODO: remove when verso#274 is fixed
  writeFileWithDirs (libDir / "code-block-bg.js") codeBlockBgJs
  writeFileWithDirs (libDir / "pretty.js") prettyJs
  writeFileWithDirs (libDir / "panel.js") slideCodePanelJs
  writeFileWithDirs (libDir / "lightbox.css") lightboxCss
  writeFileWithDirs (libDir / "lightbox.js") lightboxJs
  writeFileWithDirs (libDir / "diagram.css") diagramCss
  writeFileWithDirs (libDir / "illuminate-anim.css") illuminateAnimCss
  writeFileWithDirs (libDir / "illuminate-reveal.js") illuminateRevealJs
  writeFileWithDirs (libDir / "table.css") tableCss
  writeFileWithDirs (libDir / "math.js") mathJs

/--
An entry in the asset plan assembled from a {name}`Config`, keyed by the
output filename relative to the slideshow output directory.

Entries tagged {lit}`.text` come from a {name}`CssFile` (custom theme
stylesheet or an {lit}`extraCss` entry). Entries tagged {lit}`.binary` come
from a {name}`ThemeAsset`. The distinction matters because two payloads at
the same filename are only compatible if they share both tag and contents.
-/
private inductive AssetPayload
  | text (body : String)
  | binary (bytes : ByteArray)

private def AssetPayload.equal : AssetPayload → AssetPayload → Bool
  | .text a, .text b => a == b
  | .binary a, .binary b => a == b
  | _, _ => false

private def AssetPayload.kind : AssetPayload → String
  | .text _ => "text"
  | .binary _ => "binary"

/--
Records a file entry at {lit}`filename`, treating it as already-present
when the previous entry at the same filename has identical contents (so
the same asset included twice — e.g. a font shared between overlapping
{lit}`include_bin_dir` bundles — is accepted and written only once).
Raises {name}`IO.userError` when the contents diverge, naming both
sources and their content kinds.
-/
private def recordAsset (seen : Std.HashMap String (String × AssetPayload))
    (filename source : String) (payload : AssetPayload) :
    IO (Std.HashMap String (String × AssetPayload)) := do
  match seen.get? filename with
  | none => return seen.insert filename (source, payload)
  | some (prevSource, prev) =>
    if prev.equal payload then
      return seen
    else
      throw <| IO.userError
        s!"Filename collision in config: \"{filename}\" is claimed by {prevSource} ({prev.kind}) and {source} ({payload.kind}) with different contents."

/--
Builds the deduplicated asset plan for a {name}`Config`: the custom
theme's stylesheet (if any), every bundled theme asset, and every
{lit}`extraCss` entry. When two entries share a filename their contents
must match; otherwise {name}`IO.userError` is raised.

Returns the map of filenames to (source, payload) pairs so
{lit}`slidesMain` can write each file exactly once without
re-deduplicating.
-/
def Config.collectAssets (config : Config) :
    IO (Std.HashMap String (String × AssetPayload)) := do
  let mut seen : Std.HashMap String (String × AssetPayload) := {}
  if let .custom theme := config.theme then
    seen ← recordAsset seen theme.stylesheet.filename
      "theme stylesheet" (.text theme.stylesheet.contents.css)
    for asset in theme.assets do
      seen ← recordAsset seen asset.filename
        "theme asset" (.binary asset.contents)
  for css in config.extraCss do
    seen ← recordAsset seen css.filename
      "extraCss" (.text css.contents.css)
  return seen

/--
Checks that every filename supplied through {lit}`Config.theme` (when
{lit}`.custom`), its bundled assets, and {lit}`extraCss` either is unique
or is repeated with identical contents. Raises {name}`IO.userError` on
divergent-contents clashes; duplicates with identical contents are
silently deduplicated.
-/
def Config.validateFilenames (config : Config) : IO Unit := do
  let _ ← config.collectAssets

/-- Generates a {lit}`reveal.js` slide presentation from a Verso document. -/
def slidesMain (config : Config := {}) (doc : Part Slides) : IO UInt32 := do
  -- Validate the config and build the deduplicated asset plan up-front so
  -- any filename collision fails before we start writing files.
  let assetPlan ← config.collectAssets
  let hasError ← IO.mkRef false
  let logError (msg : String) : IO Unit := do hasError.set true; IO.eprintln msg

  -- Run the traversal pass (collects CSS blocks, etc.)
  let (doc, traverseState) ← (Slides.traverse doc : TraverseM (Part Slides)) () {}

  -- Set up HtmlT context
  let ctx : HtmlT.Context Slides IO := {
    options := { logError := logError }
    traverseContext := ()
    traverseState := traverseState
    definitionIds := {}
    linkTargets := {}
    codeOptions := {}
  }

  -- Generate slide HTML
  let (slidesHtml, hoverState) ← (renderDocument config doc).run ctx |>.run {}

  -- Produce full HTML document
  let title := inlinesToPlainText doc.title
  let fullHtml := renderFullHtml config title slidesHtml traverseState.cssBlocks

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

  -- Write the user-supplied custom-theme stylesheet, theme assets, and
  -- extraCss entries. The plan has already been deduplicated by filename
  -- (with matching-content duplicates collapsed into a single write).
  for (filename, _source, payload) in assetPlan.toList do
    match payload with
    | .text body => writeFileWithDirs (dir / filename) body
    | .binary bytes => writeBinFileWithDirs (dir / filename) bytes

  -- Copy local images to the output directory
  if !traverseState.imageFiles.isEmpty then
    let imagesDir := dir / "images"
    IO.FS.createDirAll imagesDir
    for (resolved, outputName) in traverseState.imageFiles.toList do
      let contents ← IO.FS.readBinFile resolved
      writeBinFileWithDirs (imagesDir / outputName) contents

  IO.println s!"Slides written to {indexPath}"

  if ← hasError.get then
    IO.eprintln "Errors were encountered!"
    return 1
  return 0

end VersoSlides
