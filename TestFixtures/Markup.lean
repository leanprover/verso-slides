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
%%%
autoSlide := some 5000
%%%
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

{image "images/oversized-test.png" (width := "2000px") (height := "1500px")}[Oversized image]

# CSS Test

{image "images/styled.png" (class := "css-target")}[Styled image]

```css
.css-target { border: 3px solid red; opacity: 0.5; }
```

:::class "extra-banner"
This paragraph is styled via extraCss config.
:::

# Tables

:::table +colHeaders +rowHeaders +stripedRows +colSeps +headerSep +border
*
  * Header A
  * Header B
  * Header C
*
  * Row 1
  * Cell A1
  * Cell A2
*
  * Row 2
  * Cell B1
  * Cell B2
:::

:::table +stripedCols +rowSeps
*
  * A
  * B
*
  * C
  * D
*
  * E
  * F
:::

:::table +stripedRows +stripedCols
*
  * A
  * B
*
  * C
  * D
:::

:::table +colHeaders (cellGap := "0.6em 1.2em")
*
  * Name
  * Value
*
  * x
  * 42
:::

:::table +colHeaders +rowHeaders +rowSeps +colSeps
*
  * Key
  * A
  * B
*
  * row1
  * 1
  * 2
*
  * row2
  * 3
  * 4
:::

:::table +colHeaders +stripedRows +stripedCols
*
  * H1
  * H2
  * H3
*
  * a1
  * a2
  * a3
*
  * b1
  * b2
  * b3
:::

# Math

Inline math: $`e^{i\pi} + 1 = 0`.

Display math:

$$`\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}`

The fundamental theorem: $`\sum_{k=1}^n k = \frac{n(n+1)}{2}`.

Prelude macro: $`\RR` and display $$`\Hom(A, B) \subseteq \RR`.

# Last Slide
:::fragment
A fragment paragraph.
:::
:::notes
Final notes.
:::
