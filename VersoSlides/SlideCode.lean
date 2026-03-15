/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import SubVerso.Highlighting.Highlighted
public import VersoSlides.SlideCode.CommentParsers

set_option doc.verso true

open SubVerso.Highlighting Highlighted

/-!
Intermediate representation for slide code rendering.

Transforms {name}`Highlighted` trees from SubVerso into  trees that embed fragment boundaries, click
targets, and command output for `reveal.js` progressive code reveal.
-/




namespace VersoSlides

/-- Intermediate representation for slide code with fragment/click annotations -/
public inductive SlideCode where
  | hl (content : Highlighted)
  | seq (parts : Array SlideCode)
  | tactics (info : Array (Goal Highlighted)) (startPos endPos : Nat) (content : SlideCode)
  | span (info : Array (Span.Kind × MessageContents Highlighted)) (content : SlideCode)
  | fragment (wrapper : FragmentData) (isBlock : Bool) (content : SlideCode)
  | click (target : SlideCode) (index : Option Nat)
  | commandOutput (info : Array (Span.Kind × MessageContents Highlighted))
deriving BEq, Repr, Inhabited

namespace SlideCode

/-- Empty {name}`SlideCode` node. -/
public def empty : SlideCode := .seq #[]

/-- Returns {name}`true` if a {name}`SlideCode` would render as empty. -/
public partial def isEmpty : SlideCode → Bool
  | .hl h => h.isEmpty
  | .seq parts => parts.all isEmpty
  | _ => false

/-- Appends two {name}`SlideCode` values, with simplifications. -/
public partial def append (a b : SlideCode) : SlideCode :=
  if a.isEmpty then b
  else if b.isEmpty then a
  else match a, b with
  | .seq xs, .seq ys => .seq (xs ++ ys)
  | .seq xs, y => .seq (xs.push y)
  | x, .seq ys => .seq (#[x] ++ ys)
  | x, y => .seq #[x, y]

public instance : Append SlideCode where
  append := SlideCode.append

/--
Normalizes a {name}`SlideCode` tree for test comparisons.

{open SlideCode}
{given -show}`a : Highlighted, b : Highlighted`

1. Flattens nested {lean}`seq`
2. Pushes {name}`hl` down through {name}`seq`:
  {lean type:="SlideCode"}`.hl (.seq #[a, b])` → {lean type:="SlideCode"}`.seq #[.hl a, .hl b]`
-/
public partial def normalize : SlideCode → SlideCode
  | .hl (.seq parts) =>
    (SlideCode.seq (parts.map (normalize ∘ .hl))).normalize
  | .hl h => .hl h
  | .seq parts =>
    let parts := parts.map normalize
    let parts := parts.foldl (fun acc p =>
      match p with
      | .seq inner => acc ++ inner
      | other => acc.push other) #[]
    if h : parts.size = 1 then parts[0] else SlideCode.seq parts
  | .tactics info s e content => .tactics info s e content.normalize
  | .span info content => .span info content.normalize
  | .fragment w b content => .fragment w b content.normalize
  | .click target idx => .click target.normalize idx
  | .commandOutput info => .commandOutput info

end SlideCode


private inductive HlCtx where
  | tactics (info : Array (Goal Highlighted)) (startPos endPos : Nat)
  | span (info : Array (Span.Kind × MessageContents Highlighted))

private structure Hl where
  here : SlideCode
  context : Array (SlideCode × HlCtx)
deriving Inhabited

private def Hl.empty : Hl where
  here := .seq #[]
  context := #[]

private def Hl.close (hl : Hl) : Hl :=
  match hl.context.back? with
  | none => hl
  | some (left, .tactics info s e) => { hl with
    here := left ++ .tactics info s e hl.here
    context := hl.context.pop
  }
  | some (left, .span info) => { hl with
    here := left ++ .span info hl.here
    context := hl.context.pop
  }

private def Hl.open (ctx : HlCtx) (hl : Hl) : Hl where
  here := .seq #[]
  context := hl.context.push (hl.here, ctx)

private def Hl.toSlideCode (hl : Hl) : SlideCode :=
  hl.context.foldr (init := hl.here) fun
    | (left, .tactics info s e), h => left ++ .tactics info s e h
    | (left, .span info), h => left ++ .span info h

private def Hl.push (hl : Hl) (sc : SlideCode) : Hl :=
  { hl with here := hl.here ++ sc }


private structure InlineFragInfo where
  hl : Hl
  wrapper : FragmentData
deriving Inhabited

private structure LineFragInfo where
  hl : Hl
  wrappers : Array FragmentData
deriving Inhabited

private structure FragState where
  doc : Hl
  pendingFragments : Array FragmentData
  activeLineFragment : Option LineFragInfo
  openInlineFragments : Array InlineFragInfo
  pendingCommandOutput : Option (Array (Span.Kind × MessageContents Highlighted))
  insideQuerySpan : Bool
  hideDepth : Nat := 0


/--
Splits a string into lines, keeping the newline character with each line.
A trailing non-newline segment is included as the last element.
-/
private def getLines (str : String) := str.splitInclusive '\n'

/-- Finds the character index of the last occurrence of a character in a string. -/
private def lastCharIndexOf (s : String) (c : Char) : Option Nat := Id.run do
  let mut result : Option Nat := none
  let mut i := 0
  for ch in s do
    if ch == c then result := some i
    i := i + 1
  return result

private def splitString (s : String) (atChar : Nat) : String.Slice × String.Slice := Id.run do
  let mut pos := s.startPos
  let mut n := atChar
  while h : n > 0 ∧ pos ≠ s.endPos do
    pos := pos.next h.2
    n := n - 1
  (s.sliceTo pos, s.sliceFrom pos)

private def charSlice (s : String) (start stop : Nat) : String.Slice := Id.run do
  let mut startPos := s.startPos
  let mut n := start
  while h : n > 0 ∧ startPos ≠ s.endPos do
    startPos := startPos.next h.2
    n := n - 1
  n := stop - start
  let mut stopPos := startPos
  while h : n > 0 ∧ stopPos ≠ s.endPos do
    stopPos := stopPos.next h.2
    n := n - 1
  if h : startPos ≤ stopPos then
    s.slice startPos stopPos h
  else s.slice stopPos startPos (by grind)


/--
Finds the first occurrence of {name}`needle` in {name}`haystack`, returning the character offset.
-/
private def findSubstr (haystack needle : String) : Option Nat := Id.run do
  let mut slice := haystack.toSlice
  let mut ch := 0
  while !slice.isEmpty do
    if slice.startsWith needle then return some ch
    slice := slice.drop 1
    ch := ch + 1
  return none

/-- Known “query commands” whose output is rendered inline. -/
private def queryCommands : Array String := #["#check", "#eval", "#print", "#reduce"]

/--
Finds the last newline in a {name}`SlideCode` and splits into (before-including-newline, after-newline).
Returns {name}`none` if no newline is found.
-/
private partial def splitAtLastNewline (sc : SlideCode) : Option (SlideCode × SlideCode) :=
  match sc with
  | .seq parts =>
    if parts.isEmpty then none
    else
      let rec go (i : Nat) : Option (SlideCode × SlideCode) :=
        if i >= parts.size then none
        else
          let idx := parts.size - 1 - i
          match splitAtLastNewline parts[idx]! with
          | some (before, after) =>
            let pre := SlideCode.seq (parts.extract 0 idx |>.push before)
            let post := SlideCode.seq (#[after] ++ parts.extract (idx + 1) parts.size)
            some (pre, post)
          | none => go (i + 1)
      go 0
  | .hl (.text s) =>
    if let some nlIdx := lastCharIndexOf s '\n' then
      let (before, after) := splitString s (nlIdx + 1)
      let afterS := after.copy
      some (.hl (.text before.copy), if afterS.isEmpty then .seq #[] else .hl (.text afterS))
    else none
  | .hl (.unparsed s) =>
    if let some nlIdx := lastCharIndexOf s '\n' then
      let (before, after) := splitString s (nlIdx + 1)
      let afterS := after.copy
      some (.hl (.unparsed before.copy), if afterS.isEmpty then .seq #[] else .hl (.unparsed afterS))
    else none
  | .hl (.seq parts) =>
    splitAtLastNewline (SlideCode.seq (parts.map .hl))
  | .tactics info s e content =>
    match splitAtLastNewline content with
    | some (before, after) => some (.tactics info s e before, .tactics info s e after)
    | none => none
  | .span info content =>
    match splitAtLastNewline content with
    | some (before, after) => some (.span info before, .span info after)
    | none => none
  | _ => none

/-- Result of trying to wrap a node at a given column. -/
private inductive WrapResult where
  | wrapped (sc : SlideCode)
  | notFound (consumed : Nat)
deriving Inhabited

/--
Walks forward through a line of {name}`SlideCode`, counting columns, and wraps the deepest
node at the target column in a {name (full := SlideCode.click)}`click` node.
-/
private partial def wrapAtCol (sc : SlideCode) (targetCol : Nat) (index : Option Nat) : WrapResult :=
  match sc with
  | .seq parts =>
    Id.run do
      let mut col := 0
      for i in [:parts.size] do
        if col > targetCol then return .notFound col
        match wrapAtCol parts[i]! (targetCol - col) index with
        | .wrapped sc' =>
          let newParts := parts.extract 0 i ++ #[sc'] ++ parts.extract (i + 1) parts.size
          return .wrapped (SlideCode.seq newParts)
        | .notFound consumed =>
          col := col + consumed
      return .notFound col
  | .hl (.text s) => .notFound s.length
  | .hl (.unparsed s) => .notFound s.length
  | .hl (.token tok) =>
    if tok.content.length > targetCol then
      .wrapped (.click (.hl (.token tok)) index)
    else
      .notFound tok.content.length
  | .hl (.seq parts) =>
    wrapAtCol (SlideCode.seq (parts.map .hl)) targetCol index
  | .hl (.point ..) => .notFound 0
  | .hl (.tactics info s e content) =>
    wrapAtCol (.tactics info s e (.hl content)) targetCol index
  | .hl (.span info content) =>
    wrapAtCol (.span info (.hl content)) targetCol index
  | .tactics _info _ _ content =>
    match wrapAtCol content targetCol index with
    | .wrapped _ =>
      -- Wrap the entire tactics node, not just the inner hit
      .wrapped (.click sc index)
    | .notFound consumed =>
      -- A caret anywhere within or just past the tactic extent hits the tactic
      if consumed > 0 && consumed >= targetCol then
        .wrapped (.click sc index)
      else
        .notFound consumed
  | .span info content =>
    match wrapAtCol content targetCol index with
    | .wrapped inner => .wrapped (.span info inner)
    | .notFound consumed =>
      if consumed > targetCol then
        .wrapped (.click sc index)
      else
        .notFound consumed
  | .fragment w b content =>
    match wrapAtCol content targetCol index with
    | .wrapped inner => .wrapped (.fragment w b inner)
    | .notFound consumed => .notFound consumed
  | .click target idx =>
    match wrapAtCol target targetCol index with
    | .wrapped inner => .wrapped (.click inner idx)
    | .notFound consumed => .notFound consumed
  | .commandOutput _ => .notFound 0

/--
Strips the trailing newline character from a {name}`SlideCode` tree.
-/
private partial def stripTrailingNewline (sc : SlideCode) : Option (SlideCode × SlideCode) :=
  match sc with
  | .seq parts =>
    if parts.isEmpty then none
    else match stripTrailingNewline parts.back! with
    | some (stripped, nl) =>
      if stripped.isEmpty then some (.seq parts.pop, nl)
      else some (.seq (parts.pop.push stripped), nl)
    | none => none
  | .hl (.unparsed s) =>
    if let some pre := s.dropSuffix? "\n" then
      let preS := pre.toString
      some (if preS.isEmpty then .seq #[] else .hl (.unparsed preS), .hl (.unparsed "\n"))
    else none
  | .hl (.text s) =>
    if let some pre := s.dropSuffix? "\n" then
      let preS := pre.toString
      some (if preS.isEmpty then .seq #[] else .hl (.text preS), .hl (.text "\n"))
    else none
  | .hl (.seq parts) => stripTrailingNewline (.seq (parts.map .hl))
  | _ => none

/-- Tries to wrap a click at a given column on a line. Returns error message on failure. -/
private def tryWrapClick (line : SlideCode) (caretCol : Nat) (index : Option Nat)
    : Except String SlideCode := do
  match wrapAtCol line caretCol index with
  | .wrapped wrapped => return wrapped
  | .notFound consumed =>
    if consumed <= caretCol then
      throw s!"!click caret at column {caretCol} is beyond end of preceding line (length {consumed})"
    else
      throw s!"!click found no clickable node at column {caretCol}"

/-- Resolves a `-- ^ !click` against accumulated content. -/
private partial def resolveClick (doc : Hl) (caretCol : Nat) (index : Option Nat) : Except String Hl := do
  match splitAtLastNewline doc.here with
  | none => throw "!click with no preceding line"
  | some (beforeLine, lastLine) =>
    match wrapAtCol lastLine caretCol index with
    | .wrapped wrapped =>
      return { doc with here := beforeLine ++ wrapped }
    | .notFound consumed =>
      if consumed == 0 then
        -- Empty line after last \n (bare newline pushed separately).
        -- Strip trailing \n from beforeLine to find actual code line.
        match stripTrailingNewline beforeLine with
        | none => throw "!click with no preceding line"
        | some (stripped, nlNode) =>
          let suffix := nlNode ++ lastLine
          match splitAtLastNewline stripped with
          | none =>
            let wrapped ← tryWrapClick stripped caretCol index
            return { doc with here := wrapped ++ suffix }
          | some (before2, lineContent) =>
            let wrapped ← tryWrapClick lineContent caretCol index
            return { doc with here := before2 ++ wrapped ++ suffix }
      else if consumed <= caretCol then
        throw s!"!click caret at column {caretCol} is beyond end of preceding line (length {consumed})"
      else
        throw s!"!click found no clickable node at column {caretCol}"

/-- Wraps content in nested fragment wrappers. Outermost = first (index 0). -/
private def applyPendingFragments (pending : Array FragmentData) (sc : SlideCode) : SlideCode :=
  pending.foldr (init := sc) fun w acc => .fragment w true acc

/-- Closes the active line-level fragment, wrapping its content and pushing to doc. -/
private def FragState.closeActiveLine (st : FragState) : FragState :=
  match st.activeLineFragment with
  | none => st
  | some lf =>
    let content := lf.hl.toSlideCode
    let wrapped := applyPendingFragments lf.wrappers content
    { st with
      doc := st.doc.push wrapped
      activeLineFragment := none
      openInlineFragments := st.openInlineFragments.map fun fi =>
        InlineFragInfo.mk (fi.hl.push wrapped) fi.wrapper
    }

/--
Pushes a {name}`SlideCode` node to the current accumulator.
Priority: innermost inline fragment > active line fragment > pending activation > doc.
-/
private def FragState.pushSC (st : FragState) (sc : SlideCode) : FragState :=
  if st.hideDepth > 0 then st
  else if !st.openInlineFragments.isEmpty then
    -- Route to innermost inline fragment only
    let fis := st.openInlineFragments
    let last := fis.back!
    { st with openInlineFragments := fis.pop.push { last with hl := last.hl.push sc } }
  else if let some lf := st.activeLineFragment then
    { st with activeLineFragment := some { lf with hl := lf.hl.push sc } }
  else if !st.pendingFragments.isEmpty then
    { st with
      activeLineFragment := some { hl := Hl.empty.push sc, wrappers := st.pendingFragments }
      pendingFragments := #[]
    }
  else
    { st with doc := st.doc.push sc }

/--
Opens a structural context ({name}`tactics`/{name}`span`) on the current accumulator.
Activates a line fragment if {name}`pendingFragments` is non-empty.
-/
private def FragState.openCtx (st : FragState) (ctx : HlCtx) : FragState :=
  if let some lf := st.activeLineFragment then
    { st with activeLineFragment := some { lf with hl := lf.hl.open ctx } }
  else if !st.pendingFragments.isEmpty then
    { st with
      activeLineFragment := some { hl := Hl.empty.open ctx, wrappers := st.pendingFragments }
      pendingFragments := #[]
    }
  else
    { st with doc := st.doc.open ctx }

/--
Closes a structural context. If the active line fragment has no open contexts,
closes it first (the context was opened on doc), then closes on doc.
-/
private def FragState.closeCtx (st : FragState) : FragState :=
  match st.activeLineFragment with
  | some lf =>
    if lf.hl.context.isEmpty then
      let st := st.closeActiveLine
      { st with doc := st.doc.close }
    else
      { st with activeLineFragment := some { lf with hl := lf.hl.close } }
  | none =>
    { st with doc := st.doc.close }

/-- Resolves a click comment against the current accumulator (line fragment or doc). -/
private def FragState.resolveClickOnCurrent (st : FragState) (caretCol : Nat) (index : Option Nat)
    : Except String FragState := do
  match st.activeLineFragment with
  | some lf =>
    let resolved ← resolveClick lf.hl caretCol index
    return { st with activeLineFragment := some { lf with hl := resolved } }
  | none =>
    let resolved ← resolveClick st.doc caretCol index
    return { st with doc := resolved }

/-- Gets the current context stack (from line fragment or doc). -/
private def FragState.currentContext (st : FragState) : Array (SlideCode × HlCtx) :=
  match st.activeLineFragment with
  | some lf => lf.hl.context
  | none => st.doc.context

/-- The kind of inline marker comment found in a text scan. -/
private inductive InlineMarkerKind where
  | fragmentStart
  | fragmentEnd
  | hideStart
  | hideEnd
  | replaceStart
  | replaceEnd

/-- A segment from splitting around inline marker comments. -/
private inductive TextSegment where
  | plain (text : String)
  | inlineStart (wrapper : FragmentData)
  | inlineEnd
  | hideStart
  | hideEnd
  | replaceStart (text : String)
  | replaceEnd

/-- Parses inline fragment wrapper arguments. -/
private def parseInlineWrapper (s : String) : FragmentData :=
  if s.isEmpty then { style := none, index := none }
  else
    let parts := (s.splitOn " ").filter fun p => !p.isEmpty
    match parts with
    | [x] =>
      if x.all Char.isDigit then { style := none, index := x.toNat? }
      else { style := some x, index := none }
    | [style, idx] => { style := some style, index := idx.toNat? }
    | _ => { style := some s, index := none }

private def sliceStartsWithWs (s : String.Slice) : Bool :=
  s.startsWith Char.isWhitespace

private def skipWs (probe : String.Slice) (probeLen : Nat) : String.Slice × Nat := Id.run do
  let mut probe := probe
  let mut probeLen := probeLen
  while sliceStartsWithWs probe do
    probe := probe.drop 1
    probeLen := probeLen + 1
  return (probe, probeLen)

/--
Scans for the first inline marker comment in a string. Matches the comment opener followed by at
least one whitespace then a {lit}`!`-prefixed keyword. Returns the marker kind, the start character
offset, and the after-marker character offset. For fragment start markers, the after-marker offset
points past {lit}`!fragment` (the caller scans to the comment closer separately, since fragment
start markers can carry arguments).
-/
private def findInlineMarker (haystack : String) : Option (InlineMarkerKind × Nat × Nat) := Id.run do
  let mut slice := haystack.toSlice
  let mut ch := 0
  while !slice.isEmpty do
    if slice.startsWith "/-" then
      let (probe, probeLen) := skipWs (slice.drop 2) 2
      -- Require at least one whitespace after the comment open
      if probeLen > 2 then
        -- Check for !fragment (start marker — does not consume to comment close)
        if probe.startsWith "!fragment" then
          return some (.fragmentStart, ch, ch + probeLen + "!fragment".length)
        -- Check for !hide ... closing comment
        if probe.startsWith "!hide" then
          let (probe, probeLen) := skipWs (probe.drop 5) (probeLen + 5)
          if probe.startsWith "-/" then
            return some (.hideStart, ch, ch + probeLen + 2)
        -- Check for !replace (start marker — does not consume to comment close)
        if probe.startsWith "!replace" then
          return some (.replaceStart, ch, ch + probeLen + "!replace".length)
        -- Check for !end (fragment | hide | replace) ... closing comment
        if probe.startsWith "!end" then
          let afterEnd := probeLen + 4
          let (probe, probeLen) := skipWs (probe.drop 4) afterEnd
          if probeLen > afterEnd then  -- had at least one ws after !end
            if probe.startsWith "fragment" then
              let (probe, probeLen) := skipWs (probe.drop 8) (probeLen + 8)
              if probe.startsWith "-/" then
                return some (.fragmentEnd, ch, ch + probeLen + 2)
            if probe.startsWith "hide" then
              let (probe, probeLen) := skipWs (probe.drop 4) (probeLen + 4)
              if probe.startsWith "-/" then
                return some (.hideEnd, ch, ch + probeLen + 2)
            if probe.startsWith "replace" then
              let (probe, probeLen) := skipWs (probe.drop 7) (probeLen + 7)
              if probe.startsWith "-/" then
                return some (.replaceEnd, ch, ch + probeLen + 2)
    slice := slice.drop 1
    ch := ch + 1
  return none

/-- Splits a string around inline marker comments (fragment and hide). -/
private partial def splitInlineMarkers (s : String) : Array TextSegment :=
  go s #[]
where
  processStartMarker (remaining : String) (si afterKw : Nat) (acc : Array TextSegment) :
      Array TextSegment × String :=
    let acc := if si > 0 then acc.push (.plain (remaining.take si).copy) else acc
    match findSubstr (charSlice remaining afterKw remaining.length).copy "-/" with
    | some closeOff =>
      let markerContent := charSlice remaining afterKw (afterKw + closeOff)
      let wrapper := parseInlineWrapper markerContent.trimAscii.toString
      (acc.push (.inlineStart wrapper), charSlice remaining (afterKw + closeOff + 2) remaining.length |>.copy)
    | none =>
      (acc.push (.plain remaining), "")

  processReplaceMarker (remaining : String) (si afterKw : Nat) (acc : Array TextSegment) :
      Array TextSegment × String :=
    let acc := if si > 0 then acc.push (.plain (remaining.take si).copy) else acc
    match findSubstr (charSlice remaining afterKw remaining.length).copy "-/" with
    | some closeOff =>
      let text := (charSlice remaining afterKw (afterKw + closeOff)).trimAscii.toString
      (acc.push (.replaceStart text), charSlice remaining (afterKw + closeOff + 2) remaining.length |>.copy)
    | none =>
      (acc.push (.plain remaining), "")

  emitAt (remaining : String) (offset afterEnd : Nat) (seg : TextSegment)
      (acc : Array TextSegment) : Array TextSegment × String :=
    let acc := if offset > 0 then acc.push (.plain (charSlice remaining 0 offset).copy) else acc
    (acc.push seg, (charSlice remaining afterEnd remaining.length).copy)

  go (remaining : String) (acc : Array TextSegment) : Array TextSegment :=
    if remaining.isEmpty then acc
    else
      match findInlineMarker remaining with
      | none => acc.push (.plain remaining)
      | some (.fragmentStart, offset, afterKw) =>
        let (acc, remaining) := processStartMarker remaining offset afterKw acc
        go remaining acc
      | some (.fragmentEnd, offset, afterEnd) =>
        let (acc, remaining) := emitAt remaining offset afterEnd .inlineEnd acc
        go remaining acc
      | some (.hideStart, offset, afterEnd) =>
        let (acc, remaining) := emitAt remaining offset afterEnd .hideStart acc
        go remaining acc
      | some (.hideEnd, offset, afterEnd) =>
        let (acc, remaining) := emitAt remaining offset afterEnd .hideEnd acc
        go remaining acc
      | some (.replaceStart, offset, afterKw) =>
        let (acc, remaining) := processReplaceMarker remaining offset afterKw acc
        go remaining acc
      | some (.replaceEnd, offset, afterEnd) =>
        let (acc, remaining) := emitAt remaining offset afterEnd .replaceEnd acc
        go remaining acc

/-- Processes plain text lines for line-level magic comments. -/
private def processPlainLines (st : FragState) (s : String) (isText : Bool) : Except String FragState := do
  let mkLeaf := fun (content : String) =>
    if isText then SlideCode.hl (.text content) else SlideCode.hl (.unparsed content)
  let lines := getLines s
  -- Fast path: no magic comments → push entire text as one node
  let hasMagic := lines.any fun line =>
    (parseFragmentBreak line).isSome || (parseClickComment line).isSome
  if !hasMagic then
    return st.pushSC (mkLeaf s)
  -- Slow path: process line by line
  let mut st := st
  for line in lines do
    if let some w := parseFragmentBreak line then
      if !st.openInlineFragments.isEmpty then
        throw "-- !fragment (line-level break) inside an open /- !fragment -/ region"
      st := st.closeActiveLine
      st := { st with pendingFragments := st.pendingFragments.push w }
    else if let some (caretCol, index) := parseClickComment line then
      st ← st.resolveClickOnCurrent caretCol index
    else
      if let some cmdInfo := st.pendingCommandOutput then
        if line == "\n" || (line.startsWith Char.isWhitespace) then
          st := st.pushSC (.commandOutput cmdInfo)
          st := { st with pendingCommandOutput := none }

      st := st.pushSC (mkLeaf line.toString)
  return st

/-- Processes a single text segment (from inline marker splitting). -/
private def processSegment (st : FragState) (seg : TextSegment) (isText : Bool) : Except String FragState :=
  match seg with
  | .plain txt => processPlainLines st txt isText
  | .inlineStart wrapper =>
    .ok { st with
      openInlineFragments := st.openInlineFragments.push {
        hl := { here := .seq #[], context := st.currentContext.map fun (_, ctx) => (.seq #[], ctx) }
        wrapper := wrapper
      }
    }
  | .inlineEnd =>
    if st.openInlineFragments.isEmpty then
      .error "/- !end fragment -/ without matching /- !fragment -/"
    else
      let fi := st.openInlineFragments.back!
      let st := { st with openInlineFragments := st.openInlineFragments.pop }
      let content := fi.hl.toSlideCode
      let fragNode := SlideCode.fragment fi.wrapper false content
      .ok (st.pushSC fragNode)
  | .hideStart =>
    .ok { st with hideDepth := st.hideDepth + 1 }
  | .hideEnd =>
    if st.hideDepth == 0 then
      .error "/- !end hide -/ without matching /- !hide -/"
    else
      .ok { st with hideDepth := st.hideDepth - 1 }
  | .replaceStart replacement =>
    let st := st.pushSC (.hl (.unparsed replacement))
    .ok { st with hideDepth := st.hideDepth + 1 }
  | .replaceEnd =>
    if st.hideDepth == 0 then
      .error "/- !end replace -/ without matching /- !replace -/"
    else
      .ok { st with hideDepth := st.hideDepth - 1 }

/--
Processes a {name}`text` or {name}`unparsed` node, scanning for inline fragment markers
and then line-level magic comments.
-/
private def processTextNode (st : FragState) (s : String) (isText : Bool) : Except String FragState :=
  (splitInlineMarkers s).foldlM (init := st) fun acc seg => processSegment acc seg isText

/-- Finds the first {name}`span` context in a context stack (searching from top). -/
private def findSpanInfo (ctxStack : Array HlCtx) : Option (Array (Span.Kind × MessageContents Highlighted)) :=
  ctxStack.reverse.findSome? fun
    | .span info => some info
    | _ => none

/-- Main worklist loop for the fragmentize transformation. -/
private partial def fragmentizeLoop
    (todo : List (Option Highlighted))
    (ctxStack : Array HlCtx)
    (querySpanStack : Array Bool)
    (st : FragState) : Except String FragState := do
  match todo with
  | [] => return st
  | none :: rest =>
    let st := st.closeCtx
    let querySpanStack := if !querySpanStack.isEmpty then querySpanStack.pop else querySpanStack
    let st := { st with insideQuerySpan := if querySpanStack.isEmpty then false else querySpanStack.back! }
    fragmentizeLoop rest ctxStack.pop querySpanStack st
  | some (.seq xs) :: rest =>
    fragmentizeLoop (xs.toList.map some ++ rest) ctxStack querySpanStack st
  | some (.tactics info s e x) :: rest =>
    let st := st.openCtx (.tactics info s e)
    fragmentizeLoop (some x :: none :: rest) (ctxStack.push (.tactics info s e)) (querySpanStack.push st.insideQuerySpan) st
  | some (.span info x) :: rest =>
    let st := st.openCtx (.span info)
    let st := { st with insideQuerySpan := false }
    fragmentizeLoop (some x :: none :: rest) (ctxStack.push (.span info)) (querySpanStack.push false) st
  | some (.token tok) :: rest =>
    let mut qss := querySpanStack
    let mut s := st
    if tok.kind matches .keyword .. then
      if queryCommands.contains tok.content then
        if !qss.isEmpty then
          qss := qss.pop.push true
          s := { s with insideQuerySpan := true }
          if let some info := findSpanInfo ctxStack then
            s := { s with pendingCommandOutput := some info }
    s := s.pushSC (SlideCode.hl (.token tok))
    fragmentizeLoop rest ctxStack qss s
  | some (.point kind info) :: rest =>
    let st := st.pushSC (SlideCode.hl (.point kind info))
    fragmentizeLoop rest ctxStack querySpanStack st
  | some (.text s) :: rest =>
    let st ← processTextNode st s true
    fragmentizeLoop rest ctxStack querySpanStack st
  | some (.unparsed s) :: rest =>
    let st ← processTextNode st s false
    fragmentizeLoop rest ctxStack querySpanStack st

/--
Transforms a {name}`Highlighted` tree into a {name}`SlideCode` tree, processing magic comments.
-/
public def fragmentize (hl : Highlighted) : Except String SlideCode := do
  let initSt : FragState := {
    doc := .empty
    pendingFragments := #[]
    activeLineFragment := none
    openInlineFragments := #[]
    pendingCommandOutput := none
    insideQuerySpan := false
  }
  let finalSt ← fragmentizeLoop [some hl] #[] #[] initSt
  if !finalSt.openInlineFragments.isEmpty then
    throw "Unclosed inline fragment (/- !fragment -/ without /- !end fragment -/)"
  if finalSt.hideDepth > 0 then
    throw "Unclosed hide or replace region (/- !hide -/ or /- !replace ... -/ without matching end marker)"
  -- Emit any pending command output before closing
  let finalSt := match finalSt.pendingCommandOutput with
    | some info => { finalSt.pushSC (.commandOutput info) with pendingCommandOutput := none }
    | none => finalSt
  let finalSt := finalSt.closeActiveLine
  return finalSt.doc.toSlideCode
