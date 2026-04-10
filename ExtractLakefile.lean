/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
import Lean
import Lake.DSL
import SubVerso.Compat
import SubVerso.Highlighting.Code
import SubVerso.Module

open SubVerso

open Lean Elab System

/-- Compute the path to Lake's shared library in the toolchain. -/
def lakeSharedLib (sysroot : FilePath) : FilePath :=
  sysroot / "lib" / "lean" / s!"libLake_shared.{Lake.sharedLibExt}"

/-- Returns the node kind of the command, skipping outer `in` nodes. -/
partial def commandKind (cmd : Syntax) : SyntaxNodeKind :=
  match cmd with
  | `(command|$_cmd1 in $cmd2) => commandKind cmd2
  | _ => cmd.getKind

structure Args where
  lakefile : String
  jsonFile : String
  pkgDir : Option String

def processArgs (args : List String) : IO Args := do
  let args := args.toArray
  let mut lakefile? := none
  let mut jsonFile? := none
  let mut pkgDir := none
  let mut i := 0
  while h : i < args.size do
    let this := args[i]
    i := i + 1
    if this.startsWith "-" then
      if this == "--pkg-dir" then
        if h : i < args.size then
          pkgDir := some args[i]
          i := i + 1
        else fail "Expected package dir"
      else fail s!"Unknown option {this}"
    else
      if lakefile?.isNone then lakefile? := some this
      else if jsonFile?.isNone then jsonFile? := some this
      else fail s!"Didn't understand extra positional argument {this}"
  match lakefile?, jsonFile? with
  | some lakefile, some jsonFile => return { lakefile, jsonFile, pkgDir }
  | none, _ => fail "No lakefile provided"
  | _, none => fail "No JSON file provided"
where
  fail {α} (msg : String) : IO α := throw <| .userError msg

unsafe def main (args : List String) : IO UInt32 := do
  let { lakefile, jsonFile, pkgDir } ← processArgs args

  let pkgDir : String := Id.run do
    for i in [:args.length] do
      if args[i]! == "--pkg-dir" then
        return args[i + 1]?.getD "."
    return ((lakefile : FilePath).parent.getD ".").toString


  let sysroot ← findSysroot
  initSearchPath sysroot

  enableInitializersExecution

  -- Load Lake as a plugin so its builtin_initialize functions (DSL macros, etc.) run.
  -- This is the same approach the language server uses for lakefile.lean.
  let lakePlugin := lakeSharedLib sysroot

  let contents ← IO.FS.readFile lakefile
  let ictx := Parser.mkInputContext contents lakefile
  let (headerStx, parserState, msgs) ← Parser.parseHeader ictx
  let imports := headerToImports headerStx

  let env ← importModules imports {}  (plugins := #[lakePlugin]) (trustLevel := 1024) (loadExts := true)
  let pctx : Elab.Frontend.Context := {inputCtx := ictx}

  let commandState : Command.State := { env, maxRecDepth := defaultMaxRecDepth, messages := msgs }
  let scopes :=
    let sc := commandState.scopes[0]!
    {sc with opts := sc.opts.setBool `pp.tagAppFns true } :: commandState.scopes.tail!
  let commandState := { commandState with scopes }
  let cmdPos := parserState.pos
  let cmdSt ← IO.mkRef { commandState, parserState, cmdPos }

  let res ← Compat.Frontend.processCommands headerStx pctx cmdSt

  let infos := (← cmdSt.get).commandState.infoState.trees
  let msgs := Array.flatten (res.items.map (Compat.messageLogArray ·.messages))

  let res := res.updateLeading contents

  let hls ← (Frontend.runCommandElabM <| Command.liftTermElabM <| Highlighting.highlightFrontendResult res) pctx cmdSt

  let items : Array Module.ModuleItem := hls.zip res.syntax |>.map fun (hl, stx) => {
    defines := hl.definedNames.toArray,
    kind := commandKind stx,
    range := stx.getRange?.map fun ⟨s, e⟩ => (ictx.fileMap.toPosition s, ictx.fileMap.toPosition e),
    code := hl
    : Module.ModuleItem
  }

  IO.FS.writeFile jsonFile (toString (Module.Module.mk items).toJson)

  return (0 : UInt32)

  /-
  let input ← IO.FS.readFile lakefilePath
  let inputCtx := Parser.mkInputContext input lakefilePath
  let (_, parserState, messages) ← Parser.parseHeader inputCtx

  let commandState := Command.mkState env messages
  let s ← IO.processCommands inputCtx parserState commandState

  let treeCount := s.commandState.infoState.trees.size
  IO.println s!"Info trees: {treeCount}"
  IO.println s!"Commands: {s.commands.size}"

  let msgs := s.commandState.messages
  IO.println s!"Messages: {msgs.toList.length} (hasErrors: {msgs.hasErrors})"
  for msg in msgs.toList do
    let str ← msg.toString
    IO.println s!"  [{msg.severity}] {str.take 200}"

  return 0
-/
