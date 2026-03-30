/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
/-
Tests for error reporting in code blocks.

Before the fix, a code block with an error (but no +error flag) would throw
"No error expected in code block, one occurred" in addition to the actual
Lean error. After the fix, only the actual error is reported.
-/
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

-- Without +error: only the actual Lean error should appear.
-- Before the fix, a third error "No error expected in code block, one occurred" was also thrown.
/--
error: Unknown identifier `z`
-/
#guard_msgs in
#docs (Slides) noError "Error Test" :=
:::::::
{lean}`z`
:::::::

-- With +error: errors are silenced (downgraded to warnings, then marked silent).
#guard_msgs in
#docs (Slides) withError "Error Test" :=
:::::::
{lean +error}`z`
:::::::
