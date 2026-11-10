/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
Tests for elaboration errors in code included from an external example project.
-/
module

public import VersoSlides

open VersoSlides

set_option verso.exampleProject "TestFixtures/external-example"
set_option verso.exampleModule "Example"

-- A malformed slide magic comment is reported during elaboration.
/--
error: Unclosed hide or replace region (/- !hide -/ or /- !replace ... -/ without matching end marker)
-/
#guard_msgs in
#docs (Slides) brokenMagicComment "Broken Magic Comment" :=
:::::::

# Broken

```anchor brokenHide
def visible : Nat := 1
-- !hide
def hidden : Nat := 2
```
:::::::

-- A missing anchor is reported once.
/--
error: Anchor not found.



Hint: Use a defined anchor
  • w̵r̵o̵n̵g̵p̲r̲o̲o̲f̲
  • w̵r̵o̵n̵g̵s̲t̲e̲p̲s̲
  • w̵r̵o̵n̵g̵d̲o̲u̲b̲l̲e̲
  • w̵r̵o̵n̵g̵b̲r̲o̲k̲e̲n̲H̲i̲d̲e̲
  • w̵r̵o̵n̵g̵e̲v̲a̲l̲D̲o̲u̲b̲l̲e̲
-/
#guard_msgs(drop info, error) in
#docs (Slides) missingAnchor "Missing Anchor" :=
:::::::

# Missing

```anchor wrong
x
```
:::::::
