/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

set_option verso.code.warnLineLength 500

#doc (Slides) "VersoSlides Demo" =>
%%%
theme := "black"
slideNumber := true
transition := "slide"
%%%

# Introduction

Welcome to *VersoSlides* — a Verso genre for building
[reveal.js](https://revealjs.com) slide presentations from Lean 4.

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
  | n + 1 => (n + 1) * fact n/- !end hide -/
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
/- !hide -/
def sum_to : Nat → Nat
  | 0 => 0
  | n + 1 => (n + 1) + sum_to n
/- !end hide -/

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

# Thank You

That concludes the *VersoSlides* demo.

:::fragment
Questions?
:::

:::notes
Wrap up and take questions.
:::
