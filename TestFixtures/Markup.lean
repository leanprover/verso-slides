/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

#doc (Slides) "Markup Fixture" =>

# Slide One
A simple slide.
:::notes
Speaker notes here.
:::

# Vertical Section
%%%
vertical := some true
%%%
Implicit first sub-slide.

## Sub A
Sub-slide A content.

## Sub B
%%%
backgroundColor := some "#4d7e65"
%%%
Green background sub-slide.
:::notes
Vertical sub-slide notes.
:::

# Fragments
:::fragment fadeUp
Fade-up block.
:::
:::fragment fadeUp (index := 2)
Indexed fade-up block.
:::
{fragment (style := highlightRed)}[red highlight] and
{fragment (style := highlightBlue) (index := 3)}[blue highlight]

# Metadata
%%%
backgroundColor := some "#2d1b69"
transition := some "zoom"
%%%
Purple background with zoom transition.

# Auto-Animate One
%%%
autoAnimate := some true
%%%
First.

# Auto-Animate Two
%%%
autoAnimate := some true
%%%
Second.

# Image Test

{image "images/test-logo.png" (width := "200px") (height := "100px") (class := "test-img-class")}[Test logo]

{image "images/plain.png"}[Plain image]

{image "https://example.com/remote.png"}[Remote image]

{image "images/subdir/test-logo.png"}[Dedup logo]

# CSS Test

{image "images/styled.png" (class := "css-target")}[Styled image]

```css
.css-target { border: 3px solid red; opacity: 0.5; }
```

# Last Slide
:::fragment
A fragment paragraph.
:::
:::notes
Final notes.
:::
