/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import Lean.Data.Json.FromToJson.Basic

open Lean

set_option doc.verso true

namespace VersoSlides

/-- The source of an image: either a remote URL or a project-root-relative local path. -/
public inductive ImgSrc where
  | remote (url : String)
  | projectRelative (path : String)
deriving BEq, Repr, ToJson, FromJson

public instance : Quote ImgSrc where
  quote
    | .remote url => Syntax.mkApp (mkCIdent ``ImgSrc.remote) #[quote url]
    | .projectRelative path => Syntax.mkApp (mkCIdent ``ImgSrc.projectRelative) #[quote path]
