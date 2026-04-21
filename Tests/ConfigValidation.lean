/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides

open VersoSlides

def dummyCss (name : String) (body : String := "") : CssFile where
  filename := name
  contents := ⟨body⟩

def dummyAsset (name : String) (body : String := "") : ThemeAsset where
  filename := name
  contents := body.toUTF8

def dummyBundle (stylesheet : CssFile) (assets : Array ThemeAsset := #[]) : CustomTheme :=
  { stylesheet, assets }

def expectOk (desc : String) (cfg : Config) : IO (Except String Unit) := do
  try
    cfg.validateFilenames
    return .ok ()
  catch e =>
    return .error s!"{desc}: expected success, got {e}"

def expectFail (desc : String) (cfg : Config) : IO (Except String Unit) := do
  try
    cfg.validateFilenames
    return .error s!"{desc}: expected failure, got success"
  catch _ =>
    return .ok ()

/-- String substring check. -/
private def hasSubstr (haystack needle : String) : Bool :=
  haystack.find? needle |>.isSome

/--
Asserts that the collision error message mentions each given substring. The
README promises that collision errors name the offending filename *and both
sources* — this test pins that claim to the actual error text.
-/
def expectFailMentioning (desc : String) (cfg : Config)
    (needles : List String) : IO (Except String Unit) := do
  try
    cfg.validateFilenames
    return .error s!"{desc}: expected failure, got success"
  catch e =>
    let msg := toString e
    let missing := needles.filter (!hasSubstr msg ·)
    if missing.isEmpty then
      return .ok ()
    else
      return .error s!"{desc}: error missing substrings {missing}\n  got: {msg}"

def main : IO UInt32 := do
  let cases : List (IO (Except String Unit)) := [
    expectOk "builtin theme + no extraCss" { theme := "black" },
    expectOk "builtin theme + unique extraCss"
      { extraCss := #[dummyCss "a.css", dummyCss "b.css"] },
    expectOk "custom theme + unique extraCss"
      { theme := .custom (dummyCss "theme/my.css"),
        extraCss := #[dummyCss "css/a.css"] },
    expectOk "subdir filenames with shared prefix"
      { extraCss := #[dummyCss "a/x.css", dummyCss "b/x.css"] },
    expectOk "custom theme with assets all distinct"
      { theme := .custom (dummyBundle (dummyCss "theme/my.css")
                           #[dummyAsset "theme/logo.png",
                             dummyAsset "theme/fonts/body.woff2"]),
        extraCss := #[dummyCss "css/a.css"] },
    expectOk "duplicate extraCss filename with identical contents is deduped"
      { extraCss := #[dummyCss "a.css" "body", dummyCss "a.css" "body"] },
    expectFail "duplicate extraCss filename with different contents"
      { extraCss := #[dummyCss "a.css" "one", dummyCss "a.css" "two"] },
    expectOk "custom theme and extraCss with matching filename and contents"
      { theme := .custom (dummyCss "shared.css" "body"),
        extraCss := #[dummyCss "shared.css" "body"] },
    expectFail "custom theme collides with extraCss (diverging contents)"
      { theme := .custom (dummyCss "shared.css" "one"),
        extraCss := #[dummyCss "shared.css" "two"] },
    expectFailMentioning
      "error message names filename and both sources (theme vs extraCss)"
      { theme := .custom (dummyCss "shared.css" "one"),
        extraCss := #[dummyCss "shared.css" "two"] }
      ["shared.css", "theme stylesheet", "extraCss"],
    expectFailMentioning
      "error message names filename and both sources (asset vs asset)"
      { theme := .custom (dummyBundle (dummyCss "theme.css")
                           #[dummyAsset "logo.png" "a",
                             dummyAsset "logo.png" "b"]) }
      ["logo.png", "theme asset"],
    expectFailMentioning
      "error message mentions text and binary kinds on text/binary clash"
      { theme := .custom (dummyBundle (dummyCss "theme.css" "body{}")
                           #[dummyAsset "theme.css" "body{}"]) }
      ["theme.css", "text", "binary"],
    expectFail "collision only detected after nested subdir match"
      { theme := .custom (dummyCss "themes/x.css" "one"),
        extraCss := #[dummyCss "themes/x.css" "two"] },
    expectOk "identical binary asset included twice is deduped"
      { theme := .custom (dummyBundle (dummyCss "theme.css")
                           #[dummyAsset "logo.png" "PNG",
                             dummyAsset "logo.png" "PNG"]) },
    expectFail "two assets with same name differ in bytes"
      { theme := .custom (dummyBundle (dummyCss "theme.css")
                           #[dummyAsset "logo.png" "a",
                             dummyAsset "logo.png" "b"]) },
    expectFail "asset (binary) and stylesheet (text) share a name"
      { theme := .custom (dummyBundle (dummyCss "theme.css" "body{}")
                           #[dummyAsset "theme.css" "body{}"]) },
    expectFail "asset clashes with extraCss even when both are text"
      { theme := .custom (dummyBundle (dummyCss "theme.css")
                           #[dummyAsset "shared.css"]),
        extraCss := #[dummyCss "shared.css"] }
  ]
  let mut failed := 0
  for run in cases do
    match ← run with
    | .ok () => pure ()
    | .error msg => IO.eprintln msg; failed := failed + 1
  if failed == 0 then
    IO.println s!"All {cases.length} validation cases passed."
    return 0
  else
    IO.eprintln s!"{failed} validation case(s) FAILED."
    return 1
