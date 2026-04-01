/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import Lean.Data.Json.FromToJson.Basic

open Lean

namespace VersoSlides

/-- Fragment wrapper metadata: optional CSS style class and optional explicit fragment index. -/
public structure FragmentData where
  style : Option String
  index : Option Nat
deriving BEq, ReflBEq, LawfulBEq, Hashable, Repr, Inhabited, ToJson, FromJson

/--
Parses a line as a `-- !fragment [style] [index]` magic comment.
Returns `none` if the line does not match the pattern.
-/
public def parseFragmentBreak (line : String.Slice) : Option FragmentData := do
  let mut todo := line.dropWhile (· == ' ')
  todo ← todo.dropPrefix? "--"
  todo := todo.dropWhile (· == ' ')
  todo ← todo.dropPrefix? "!fragment"
  if todo.startsWith (·.isAlpha) then failure
  todo := todo.dropWhile (· == ' ')
  let style : Option String ←
    if todo.startsWith (fun c => c.isAlpha) then
      let style := todo.takeWhile (fun c => c.isAlpha || c == '-')
      todo := todo.dropWhile (fun c => c.isAlpha || c == '-')
      todo := todo.dropWhile (· == ' ')
      pure <| some style.copy
    else pure none
  let index : Option Nat ←
    if todo.startsWith (fun c => c.isDigit) then
      let index := todo.takeWhile (·.isDigit)
      todo := todo.dropWhile (·.isDigit)
      let index ← index.toNat?
      pure (some index)
    else pure none
  if todo.all (·.isWhitespace) then return { style, index } else failure

/--
Parses a line as a `-- ^ !click [index]` magic comment.
Returns `(caretColumn, optionalIndex)` if the line matches, `none` otherwise.
-/
public def parseClickComment (line : String.Slice) : Option (Nat × Option Nat) := do
  let leading := line.takeWhile (· == ' ')
  let mut todo := line.dropWhile (· == ' ')
  todo ← todo.dropPrefix? "--"
  let spaces := todo.takeWhile (· == ' ')
  todo := todo.dropWhile (· == ' ')
  todo ← todo.dropPrefix? "^"
  if todo.startsWith (· == '^') then failure
  let caretCol := leading.positions.length + 2 + spaces.positions.length
  todo := todo.dropWhile (· == ' ')
  todo ← todo.dropPrefix? "!click"
  if todo.startsWith (·.isAlpha) then failure
  todo := todo.dropWhile (·.isWhitespace)
  let index : Option Nat ←
    if todo.startsWith (·.isDigit) then
      let digits := todo.takeWhile (·.isDigit)
      todo := todo.dropWhile (·.isDigit)
      let index ← digits.toNat?
      pure (some index)
    else pure none
  if todo.all (·.isWhitespace) then return (caretCol, index) else failure
