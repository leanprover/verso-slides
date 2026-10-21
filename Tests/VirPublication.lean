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

private def expectFailure (action : IO α) : IO Unit := do
  let rejected ← try action *> pure false catch _ => pure true
  check rejected "expected rejection"

private def tests (dir : System.FilePath) : IO Unit := do
  -- Exercise the real renderer's ordinary asset writer. Publication writes in
  -- place, preserves unrelated/stale files, and is not whole-site transactional.
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
  expectFailure (VersoSlides.slidesMain { config with
    outputDir := blocked, extraCss := #[forbidden] } doc)
  check (!(← blocked.pathExists)) "asset collision wrote output"
  let html ← IO.FS.readFile (config.outputDir / "index.html")
  for (key, expected) in [("data-runtime-module", builtin.runtimeModule),
      ("data-runtime-manifest", builtin.runtimeManifest), ("data-program-manifest", builtin.programManifests[0]!)] do
    check ((html.splitOn s!"{key}=\"{expected}\"").length == 2)
      s!"bootstrap changed the library-owned {key} path"
  check (!(← (config.outputDir / "vir-bootstrap.js").pathExists)) "external bootstrap was emitted"
  check (!(← (config.outputDir / "lib/.vir-stage").pathExists)) "staging directory was emitted"
  IO.FS.writeFile (config.outputDir / "lib/vir/stale") "keep stale"
  IO.FS.writeFile (config.outputDir / "unrelated") "keep unrelated"
  check ((← VersoSlides.slidesMain config doc) == 0) "repeat render failed"
  check ((← IO.FS.readFile (config.outputDir / "lib/vir/stale")) == "keep stale") "stale policy changed"
  check ((← IO.FS.readFile (config.outputDir / "unrelated")) == "keep unrelated") "unrelated file changed"

  -- An ordinary output error can leave index/vendor files written. Fixing the
  -- destination and rerunning must complete the inventory without a private stage.
  let broken := dir / "partial"
  IO.FS.createDirAll (broken / "lib")
  IO.FS.writeFile (broken / "lib/vir") "not a directory"
  let rejected ← try
    let _ ← VersoSlides.slidesMain { config with outputDir := broken } doc
    pure false
  catch _ => pure true
  check rejected "invalid resource output did not fail"
  check ((← IO.FS.readFile (broken / "lib/vir")) == "not a directory") "invalid output file was modified"
  IO.FS.removeFile (broken / "lib/vir")
  check ((← VersoSlides.slidesMain { config with outputDir := broken } doc) == 0) "recovery render failed"
  for file in builtin.files do
    check ((← IO.FS.readBinFile (broken / file.path)) == file.bytes) "recovery inventory differs"

public def main : IO UInt32 := IO.FS.withTempDir fun dir => do
  tests dir
  IO.println "Ordinary publication tests passed."
  return 0
