/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import Verso.Doc.Concrete
import Illuminate

open VersoSlides

set_option verso.code.warnLineLength 500

#doc (Slides) "VersoSlides Demo" =>

# Introduction

Welcome to *VersoSlides* — a Verso genre for building
[`reveal.js`](https://revealjs.com) slide presentations from Lean.

This demo exercises all the major features.

:::notes
This is a speaker note on the introduction slide.
Press *S* to open the speaker view.
:::

# Features Overview

VersoSlides supports:

* Elaborated Lean code blocks with hovers and info panels
* Inline Lean expressions: elaborated and type-checked
* Progressive proof reveals with magic comments
* Hidden setup code and replaced expressions
* Fragment animations (block and inline)
* Per-slide metadata (backgrounds, transitions)
* Speaker notes (press `s` on your keyboard)

:::fragment
Read on for examples of each.
:::

# Code Example

Here is an elaborated Lean code block:

```lean
def hello : IO Unit := do
  IO.println "Hello from VersoSlides!"
```

```lean
#check hello
```
And some inline {lean}`hello` for good measure. {lean}`Unit`

# Code on Light Background
%%%
backgroundColor := "#f5f5f5"
%%%

A light-themed slide with Lean code:

```lean
def greet (name : String) : String :=
  s!"Hello, {name}!"

#eval greet "Lean"
```

# Proof

```lean
def replicate (n : Nat) (x : α) : List α :=
  match n with
  | 0 => []
  | n' + 1 => x :: replicate n' x

-- !fragment
theorem replicate_length : ∀ {n : Nat} {x : α},
    (replicate n x).length = n := by
  intro n
-- !fragment
  intro x
-- ^ !click
  induction n
  . grind [replicate]
  next n' ih =>
-- !fragment fadeUp
    simp only [replicate]
    conv =>
      rhs
      rw [← ih]
    simp
```

# Proof with Hidden Setup

```lean
/- !hide -/def fact : Nat → Nat
  | 0 => 1
  | n + 1 => (n + 1) * fact n
-- !end hide
theorem fact_pos : ∀ n, 0 < fact n := by
-- !fragment
  intro n
-- ^ !click
  induction n with
  | zero => simp [fact]
-- !fragment
  | succ n ih =>
    simp [fact]
    omega
```

# Proof with Fragment Indices

```lean
-- !hide
def sum_to : Nat → Nat
  | 0 => 0
  | n + 1 => (n + 1) + sum_to n
-- !end hide
-- !fragment 2
theorem sum_to_formula : ∀ n,
    2 * sum_to n = n * (n + 1) := by
-- !fragment 1
  intro n
-- ^ !click 1
  induction n with
  | zero => simp [sum_to]
-- !fragment 3
  | succ n ih =>
    grind [sum_to]
```

# Proof with Fragment Effects

```lean -show
/-- This function is invisible -/
def hiddenFunction (x : Nat) : String := s!"{x}{x}"
```
```lean
/- !fragment highlight-current-green -/def y := /- !fragment grow -/hiddenFunction/- !end fragment -/ /- !fragment shrink -/22/- !end fragment -//- !end fragment -/

-- !fragment grow
def z := 5
-- !fragment highlight-current-red
def zz := 22
```

# Hidden Lean

This slide has hidden setup code.

```lean -show
section
set_option pp.all true
variable {α : Type} [ToString α]
```
We have {lean}`α` available here:
```lean
#check List α
```
But not {lean +error}`β`.
```lean -show
end
```

# Without Panel

```lean -panel
-- There is no info panel here
def simple : Nat := 42
```

# Replace Example

```lean
def result : Nat :=
  /- !replace ... -/ List.length [1, 2, 3] /- !end replace -/
```

# Other Languages

```code rust
fn main() {
    let nums = vec![3, 1, 4, 1, 5, 9];
    let max = nums.iter().max().unwrap();
    println!("Max: {max}");
}
```

```code "c++"
#include <iostream>
#include <vector>

int main() {
    std::vector<int> v = {1, 2, 3};
    for (auto x : v) std::cout << x << "\n";
}
```

# Complete Modules

```leanModule
module
import Std.Data.HashMap

open Std
def xs : HashMap Nat String := {}
```

# Lake Configs

```leanModule +lakefile
import Lake
open Lake DSL

require «verso-slides» from git
  "https://github.com/leanprover/verso-slides.git"@"main"

package «etaps-tutorial» where
  version := v!"0.1.0"

lean_lib MiniRadix
```

# Multi-Module Examples

:::leanModules (moduleRoot := Lib)
```leanModule (moduleName := Lib.A)
module
public def x : Nat := 1
def y : Nat := 2
```
```leanModule (moduleName := Lib.B)
module
import Lib.A
def z := x
/-- error: Unknown identifier `y` -/
#guard_msgs in
def x' := y
```
:::

# Multi-Module Examples with Lakefiles

:::leanModules
```leanModule +lakefile
import Lake
open Lake DSL

package p

lean_lib A
```
```leanModule (moduleName := A)
def x := "Module A!"
```
We can refer to {name}`x`.
:::

# Library Code

Show the current source of a declaration from a dependency:

```leanLibCode Verso.Code.External (package := verso) (decl := Verso.Code.External.withNl)
/--
Adds a newline to a string if it doesn't already end with one.
-/
public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
```

Or a specific line range:

```leanLibCode Verso.Code.External (package := verso) (startLine := 77) (endLine := 77)
public meta def withNl (s : String) : String := if s.endsWith "\n" then s else s ++ "\n"
```

# Fragment Styles

:::fragment fadeUp
This block fades up.
:::

:::fragment fadeUp (index := 2)
This block also fades up, but with explicit index 2.
:::

Here is an {fragment (style := highlightRed)}[inline red highlight]
within a sentence.

And another {fragment (style := highlightBlue) (index := 3)}[inline blue highlight]
with an explicit index.

# Math

$$`\frac{dV(t)}{dt} = \delta_t\, V(t) + \pi_t - b_t
    - \mu_{x+t}\bigl(S_t - V(t)\bigr)`

* $`\delta_t` is the force of interest at time $`t`
* $`\pi_t` is the premium payment rate
* $`b_t` is the continuous benefit payment rate
* $`\mu_{x+t}` is the force of mortality for a life aged $`x + t`
* $`S_t` is the sum payable on death at time $`t`

# Vertical Slides
%%%
vertical := true
%%%

This content appears on the first implicit vertical sub-slide.

## Sub-slide A

This is vertical sub-slide A.

Navigate *down* to see the next sub-slide.

## Sub-slide B
%%%
backgroundColor := "#4d7e65"
%%%

This vertical sub-slide has a custom green background.

:::notes
Vertical slides are great for supplementary content.
:::

# Custom Attributes

:::fitText
Big text!
:::

:::id "custom-paragraph"
This paragraph has a custom `id` attribute.
:::

:::attr («data-id» := "my-box")
This paragraph has a custom `data-id` for auto-animate matching.
:::

# Auto-Animate

%%%
autoAnimate := true
%%%

:::attr («data-id» := "title")
Small title
:::

# Auto-Animate (cont.)

%%%
autoAnimate := true
%%%

:::::fitText
:::attr («data-id» := "title")
*Big* title
:::
:::::

# Custom Background
%%%
backgroundColor := "#2d1b69"
transition := "zoom"
%%%

This slide has a purple background and uses the *zoom* transition.

# Horizontal Stack

The `:::hstack` directive arranges children side by side.

:::hstack
Left column content.

Center column content.

Right column content.
:::

# Vertical Stack

The `:::vstack` directive arranges children vertically with centered alignment.

:::vstack
Top item.

Middle item.

Bottom item.
:::

# Stack (Overlay)

The `:::stack` directive overlays children on top of each other.
Combine with fragments to reveal them one at a time.

:::::stack
:::fragment fadeOut
First layer (visible initially).
:::

:::fragment fadeIn
Second layer (appears on click).
:::
:::::

# Frame

The `:::frame` directive adds a default styled border around content.

:::frame
This paragraph is framed.
:::

:::frame
Another framed block, separately bordered.
:::

# Stretch

The `:::stretch` directive makes an element fill the remaining slide space.

:::stretch
This content stretches to fill available vertical space.
:::

A footer line after the stretched content.

# Class Directive

The `:::class` directive pushes one or more CSS classes onto each child block.

:::class "r-fit-text"
Custom-classed text!
:::

# Inline Class Role

The `{class}` role wraps inline content in a `<span>` with CSS classes.

This sentence has {class "fragment highlight-green"}[green highlighted] text
that appears as a fragment.

# Inline ID Role

The `{id}` role wraps inline content with an HTML `id` attribute.

This word is {id "special-word"}[identifiable] by its ID.

# Inline Attr Role

The `{attr}` role applies arbitrary HTML attributes to inline content.

This {attr («data-id» := "morphing-word")}[word] has a custom data attribute.

# Custom CSS

```css
.demo-highlight { color: #ff6600; font-weight: bold; }
```

:::class "demo-highlight"
This text is styled with custom CSS injected via a `css` code block.
:::

# Image Role

The `{image}` role renders an `<img>` tag with configurable width and height. The path to the image is relative to the source file.

{image "demo-images/demo-image.svg" (width := "300px")}[Demo image]


# Lean Command Role

The `{leanCommand}` role renders a single elaborated Lean command inline.

Here is an inline command: {leanCommand}`#check Nat.add_comm`

# Diagram

```diagram (background := "#ffffff")
open Illuminate in
let box (n : Lean.Name) (label : String) (clr : Color) : Diagram SVG :=
  Diagram.atop
    (Diagram.text label { fontSize := 14, fontFamily := "text" })
    (Diagram.roundedRect 120 40 6
      (fill := clr) (stroke := { width := 1.5 })
      (name := n))
let src := Diagram.paper
  (label := some (Diagram.text "Lean\nSource" { fontSize := 14, fontFamily := "text" }))
  (width := some 70) (cornerFold := 0.2)
  (fill := rgb!"#5b8bd4") (stroke := { width := 1.5 })
  (name := some `src)
let tip : LineEnd := { point := `elab.west, arrowhead := some { type := .latex } }
let tip2 : LineEnd := { point := `hl.north, arrowhead := some { type := .latex }, angle := some (3 * pi / 2), pull := 0.5 }
let tip3 : LineEnd := { point := `html.west, arrowhead := some { type := .latex } }
Diagram.vsep 80 [
  .hsep 60 [ src, box `elab "Elaborate" (rgb!"#7cc47c")],
  .hsep 60 [box `hl "Highlight" (rgb!"#f0c050"), box `html "HTML" (rgb!"#e06050") ]
]
|>.connect `src.east tip (stroke := { width := 1.5 })
|>.connect { point := `elab.south, angle := some (3 * pi / 2), pull := 0.5 } tip2 (stroke := { width := 1.5 })
|>.connect `hl.east tip3 (stroke := { width := 1.5 })
```

# Animation

```animate (fps := 70) (background := "#ffffff") +autoplay
open Illuminate VersoSlides in
{ steps :=
    [{ duration := 1.0 },
     { duration := 1.5 },
     { duration := 0, pause := true },
     { duration := 1.0 },
     { duration := 2.0, loop := true }],
  render := fun v =>
    let dot :=
      Diagram.circle 20 (fill := rgb!"#5b8bd4") (stroke := { width := 2 })
      |>.scale (1.0 + 0.8 * (v[4] - 0.5).abs)
    let start : Vec2 := { x := -100, y := 0 }
    let stop : Vec2 := { x := 100, y := 0 }
    let pos := Interpolate.interpolate start stop (Easing.easeInOut v[1])
    let opacity := v[0]
    dot.translate pos.x pos.y |>.cellophane opacity |>.compose
      (Diagram.text "Click to advance" { fontSize := 12, fontFamily := "text" }
        |>.translate 0 (-40)
        |>.cellophane (v[1] - v[3])) }
```

# Shape Morphing

:::::::::hstack

:::::::attr (style := "text-align: center; font-size: 2em")

:::::stack
:::fragment fadeOut (index := 1)
*Square*
:::
:::fragment fadeInThenOut (index := 1)
*Circle*
:::
:::fragment fadeIn (index := 2)
*Star*
:::
:::::

:::::::

```animate (background := "#ffffff")
open Illuminate VersoSlides in
let sq := Diagram.roundedRect 60 60 4
  (fill := rgb!"#5b8bd4") (stroke := { width := 2 })
let circ := Diagram.circle 34
  (fill := rgb!"#7cc47c") (stroke := { width := 2 })
let st := Diagram.star 5 38 18
  (fill := rgb!"#f0c050") (stroke := { width := 2 })
let rotatedSq := sq.rotate (pi / 4)
let morph1 : Morph SVG :=
  { node := prepareMorph rotatedSq circ, source := rotatedSq, target := circ }
let morph2 : Morph SVG :=
  { node := prepareMorph circ st, source := circ, target := st }
{ steps :=
    [{ duration := 0.5, pause := true, fragmentIndex := some 1 },
     { duration := 1.0 },
     { duration := 1.0, pause := true, fragmentIndex := some 2 },
     { duration := 4.0, loop := true, pause := true, fragmentIndex := some 3 }],
  render := fun v =>
    let t1 := Easing.easeInOut v[0]
    let t2 := Easing.easeInOut v[1]
    let t3 := Easing.easeInOut v[2]
    let shape :=
      if t3 > 0 then morph2.evaluate t3
      else if t2 > 0 then morph1.evaluate t2
      else sq.rotate (t1 * pi / 4)
    let angle := v[3] * 2 * pi
    shape.rotate angle }
```

:::::::::

# Tables
%%%
vertical := true
%%%

Navigate *down* through five table examples.

## Striped Rows
%%%
backgroundColor := some "#f5f5f5"
%%%

Column headers and striped rows on a light background.

:::table +colHeaders +stripedRows
*
  * Type
  * Size
  * Signed
  * Example
*
  * {lean}`Nat`
  * Unbounded
  * No
  * {lean}`0`, {lean}`42`
*
  * {lean}`Int`
  * Unbounded
  * Yes
  * {lean (type := "Int")}`-5`, {lean (type := "Int")}`100`
*
  * {lean}`Float`
  * 64-bit
  * Yes
  * {lean}`3.14`
:::

## Striped Columns
%%%
backgroundColor := some "#0d1b2a"
%%%

Striped columns and row headers on a dark background.

:::table +colHeaders +rowHeaders +stripedCols +headerSep
*
  * Tactic
  * Closes?
  * Rewrites?
  * New goals?
*
  * `exact`
  * ✓
  * —
  * —
*
  * `apply`
  * —
  * —
  * ✓
*
  * `intro`
  * —
  * ✓
  * —
*
  * `simp`
  * partial
  * ✓
  * —
*
  * `omega`
  * ✓
  * —
  * —
:::

## Row Separators

Column headers and row separators, no stripes or border.

:::table +colHeaders +rowSeps
*
  * Transition
  * Effect
*
  * `slide`
  * Default horizontal motion
*
  * `fade`
  * Cross-fade between slides
*
  * `convex`
  * Angled away from viewer
*
  * `concave`
  * Angled toward viewer
*
  * `zoom`
  * Zoom in from center
*
  * `none`
  * Instant cut
:::

## Bordered Table

Row separators and an outer border.

:::table +colHeaders +rowSeps +border
*
  * Directive
  * Arguments
  * Effect
*
  * `notes`
  * —
  * Speaker notes
*
  * `fragment`
  * style, index
  * Progressive reveal
*
  * `fitText`
  * —
  * Auto-sizes text to fit
*
  * `stretch`
  * —
  * Fills remaining slide height
*
  * `hstack`
  * —
  * Horizontal side-by-side layout
:::

## Propositional Connectives

Striped

:::table +colHeaders +rowHeaders +stripedRows +stripedCols +border +headerSep
*
  * (A, B)
  * A ∧ B
  * A ∨ B
  * A → B
  * A ↔ B
*
  * (T, T)
  * T
  * T
  * T
  * T
*
  * (T, F)
  * F
  * T
  * F
  * F
*
  * (F, T)
  * F
  * T
  * T
  * F
*
  * (F, F)
  * F
  * F
  * T
  * T
:::


# Thank You

That concludes the *VersoSlides* demo.

:::fragment
Questions?
:::

:::notes
Wrap up and take questions.
:::
