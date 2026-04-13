/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import Lake

open System Lake DSL

require verso from git "https://github.com/leanprover/verso.git"@"main"
require illuminate from git "https://github.com/leanprover/illuminate.git"@"main"

package «verso-slides» where
  version := v!"0.1.0"

input_dir vendorAssets where
  path := "vendor"

lean_lib VersoSlidesVendored where
  needs := #[vendorAssets]

input_dir panelAssets where
  path := "panel"

input_dir animateAssets where
  path := "animate"

lean_lib VersoSlides where
  needs := #[panelAssets, animateAssets]

lean_lib Demo

@[default_target] lean_exe «demo-slides» where root := `Main

lean_exe «extract-lakefile» where root := `ExtractLakefile

@[test_driver]
lean_exe «verso-slides-test» where root := `TestMain

lean_lib TestFixtures

lean_exe «test-fixtures-build» where
  root := `TestFixtures.Build

lean_lib TestElab

lean_lib Tests

lean_exe «test-fragmentize» where
  root := `Tests.Fragmentize

lean_exe «test-render» where
  root := `Tests.Render

lean_exe «test-comment-parsers» where
  root := `Tests.CommentParsers
