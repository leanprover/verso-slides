/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides
import Verso.Doc.Concrete
import Illuminate

open VersoSlides

#doc (Slides) "Diagram & Animation Fixture" =>

# Simple Diagram

```diagram
open Illuminate in
Diagram.circle 40 (fill := rgb!"#5b8bd4") (stroke := { width := 2 })
```

# Diagram Background

```diagram (background := "#ffffff")
open Illuminate in
Diagram.roundedRect 80 50 6 (fill := rgb!"#7cc47c") (stroke := { width := 2 })
```

# Animation Autoplay

```animate +autoplay
open Illuminate VersoSlides in
{ steps :=
    [{ duration := 0.5 },
     { duration := 0, pause := true },
     { duration := 0.5 }],
  render := fun v =>
    let c := Diagram.circle 30 (fill := rgb!"#5b8bd4")
    c.cellophane v[0] }
```

# Animation No Autoplay

```animate
open Illuminate VersoSlides in
{ steps :=
    [{ duration := 0.5 },
     { duration := 0, pause := true }],
  render := fun v =>
    let c := Diagram.circle 30 (fill := rgb!"#e06050")
    c.cellophane v[0] }
```

# Animation Click

```animate
open Illuminate VersoSlides in
{ steps :=
    [{ duration := 0.3, pause := true },
     { duration := 0.3, pause := true },
     { duration := 0.3, pause := true }],
  render := fun v =>
    let r := 20.0 + 10.0 * v[0] + 10.0 * v[1] + 10.0 * v[2]
    Diagram.circle r (fill := rgb!"#5b8bd4") }
```

# Shape Morphing

:::::::::hstack

:::::::attr (style := "text-align: center; font-size: 2em")

:::::stack
:::fragment fadeOut (index := 1)
*A*
:::
:::fragment fadeIn (index := 1)
*B*
:::
:::::

:::::::

```animate
open Illuminate VersoSlides in
{ steps :=
    [{ duration := 0.3, pause := true, fragmentIndex := some 1 }],
  render := fun v =>
    let sq := Diagram.roundedRect 40 40 4 (fill := rgb!"#5b8bd4")
    let circ := Diagram.circle 22 (fill := rgb!"#7cc47c")
    crossFade sq circ (Easing.easeInOut v[0]) }
```

:::::::::

# Animation Loop End

```animate
open Illuminate VersoSlides in
{ steps :=
    [{ duration := 0.3, pause := true },
     { duration := 1.0, loop := true }],
  render := fun v =>
    let c := Diagram.circle 30 (fill := rgb!"#f0c050")
    c.rotate (v[1] * 2.0 * Illuminate.pi)
      |>.compose (Diagram.rect 5 30 (fill := rgb!"#e06050")) }
```

# Animation Loop Middle

```animate
open Illuminate VersoSlides in
{ steps :=
    [{ duration := 0.3, pause := true },
     { duration := 1.0, loop := true, pause := true },
     { duration := 0.3, pause := true }],
  render := fun v =>
    let c := Diagram.circle (20.0 + 10.0 * v[2]) (fill := rgb!"#f0c050")
    c.rotate (v[1] * 2.0 * Illuminate.pi)
      |>.compose (Diagram.rect 5 30 (fill := rgb!"#e06050")) }
```
