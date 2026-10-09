/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import VersoSlidesVendored
import VersoSlides.Render

open Vir.Resources

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def tests (dir : System.FilePath) : IO Unit := do
  -- Slides must publish the library's bytes and reference those same files.
  let config : VersoSlides.Config := { outputDir := dir / "site" }
  let doc : Verso.Doc.Part VersoSlides.Slides := .mk #[] "publication" none #[] #[]
  check ((← VersoSlides.slidesMain config doc) == 0) "initial render failed"
  let resources := VersoSlides.VirPrettyMResources.resources
  let builtin ← IO.ofExcept <| (resources.forSite "lib/vir").mapError reprStr
  for file in builtin.files do
    check ((← IO.FS.readBinFile (config.outputDir / file.path)) == file.bytes)
      "renderer changed a prepared file"
  -- The existing asset plan catches an exact resource-file collision before writing.
  let blocked := dir / "collision"
  let forbidden : VersoSlides.CssFile := {
    filename := builtin.runtimeModule, contents := ⟨"different contents"⟩ }
  let collision ← try
    let _ ← VersoSlides.slidesMain { config with
      outputDir := blocked, extraCss := #[forbidden] } doc
    pure false
  catch error =>
    pure (error.toString.startsWith "Filename collision in config:")
  check collision "expected an asset filename collision"
  check (!(← blocked.pathExists)) "asset collision wrote output"
  let html ← IO.FS.readFile (config.outputDir / "index.html")
  for (key, expected) in [("data-runtime-module", builtin.runtimeModule),
      ("data-runtime-manifest", builtin.runtimeManifest), ("data-program-manifest", builtin.programManifests[0]!)] do
    check ((html.splitOn s!"{key}=\"{expected}\"").length == 2)
      s!"bootstrap changed the library-owned {key} path"

public def main : IO UInt32 := IO.FS.withTempDir fun dir => do
  tests dir
  IO.println "Ordinary publication tests passed."
  return 0
