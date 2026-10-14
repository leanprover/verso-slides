/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

import Lake
open Lake DSL

require «verso-slides» from "../.."

package «my-talk» where
  requiresModuleSystem := true
  buildDir := "talk-build"

lean_lib MyTalk

@[default_target] lean_exe «my-talk» where
  root := `Main
