/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
import VersoSlides.Basic
public meta import VersoSlides.Basic
import VersoSlides.ImageWidget
public meta import VersoSlides.ImageWidget
public meta import VersoSlides.ImgSrc
import Verso.Doc.Elab
import Verso.Doc.ArgParse
public import Verso.Doc.Elab.Monad
public meta import Verso.Doc.Elab.Block
public meta import Verso.Doc.Elab.Inline

open Verso Doc Elab ArgParse
open Lean Elab Widget
open Lean.Doc.Syntax

register_option verso.slides.warnOnImage : Bool := {
  defValue := true
  descr := "if true, warn when Markdown image syntax ![alt](url) is used instead of the {image} role"
}

namespace VersoSlides

/-- Arguments for the `:::fragment` directive. -/
public structure FragmentArgs where
  style : Option Name := none
  index : Option Nat := none

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public meta instance : FromArgs FragmentArgs m where
  fromArgs :=
    FragmentArgs.mk <$>
      (some <$> .positional `style .name <|> pure none) <*>
      .named `index .nat true
end

/-- Arguments for the `{fragment}` inline role. -/
public meta structure InlineFragmentArgs where
  style : Option Name := none
  index : Option Nat := none

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public meta instance : FromArgs InlineFragmentArgs m where
  fromArgs :=
    InlineFragmentArgs.mk <$>
      .named `style .name true <*>
      .named `index .nat true
end

/-- Arguments for variadic class directives/roles: one or more positional string args. -/
public meta structure ClassArgs where
  classes : Array String

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public meta instance : FromArgs ClassArgs m where
  fromArgs :=
    ClassArgs.mk <$> (List.toArray <$> ArgParse.many (.positional `class .string))
end

/-- Arguments for the `:::id` directive / `{id}` role: single positional string arg. -/
public meta structure IdArgs where
  id : String

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public meta instance : FromArgs IdArgs m where
  fromArgs :=
    IdArgs.mk <$> .positional `id .string
end

/-- Arguments for the `:::attr` directive / `{attr}` role: variadic named key-value pairs. -/
public meta structure AttrArgs where
  attrs : Array (String × String)

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public meta instance : FromArgs AttrArgs m where
  fromArgs :=
    AttrArgs.mk <$> (List.toArray <$>
      ArgParse.many ((fun (k, v) => (k.getId.toString (escape := false), v)) <$>
        .anyNamed `attribute .string))
end


/-- Converts a Lean `Name` to a kebab-case fragment style string. -/
private meta def nameToStyle (n : Name) : String :=
  camelToKebab (n.toString (escape := false))
where
  camelToKebab (s : String) : String := Id.run do
    let mut result := ""
    for c in s.toList do
      if c.isUpper then
        if !result.isEmpty then
          result := result.push '-'
        result := result.push c.toLower
      else
        result := result.push c
    result


/--
Speaker notes directive. Wraps content in `<aside class="notes">`.

Usage:
```
:::notes
Remember to explain this point.
:::
```
-/
@[directive]
public meta def notes : DirectiveExpanderOf Unit
  | (), stxs => do
  let contents ← stxs.mapM elabBlock
  ``(Block.other (VersoSlides.BlockExt.notes) #[$contents,*])

/--
Fragment directive with push-down semantics. Pushes the fragment class onto each child
block's HTML tag.

Usage:
```
:::fragment fadeUp (index := 1)
Block content here.
:::
```
-/
@[directive]
public meta def fragment : DirectiveExpanderOf FragmentArgs
  | args, stxs => do
  let style := args.style.map nameToStyle
  let blocks ← stxs.mapM fun stx => do
    let b ← elabBlock stx
    ``(Block.other (VersoSlides.BlockExt.fragment $(quote style) $(quote args.index)) #[$b])
  ``(Block.concat #[$blocks,*])


/--
Class directive with push-down semantics. Pushes one or more CSS classes onto each child block.

Usage:
```
:::class "r-fit-text"
Big text!
:::
```
-/
@[directive]
public meta def «class» : DirectiveExpanderOf ClassArgs
  | args, stxs => do
  let cls := " ".intercalate args.classes.toList
  let attrs : Array (String × String) := #[("class", cls)]
  let blocks ← stxs.mapM fun stx => do
    let b ← elabBlock stx
    ``(Block.other (VersoSlides.BlockExt.attr $(quote attrs)) #[$b])
  ``(Block.concat #[$blocks,*])

/--
ID directive with push-down semantics. Pushes an `id` attribute onto each child block.

Usage:
```
:::id "custom-paragraph"
This paragraph has a custom id.
:::
```
-/
@[directive id]
public meta def idDirective : DirectiveExpanderOf IdArgs
  | args, stxs => do
  let attrs : Array (String × String) := #[("id", args.id)]
  let blocks ← stxs.mapM fun stx => do
    let b ← elabBlock stx
    ``(Block.other (VersoSlides.BlockExt.attr $(quote attrs)) #[$b])
  ``(Block.concat #[$blocks,*])

/--
Generic attribute directive with push-down semantics. Pushes arbitrary HTML attributes
onto each child block. Useful for `data-*` attributes.

Usage:
```
:::attr (data-id := "box") (data-auto-animate-delay := "0.5")
Content here.
:::
```
-/
@[directive]
public meta def attr : DirectiveExpanderOf AttrArgs
  | args, stxs => do
  let blocks ← stxs.mapM fun stx => do
    let b ← elabBlock stx
    ``(Block.other (VersoSlides.BlockExt.attr $(quote args.attrs)) #[$b])
  ``(Block.concat #[$blocks,*])

/--
Fit-text directive. Pushes `class="r-fit-text"` onto each child block so reveal.js
auto-sizes the text.

Usage:
```
:::fitText
Big text!
:::
```
-/
@[directive]
public meta def fitText : DirectiveExpanderOf Unit
  | (), stxs => do
  let attrs : Array (String × String) := #[("class", "r-fit-text")]
  let blocks ← stxs.mapM fun stx => do
    let b ← elabBlock stx
    ``(Block.other (VersoSlides.BlockExt.attr $(quote attrs)) #[$b])
  ``(Block.concat #[$blocks,*])

/--
Stretch directive. Pushes `class="r-stretch"` onto each child block so reveal.js
stretches the element to fill remaining slide space.

Usage:
```
:::stretch
![image](./img.png)
:::
```
-/
@[directive]
public meta def stretch : DirectiveExpanderOf Unit
  | (), stxs => do
  let attrs : Array (String × String) := #[("class", "r-stretch")]
  let blocks ← stxs.mapM fun stx => do
    let b ← elabBlock stx
    ``(Block.other (VersoSlides.BlockExt.attr $(quote attrs)) #[$b])
  ``(Block.concat #[$blocks,*])

/--
Frame directive. Pushes `class="r-frame"` onto each child block to add a default
styled border.

Usage:
```
:::frame
Framed content.
:::
```
-/
@[directive]
public meta def frame : DirectiveExpanderOf Unit
  | (), stxs => do
  let attrs : Array (String × String) := #[("class", "r-frame")]
  let blocks ← stxs.mapM fun stx => do
    let b ← elabBlock stx
    ``(Block.other (VersoSlides.BlockExt.attr $(quote attrs)) #[$b])
  ``(Block.concat #[$blocks,*])


/--
Stack layout directive. Wraps children in `<div class="r-stack">` for stacking
elements on top of each other.

Usage:
```
:::stack
First element (bottom of stack).

Second element (on top).
:::
```
-/
@[directive]
public meta def stack : DirectiveExpanderOf Unit
  | (), stxs => do
  let contents ← stxs.mapM elabBlock
  ``(Block.other (VersoSlides.BlockExt.wrap #[("class", "r-stack")]) #[$contents,*])

/--
Horizontal stack layout directive. Wraps children in `<div class="r-hstack">` for
horizontal arrangement.

Usage:
```
:::hstack
Left element.

Right element.
:::
```
-/
@[directive]
public meta def hstack : DirectiveExpanderOf Unit
  | (), stxs => do
  let contents ← stxs.mapM elabBlock
  ``(Block.other (VersoSlides.BlockExt.wrap #[("class", "r-hstack")]) #[$contents,*])

/--
Vertical stack layout directive. Wraps children in `<div class="r-vstack">` for
vertical arrangement.

Usage:
```
:::vstack
Top element.

Bottom element.
:::
```
-/
@[directive]
public meta def vstack : DirectiveExpanderOf Unit
  | (), stxs => do
  let contents ← stxs.mapM elabBlock
  ``(Block.other (VersoSlides.BlockExt.wrap #[("class", "r-vstack")]) #[$contents,*])


/--
Inline fragment role. Wraps content in `<span class="fragment ...">`.

Usage:
```
This is {fragment (style := highlightRed)}[important text].
```
-/
@[role VersoSlides.fragment]
public meta def fragmentRole : RoleExpanderOf InlineFragmentArgs
  | args, stxs => do
  let style := args.style.map nameToStyle
  let contents ← stxs.mapM elabInline
  ``(Inline.other (VersoSlides.InlineExt.fragment $(quote style) $(quote args.index)) #[$contents,*])

/--
Inline class role. Wraps content in `<span class="...">`.

Usage:
```
This is {class "highlight"}[highlighted text].
```
-/
@[role VersoSlides.«class»]
public meta def classRole : RoleExpanderOf ClassArgs
  | args, stxs => do
  let cls := " ".intercalate args.classes.toList
  let attrs : Array (String × String) := #[("class", cls)]
  let contents ← stxs.mapM elabInline
  ``(Inline.other (VersoSlides.InlineExt.styled $(quote attrs)) #[$contents,*])

/--
Inline id role. Wraps content in `<span id="...">`.

Usage:
```
This is {id "my-element"}[identified text].
```
-/
@[role id]
public meta def idRole : RoleExpanderOf IdArgs
  | args, stxs => do
  let attrs : Array (String × String) := #[("id", args.id)]
  let contents ← stxs.mapM elabInline
  ``(Inline.other (VersoSlides.InlineExt.styled $(quote attrs)) #[$contents,*])

/--
Generic inline attribute role. Wraps content in `<span>` with arbitrary HTML attributes.

Usage:
```
Some {attr (data-id := "word")}[animated word] here.
```
-/
@[role VersoSlides.attr]
public meta def attrRole : RoleExpanderOf AttrArgs
  | args, stxs => do
  let contents ← stxs.mapM elabInline
  ``(Inline.other (VersoSlides.InlineExt.styled $(quote args.attrs)) #[$contents,*])

/-- Arguments for the `{image}` role. -/
public meta structure ImageArgs where
  src : String
  width : Option String := none
  height : Option String := none
  «class» : Option String := none

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public meta instance : FromArgs ImageArgs m where
  fromArgs :=
    ImageArgs.mk <$>
      .positional `src .string <*>
      .named `width .string true <*>
      .named `height .string true <*>
      .named `class .string true
end


private meta def isUrl (s : String) : Bool :=
  s.startsWith "http://" || s.startsWith "https://" || s.startsWith "data:" || s.startsWith "//"

/--
Image role with configurable dimensions. Alt text must be plain text.

Usage:
```
{image "logo.png" (width := "200px")}[Company Logo]
```
-/
@[role]
public meta def image : RoleExpanderOf ImageArgs
  | args, stxs => do
  let mut altParts : Array String := #[]
  for stx in stxs do
    match stx with
    | `(inline| $strLit:str) =>
      altParts := altParts.push strLit.getString.trimAscii.copy
    | `(inline| line! $_) => continue
    | _ => logErrorAt stx "image alt text must be plain text, not formatted content"
  let alt : String := " ".intercalate altParts.toList

  -- Resolve the image source: URLs pass through, local paths get normalized to project root
  let imgSrc : ImgSrc ←
    if isUrl args.src then
      pure <| ImgSrc.remote args.src
    else
      let srcDir := (System.FilePath.mk (← getFileName)).parent.getD "."
      let absPath ← IO.FS.realPath (srcDir / args.src)
      let cwd ← IO.FS.realPath "."
      let cwdPrefix : String := cwd.toString ++ toString System.FilePath.pathSeparator
      let absStr : String := absPath.toString
      let rel : String := absStr.dropPrefix cwdPrefix |>.copy
      pure <| .projectRelative rel

  match imgSrc with
  | .projectRelative rel => saveLocalImagePreview rel alt
  | .remote url => saveRemoteImagePreview url alt

  ``(Inline.other (VersoSlides.InlineExt.image $(quote imgSrc) $(quote alt) $(quote args.width) $(quote args.height) $(quote args.class)) #[])

/--
Intercepts the Markdown-like `![alt](url)` syntax and warns that the `{image}` role should be used
instead, since it supports width, height, and class, and uses local path resolution. Controlled by
the `verso.slides.warnOnImage` option. After warning, delegates to the default handler.
-/
@[inline_expander Lean.Doc.Syntax.image]
public meta def warnOnMarkdownImage : InlineExpander
  | `(inline| image( $alt:str ) ( $url )) => do
    if (← getOptions).getBool `verso.slides.warnOnImage true then
      let suggestion := "{image " ++ url.getString.quote ++ "}[" ++ alt.getString ++ "]"
      let msg := m!"This image syntax is missing features that are useful for slides, such as width and height."
      let h ←
        (m!"Use the `{.ofConstName ``image}` role instead of `![alt](url)` for slides. " ++
         m!"It supports width, height, and CSS class, and it copies images to the output directory.").hint
        #[{ suggestion := .string suggestion }]
      logWarningAt alt (msg ++ h)
    throwUnsupportedSyntax
  | _ => throwUnsupportedSyntax

/-- Arguments for the `:::table` directive. All features are off by default. -/
public meta structure TableArgs where
  colHeaders  : Bool          := false
  rowHeaders  : Bool          := false
  stripedRows : Bool          := false
  stripedCols : Bool          := false
  rowSeps     : Bool          := false
  colSeps     : Bool          := false
  headerSep   : Bool          := false
  border      : Bool          := false
  cellGap     : Option String := none

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

-- The second argument to `.flag` is the default value when the flag is absent.
public meta instance : FromArgs TableArgs m where
  fromArgs :=
    TableArgs.mk
      <$> .flag `colHeaders  false
      <*> .flag `rowHeaders  false
      <*> .flag `stripedRows false
      <*> .flag `stripedCols false
      <*> .flag `rowSeps     false
      <*> .flag `colSeps     false
      <*> .flag `headerSep   false
      <*> .flag `border      false
      <*> .named `cellGap .string true
end

/--
Table directive. Input is a nested list of lists: each outer item is a row,
each inner item is a cell. All rows must have the same number of columns.

Boolean flags are written as `+name` (all off by default):
- `+colHeaders` — first row becomes `<thead>` with `<th scope="col">` cells
- `+rowHeaders` — first cell of each body row becomes `<th scope="row">`
- `+stripedRows` — alternating row background colors
- `+stripedCols` — alternating column background colors (checkerboard when combined with `+stripedRows`)
- `+rowSeps` — horizontal separator lines between data rows
- `+colSeps` — vertical separator lines between data columns
- `+headerSep` — thicker separator after the header row/column
- `+border` — separator lines on all outer edges

`cellGap` takes a named string passed through as a CSS `padding` shorthand
(one, two, or four lengths), e.g. `(cellGap := "0.4em 0.6em")`.

Usage:
```
:::table +colHeaders +stripedRows +border
*
  * Header A
  * Header B
*
  * Cell A1
  * Cell B1
*
  * Cell A2
  * Cell B2
:::
```
-/
@[directive]
public meta def table : DirectiveExpanderOf TableArgs
  | args, contents => do
    let #[oneBlock] := contents
      | throwError "Expected a single unordered list"
    let `(block|ul{$items*}) := oneBlock
      | throwErrorAt oneBlock "Expected a single unordered list"
    let preRows ← items.mapM getLi
    let rows ← preRows.mapM fun blks => do
      let #[oneInRow] := blks.filter (·.raw.isOfKind ``Lean.Doc.Syntax.ul)
        | throwError "Each row should have exactly one list in it"
      let `(block|ul{ $cellItems*}) := oneInRow
        | throwErrorAt oneInRow "Each row should have exactly one list in it"
      cellItems.mapM getLi
    if h : rows.size = 0 then
      throwErrorAt oneBlock "Expected at least one row"
    else
      let columns := rows[0].size
      if columns = 0 then
        throwErrorAt oneBlock "Expected at least one column"
      if rows.any (·.size != columns) then
        throwErrorAt oneBlock s!"Expected all rows to have same number of columns, but got {rows.map (·.size)}"
      let flattened := rows.flatten
      let blocks : Array (Syntax.TSepArray `term ",") ← flattened.mapM (·.mapM elabBlock)
      let style : TableStyle := {
        colHeaders  := args.colHeaders,  rowHeaders  := args.rowHeaders,
        stripedRows := args.stripedRows, stripedCols := args.stripedCols,
        rowSeps     := args.rowSeps,     colSeps     := args.colSeps,
        headerSep   := args.headerSep,   border      := args.border,
        cellGap     := args.cellGap }
      ``(Block.other
          (VersoSlides.BlockExt.table $(quote columns) $(quote style))
          #[Block.ul #[$[Verso.Doc.ListItem.mk #[$blocks,*]],*]])
where
  getLi : Syntax → DocElabM (TSyntaxArray `block)
    | `(list_item| * $content*) => pure content
    | other => throwErrorAt other "Expected list item"

/--
Custom CSS block. The content is collected during traversal and injected
as a `<style>` element in the page header.

Usage:
````
```css
.my-class { color: red; }
```
````
-/
@[code_block]
public meta def css : CodeBlockExpanderOf Unit
  | (), str =>
    ``(Verso.Doc.Block.other (BlockExt.css $(quote str.getString)) #[])
