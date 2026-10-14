/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

module

public import VersoSlides.Pretty
meta import Vir.Attributes

namespace VersoSlides.VirPrettyM

/-- Slides-owned PrettyM entrypoint for VIR's direct host call ABI. -/
@[vir_export] public def formatSegments (format : Std.Format) (width indent : Nat) :
    Array Pretty.Segment :=
  Pretty.formatSegments format width indent

end VersoSlides.VirPrettyM
