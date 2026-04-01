/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
Tests for the `verso.slides.warnOnImage` option and the `{image}` role's
alt-text validation.
-/
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

-- Markdown image syntax should produce a warning by default.
/--
warning: This image syntax is missing features that are useful for slides, such as width and height.

Hint: Use the `image` role instead of `![alt](url)` for slides. It supports width, height, and CSS class, and it copies images to the output directory.
  !̵[̵a̵l̵t̵ ̵t̵e̵x̵t̵]̵(̵h̵t̵t̵p̵:̵/̵/̵e̵x̵a̵m̵p̵l̵e̵.̵c̵o̵m̵/̵i̵m̵g̵.̵p̵n̵g̵)̵{̲i̲m̲a̲g̲e̲ ̲"̲h̲t̲t̲p̲:̲/̲/̲e̲x̲a̲m̲p̲l̲e̲.̲c̲o̲m̲/̲i̲m̲g̲.̲p̲n̲g̲"̲}̲[̲a̲l̲t̲ ̲t̲e̲x̲t̲]̲
-/
#guard_msgs in
#docs (Slides) warnDefault "Warn Default" :=
:::::::
![alt text](http://example.com/img.png)
:::::::

-- Setting `verso.slides.warnOnImage` to false should suppress the warning.
set_option verso.slides.warnOnImage false in
#guard_msgs in
#docs (Slides) warnSuppressed "Warn Suppressed" :=
:::::::
![alt text](http://example.com/img.png)
:::::::

-- The {image} role should reject non-plain-text alt content.
/--
error: image alt text must be plain text, not formatted content
-/
#guard_msgs in
#docs (Slides) fmtAlt "Formatted Alt" :=
:::::::
{image "http://example.com/img.png"}[`code alt`]
:::::::

-- Newlines in alt text should be collapsed into a single space.
#guard_msgs in
#docs (Slides) nlAlt "Newline Alt" :=
:::::::
{image "http://example.com/img.png"}[alt text
  with a newline]
:::::::
