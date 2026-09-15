/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

module

import VersoSlides
import TestElab

/-- Runs a process, printing its output. Returns its exit code. -/
def runCmd (cmd : String) (args : Array String) (desc : String) : IO UInt32 := do
  IO.println s!"[test] {desc}..."
  let result ← IO.Process.output { cmd, args }
  IO.print result.stdout
  IO.eprint result.stderr
  if result.exitCode != 0 then
    IO.eprintln s!"[test] {desc} failed (exit code {result.exitCode})"
  return result.exitCode

public def main (args : List String) : IO UInt32 := do
  let mut runPlaywright := true
  for arg in args do
    match arg with
    | "--no-playwright" => runPlaywright := false
    | _ =>
      IO.eprintln s!"[test] unknown argument: {arg}"
      return 1

  -- Step 0: Lean-side unit tests that don't require browsers
  let leanTests := #[
    ("test-fragmentize", "Running fragmentize unit tests"),
    ("test-render", "Running rendering unit tests"),
    ("test-comment-parsers", "Running comment-parser unit tests")
  ]
  for (exe, desc) in leanTests do
    let rc ← runCmd "lake" #["exe", exe] desc
    if rc != 0 then return rc

  let rc ← runCmd "lake" #["exe", "test-config-validation"]
    "Running Config.validateFilenames unit tests"
  if rc != 0 then return rc

  -- Step 1: generate test fixture slides
  let rc ← runCmd "lake" #["exe", "test-fixtures-build"] "Generating test fixtures"
  if rc != 0 then return rc

  if !runPlaywright then
    IO.println "[test] Skipping Playwright browser tests (--no-playwright)"
    return 0

  -- Step 2: install Python test dependencies
  let rc ← runCmd "uv" #["sync", "--project", "browser-tests"]
    "Installing Python dependencies"
  if rc != 0 then return rc

  -- Step 3: install Playwright browsers
  let rc ← runCmd "uv"
    #["run", "--project", "browser-tests",
      "playwright", "install", "--with-deps", "chromium", "firefox"]
    "Installing Playwright browsers"
  if rc != 0 then return rc

  -- Step 4: run pytest
  let rc ← runCmd "uv"
    #["run", "--project", "browser-tests",
      "pytest", "browser-tests", "-v"]
    "Running tests"
  return rc
