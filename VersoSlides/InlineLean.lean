/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

import VersoSlides.Basic
import VersoSlides.SlideCode.Export
import VersoManual.InlineLean
import Verso.Code.Highlighted
import Verso.Doc.Helpers

open Lean Elab
open Verso Doc Elab
open Verso.Genre.Manual.InlineLean (LeanBlockConfig LeanInlineConfig)
open SubVerso.Highlighting (Highlighted hlToExport highlight highlightIncludingUnparsed highlightMessage)
open Verso.SyntaxUtils (strLitInputContext parseStrLitAsCategory)
open Verso.Genre.Manual.InlineLean (reportMessages firstToken? saveOutputs)
open Verso.Genre.Manual.InlineLean.Scopes (getScopes setScopes runWithOpenDecls runWithVariables)
open Verso (withoutAsync)
open Lean.Doc.Syntax

namespace VersoSlides

/-- Syntax node kinds whose output should be rendered inline after the command. -/
private def queryCommandKinds : Array SyntaxNodeKind :=
  open Lean.Parser.Command in
  #[``eval, ``check, ``print, ``reduceCmd]

/--
Returns `true` if `stx` contains a query command (e.g. `#eval`, `#check`)
anywhere in its syntax tree, accounting for wrappers like `open ... in`.
-/
private def isQueryCommand (stx : Syntax) : Bool :=
  (stx.find? (queryCommandKinds.contains ·.getKind)).isSome

/-- Token strings for query commands (used to find them in `Highlighted` trees). -/
private def queryCommandTokens : Array String := #["#check", "#eval", "#print", "#reduce"]

/-- Returns `true` if `hl` contains a query command keyword token anywhere in its tree. -/
private partial def containsQueryToken : Highlighted → Bool
  | .token tok => tok.kind matches .keyword .. && queryCommandTokens.contains tok.content
  | .seq xs => xs.any containsQueryToken
  | .span _ x | .tactics _ _ _ x => containsQueryToken x
  | _ => false

/--
For a query command's highlighted code, find spans that contain a query command
token and collect their info-severity messages as `point` nodes to append.
The original tree is left intact (spans keep their info for diagnostic markers).
-/
private partial def collectQueryOutput : Highlighted → Array Highlighted
  | .span info x =>
    if containsQueryToken x then
      info.filterMap fun (kind, msg) =>
        if kind == .info then some (.point kind msg) else none
    else
      collectQueryOutput x
  | .seq xs => xs.foldl (init := #[]) fun acc x => acc ++ collectQueryOutput x
  | .tactics _ _ _ x => collectQueryOutput x
  | _ => #[]

/-- Slides-specific code block configuration, extending {name}`LeanBlockConfig` with a panel toggle. -/
private structure SlidesLeanBlockConfig extends LeanBlockConfig where
  panel : Bool

instance : Verso.ArgParse.FromArgs SlidesLeanBlockConfig DocElabM where
  fromArgs := SlidesLeanBlockConfig.mk <$> Verso.ArgParse.fromArgs <*> .flag `panel true

/-- Callback for `elabCommands`: produces a `Block.other (BlockExt.slideCode ...)` term. -/
private def toSlidesHighlightedBlock (panel shouldShow : Bool) (hls : Highlighted)
    (str : StrLit) : DocElabM Term := do
  if !shouldShow then
    return ← ``(Verso.Doc.Block.concat #[])

  -- De-indent based on column position of the code fence
  let col? := (← getRef).getPos? |>.map (← getFileMap).utf8PosToLspPos |>.map (·.character)
  let hls := match col? with
    | .none => hls
    | .some col => hls.deIndent col

  match fragmentize hls.trim with
  | .ok sc =>
    let exported := scToExport sc
    ``(Verso.Doc.Block.other (VersoSlides.BlockExt.slideCode $(quote exported) $(quote panel)) #[Verso.Doc.Block.code $(quote str.getString)])
  | .error msg =>
    throwErrorAt str.raw msg

/-- Callback for `elabCommands`: produces an `Inline.other (InlineExt.slideCode ...)` term. -/
private def toSlidesHighlightedInline (shouldShow : Bool) (hls : Highlighted) (str : StrLit) :
    DocElabM Term := do
  if !shouldShow then
    return ← ``(Verso.Doc.Inline.concat #[])

  match fragmentize hls.trim with
  | .ok sc =>
    let exported := scToExport sc
    ``(Verso.Doc.Inline.other (VersoSlides.InlineExt.slideCode $(quote exported)) #[Verso.Doc.Inline.code $(quote str.getString)])
  | .error msg =>
    throwErrorAt str.raw msg

/-- Abbreviate a string to the first line, truncated to `width` characters. -/
private def abbrevFirstLine (width : Nat) (str : String) : String :=
  let str := str.trimAsciiStart
  let short := str.take width |>.replace "\n" "⏎"
  if short.toSlice == str then short else short ++ "…"

/--
Fork of `Verso.Genre.Manual.InlineLean.elabCommands` that passes `collectFormat := true`
to `highlightIncludingUnparsed`, enabling format data collection for reflowable rendering.
-/
def elabCommandsWithFormat (config : LeanBlockConfig) (str : StrLit)
    (toHighlightedLeanContent : (shouldShow : Bool) → (hls : Highlighted) → (str: StrLit) → DocElabM Term)
    (minCommands : Option Nat := none)
    (maxCommands : Option Nat := none) :
    DocElabM Term :=
  withoutAsync <| do
    PointOfInterest.save (← getRef) ((config.name.map (·.toString)).getD (abbrevFirstLine 20 str.getString))
      (kind := Lsp.SymbolKind.file)
      (detail? := some ("Lean code" ++ config.outlineMeta))

    let col? := (← getRef).getPos? |>.map (← getFileMap).utf8PosToLspPos |>.map (·.character)

    let origScopes ← if config.fresh then pure [{header := ""}] else getScopes

    let origScopes := origScopes.modifyHead fun sc =>
      { sc with opts := pp.tagAppFns.set (Elab.async.set sc.opts false) true }

    let text ← getFileMap
    let (ictx, startPos) ← strLitInputContext str.raw (← getFileName)
    let cctx : Command.Context := { fileName := ← getFileName, fileMap := text, snap? := none, cancelTk? := none}

    let mut cmdState : Command.State := {env := ← getEnv, maxRecDepth := ← MonadRecDepth.getMaxRecDepth, scopes := origScopes}
    let mut pstate := {pos := startPos, recovering := false, hasLeading := false}
    let mut cmds : Array Syntax := #[]

    -- Check whether whitespace (including comments) consumes the entire block content.
    -- If so, there are no commands to parse. We synthesize an EOI node that preserves
    -- any comments as leading whitespace so they still appear in the highlighted output.
    let scope := cmdState.scopes.head!
    let pmctx := { env := cmdState.env, options := scope.opts, currNamespace := scope.currNamespace, openDecls := scope.openDecls }
    let wsState := Parser.whitespace.run ictx pmctx (Parser.getTokenTable cmdState.env)
      { cache := Parser.initCacheForInput ictx.inputString, pos := startPos }

    if ictx.atEnd wsState.pos then
      -- This is equivalent to mkEOI in Lean.Parser.Module
      let leading := ictx.substring startPos wsState.pos
      let emptyAt := ictx.substring wsState.pos wsState.pos
      let atom := Syntax.atom (.original leading wsState.pos emptyAt wsState.pos) ""
      cmds := cmds.push (mkNode ``Lean.Parser.Command.eoi #[atom])
    else
      repeat
        let scope := cmdState.scopes.head!
        let pmctx := { env := cmdState.env, options := scope.opts, currNamespace := scope.currNamespace, openDecls := scope.openDecls }
        let (cmd, ps', messages) := Parser.parseCommand ictx pmctx pstate cmdState.messages
        cmds := cmds.push cmd
        pstate := ps'
        cmdState := { cmdState with messages := messages }

        if Parser.isTerminalCommand cmd then break

        let savedMsgs := cmdState.messages
        let savedTrees := cmdState.infoState.trees
        cmdState ← withInfoTreeContext (mkInfoTree := pure ∘ InfoTree.node (.ofCommandInfo {elaborator := `Manual.Meta.lean, stx := cmd})) <|
          runCommand (Command.elabCommandTopLevel cmd) cmd cctx cmdState
        cmdState := { cmdState with
          messages := savedMsgs ++ cmdState.messages,
          infoState := { cmdState.infoState with trees := savedTrees ++ cmdState.infoState.trees }
        }

    let nonTerm := cmds.filter (! Parser.isTerminalCommand ·)
    if let some maxCmds := maxCommands then
      if h : nonTerm.size > maxCmds then
        logErrorAt nonTerm.back m!"Expected at most {maxCmds} commands, but got {nonTerm.size} commands."

    if let some minCmds := minCommands then
      if h : nonTerm.size < minCmds then
        let blame := nonTerm[0]? |>.getD (← getRef)
        logErrorAt blame m!"Expected at least {minCmds} commands, but got {nonTerm.size} commands."

    let origEnv ← getEnv
    try
      setEnv cmdState.env
      setScopes cmdState.scopes

      for t in cmdState.infoState.trees do
        pushInfoTree t

      let mut hls := Highlighted.empty
      let nonSilentMsgs := cmdState.messages.toArray.filter (!·.isSilent)
      let mut lastPos : String.Pos.Raw := startPos
      for cmd in cmds do
        let cmdHl ← highlightIncludingUnparsed cmd nonSilentMsgs cmdState.infoState.trees (startPos? := lastPos) (collectFormat := true)
        lastPos := (cmd.getTrailingTailPos?).getD lastPos
        -- For query commands (#eval, #check, etc.), extract output messages from
        -- the highlighted spans and place them as point nodes after the command.
        hls := hls ++ cmdHl
        if isQueryCommand cmd then
          for p in collectQueryOutput cmdHl do
            hls := hls ++ p

      toHighlightedLeanContent config.show hls str
    finally
      if !config.keep then
        setEnv origEnv

      if let some name := config.name then
        let nonSilentMsgs := cmdState.messages.toList.filter (!·.isSilent)
        let msgs ← nonSilentMsgs.mapM fun (msg : Message) => do
          let head := if msg.caption != "" then msg.caption ++ ":\n" else ""
          let msg ← highlightMessage msg
          pure { msg with contents := .append #[.text head, msg.contents] }

        saveOutputs name msgs

      reportMessages (if config.error then some true else none) str cmdState.messages

      if config.show then
        Verso.Genre.Manual.warnLongLines col? str
where
  runCommand (act : Command.CommandElabM Unit) (stx : Syntax)
      (cctx : Command.Context) (cmdState : Command.State) :
      DocElabM Command.State := do
    let (output, cmdState) ←
      match (← liftM <| IO.FS.withIsolatedStreams <| EIO.toIO' <| (act.run cctx).run cmdState) with
      | (output, .error e) => logError e.toMessageData; pure (output, cmdState)
      | (output, .ok ((), cmdState)) => pure (output, cmdState)

    if output.trimAscii.isEmpty then return cmdState

    let log : MessageData → Command.CommandElabM Unit :=
      if let some tok := firstToken? stx then logInfoAt tok
      else logInfo

    match (← liftM <| EIO.toIO' <| ((log output).run cctx).run cmdState) with
    | .error _ => pure cmdState
    | .ok ((), cmdState) => pure cmdState

/-- Elaborated Lean code block for slides (with format data collection). -/
@[code_block]
def lean : CodeBlockExpanderOf SlidesLeanBlockConfig
  | config, str => elabCommandsWithFormat config.toLeanBlockConfig str (toSlidesHighlightedBlock config.panel)

/-- Inline elaborated Lean command for slides (with format data collection). -/
@[role]
def leanCommand : RoleExpanderOf LeanBlockConfig
  | config, inls => do
    if let some str ← oneCodeStr? inls then
      elabCommandsWithFormat config str toSlidesHighlightedInline (minCommands := some 1) (maxCommands := some 1)
    else
      `(sorry)

/-- Inline elaborated Lean term for slides (with format data collection). -/
@[role lean]
def leanInline : RoleExpanderOf LeanInlineConfig
  | config, inlines => withoutAsync do
    let #[arg] := inlines
      | throwError "Expected exactly one argument"
    let `(inline|code( $term:str )) := arg
      | throwErrorAt arg "Expected code literal with the example name"
    let leveller :=
      if let some us := config.universes then
        let us :=
          us.getString.splitOn " " |>.filterMap fun (s : String) =>
            if s.isEmpty then none else some s.toName
        Elab.Term.withLevelNames us
      else id

    let stx ← parseStrLitAsCategory `term term

    let (newMsgs, type, tree) ← do
      let initMsgs ← Core.getMessageLog
      try
        Core.resetMessageLog
        let (tree', t) ← runWithOpenDecls <| runWithVariables fun _ => do

          let expectedType ← config.type.mapM fun (s : StrLit) => do
            match Parser.runParserCategory (← getEnv) `term s.getString (← getFileName) with
            | .error e => throwErrorAt term e
            | .ok stx => withEnableInfoTree false do
              let t ← leveller <| Elab.Term.elabType stx
              Term.synthesizeSyntheticMVarsNoPostponing
              let t ← instantiateMVars t
              if t.hasExprMVar || t.hasLevelMVar then
                throwErrorAt s "Type contains metavariables: {t}"
              pure t

          let e ← leveller <| Elab.Term.elabTerm (catchExPostpone := true) stx expectedType
          Term.synthesizeSyntheticMVarsNoPostponing
          let e ← Term.levelMVarToParam (← instantiateMVars e)
          let t ← Meta.inferType e >>= instantiateMVars >>= (Meta.ppExpr ·)
          let t := Std.Format.group <| (← Meta.ppExpr e) ++ (" :" ++ .line) ++ t

          Term.synthesizeSyntheticMVarsNoPostponing
          let ctx := PartialContextInfo.commandCtx {
            env := ← getEnv, fileMap := ← getFileMap, mctx := ← getMCtx, currNamespace := ← getCurrNamespace,
            openDecls := ← getOpenDecls, options := ← getOptions, ngen := ← getNGen
          }
          pure <| (InfoTree.context ctx (.node (Info.ofCommandInfo ⟨`VersoSlides.leanInline, arg⟩) (← getInfoState).trees), t)
        pure (← Core.getMessageLog, t, tree')
      finally
        Core.setMessageLog initMsgs

    if let some name := config.name then
      let msgs ← newMsgs.toList.mapM fun (msg : Message) => do
        let head := if msg.caption != "" then msg.caption ++ ":\n" else ""
        let msg ← highlightMessage msg
        pure { msg with contents := .append #[.text head, msg.contents] }
      saveOutputs name msgs

    pushInfoTree tree

    if let `(inline|role{%$s $f $_*}%$e[$_*]) ← getRef then
      Verso.Hover.addCustomHover (mkNullNode #[s, e]) type
      Verso.Hover.addCustomHover f type

    reportMessages (if config.error then some true else none) term newMsgs

    let hls := (← highlight stx newMsgs.toArray (PersistentArray.empty.push tree) (collectFormat := true))

    toSlidesHighlightedInline config.show hls term

/-- Configuration for the `name` role. -/
private structure NameConfig where
  full : Option Name

section
open Verso.ArgParse
variable [Monad m] [MonadError m] [MonadLiftT CoreM m] [MonadLiftT TermElabM m]

private def NameConfig.parse : ArgParse m NameConfig :=
  NameConfig.mk <$> ((fun _ => none) <$> .done <|> .positional `name ref)
where
  ref : ValDesc m (Option Name) := {
    description := "reference name"
    signature := .Ident
    get := fun
      | .name x =>
        try
          let resolved ← liftM (runWithOpenDecls (runWithVariables fun _ => realizeGlobalConstNoOverloadWithInfo x))
          return some resolved
        catch
          | .error ref e => throwErrorAt ref e
          | _ => return none
      | other => throwError "Expected reference name, got {repr other}"
  }

instance : FromArgs NameConfig m := ⟨NameConfig.parse⟩
end

/-- Create a highlighted token for a resolved constant name. -/
private def constTok [Monad m] [MonadEnv m] [MonadLiftT MetaM m] [MonadLiftT IO m]
    (resolvedName : Name) (str : String) :
    m Highlighted := do
  let docs ← findDocString? (← getEnv) resolvedName
  let sig := toString (← (PrettyPrinter.ppSignature resolvedName)).1
  pure <| .token ⟨.const resolvedName sig docs false none, str⟩

/--
`name` role: refers to a Lean name (constant) without fully elaborating.
Resolves the name in the current environment, producing a highlighted token
with signature and docstring hover info.

Usage: `{name}[List.map]` or `{name List.map'}[map']`
-/
@[role]
def name : RoleExpanderOf NameConfig
  | cfg, #[arg] => do
    let `(inline|code( $nameStx:str )) := arg
      | throwErrorAt arg "Expected code literal with the example name"
    let exampleName := nameStx.getString.toName
    let identStx := mkIdentFrom arg (cfg.full.getD exampleName) (canonical := true)

    try
      let resolvedName ←
        runWithOpenDecls <| runWithVariables fun _ =>
          withInfoTreeContext (mkInfoTree := pure ∘ InfoTree.node (.ofCommandInfo {elaborator := `VersoSlides.name, stx := identStx})) do
            realizeGlobalConstNoOverloadWithInfo identStx

      let hl : Highlighted ← constTok resolvedName nameStx.getString
      let exported := hlToExport hl

      ``(Verso.Doc.Inline.other (VersoSlides.InlineExt.name $(quote exported)) #[Verso.Doc.Inline.code $(quote nameStx.getString)])
    catch e =>
      logErrorAt identStx e.toMessageData
      ``(Verso.Doc.Inline.code $(quote nameStx.getString))
  | _, more =>
    if h : more.size > 0 then
      throwErrorAt more[0] "Unexpected contents"
    else
      throwError "Unexpected arguments"
