/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
import VersoSlides.Basic
import Verso.Doc.Elab
import Verso.Doc.ArgParse
public import Verso.Doc.Elab.Monad

open Verso Doc Elab ArgParse
open Lean Elab

namespace VersoSlides


/-- Arguments for the `:::fragment` directive. -/
public structure FragmentArgs where
  style : Option Name := none
  index : Option Nat := none

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public instance : FromArgs FragmentArgs m where
  fromArgs :=
    FragmentArgs.mk <$>
      (some <$> .positional `style .name <|> pure none) <*>
      .named `index .nat true
end

/-- Arguments for the `{fragment}` inline role. -/
public structure InlineFragmentArgs where
  style : Option Name := none
  index : Option Nat := none

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public instance : FromArgs InlineFragmentArgs m where
  fromArgs :=
    InlineFragmentArgs.mk <$>
      .named `style .name true <*>
      .named `index .nat true
end

/-- Arguments for variadic class directives/roles: one or more positional string args. -/
public structure ClassArgs where
  classes : Array String

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public instance : FromArgs ClassArgs m where
  fromArgs :=
    ClassArgs.mk <$> (List.toArray <$> ArgParse.many (.positional `class .string))
end

/-- Arguments for the `:::id` directive / `{id}` role: single positional string arg. -/
public structure IdArgs where
  id : String

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public instance : FromArgs IdArgs m where
  fromArgs :=
    IdArgs.mk <$> .positional `id .string
end

/-- Arguments for the `:::attr` directive / `{attr}` role: variadic named key-value pairs. -/
public structure AttrArgs where
  attrs : Array (String × String)

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m] [MonadLiftT CoreM m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

public instance : FromArgs AttrArgs m where
  fromArgs :=
    AttrArgs.mk <$> (List.toArray <$>
      ArgParse.many ((fun (k, v) => (k.getId.toString (escape := false), v)) <$>
        .anyNamed `attribute .string))
end


/-- Converts a Lean `Name` to a kebab-case fragment style string. -/
private def nameToStyle (n : Name) : String :=
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
public def notes : DirectiveExpanderOf Unit
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
public def fragment : DirectiveExpanderOf FragmentArgs
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
public def «class» : DirectiveExpanderOf ClassArgs
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
public def idDirective : DirectiveExpanderOf IdArgs
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
public def attr : DirectiveExpanderOf AttrArgs
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
public def fitText : DirectiveExpanderOf Unit
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
public def stretch : DirectiveExpanderOf Unit
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
public def frame : DirectiveExpanderOf Unit
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
public def stack : DirectiveExpanderOf Unit
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
public def hstack : DirectiveExpanderOf Unit
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
public def vstack : DirectiveExpanderOf Unit
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
public def fragmentRole : RoleExpanderOf InlineFragmentArgs
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
public def classRole : RoleExpanderOf ClassArgs
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
public def idRole : RoleExpanderOf IdArgs
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
public def attrRole : RoleExpanderOf AttrArgs
  | args, stxs => do
  let contents ← stxs.mapM elabInline
  ``(Inline.other (VersoSlides.InlineExt.styled $(quote args.attrs)) #[$contents,*])
