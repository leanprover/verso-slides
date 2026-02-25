/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import VersoSlides

/-- Runs a process, printing its output. Returns its exit code. -/
def runCmd (cmd : String) (args : Array String) (desc : String) : IO UInt32 := do
  IO.println s!"[test] {desc}..."
  let result ← IO.Process.output { cmd, args }
  IO.print result.stdout
  IO.eprint result.stderr
  if result.exitCode != 0 then
    IO.eprintln s!"[test] {desc} failed (exit code {result.exitCode})"
  return result.exitCode

def main : IO UInt32 := do
  -- Step 1: generate test fixture slides
  let rc ← runCmd "lake" #["exe", "test-fixtures-build"] "Generating test fixtures"
  if rc != 0 then return rc

  -- Step 2: install Python test dependencies
  let rc ← runCmd "uv" #["sync", "--project", "browser-tests", "--extra", "test"]
    "Installing Python dependencies"
  if rc != 0 then return rc

  -- Step 3: install Playwright browsers
  let rc ← runCmd "uv"
    #["run", "--project", "browser-tests", "--extra", "test",
      "playwright", "install", "--with-deps", "chromium", "firefox"]
    "Installing Playwright browsers"
  if rc != 0 then return rc

  -- Step 4: run pytest
  let rc ← runCmd "uv"
    #["run", "--project", "browser-tests", "--extra", "test",
      "pytest", "browser-tests", "-v"]
    "Running tests"
  return rc
