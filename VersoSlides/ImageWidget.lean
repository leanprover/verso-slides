/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
import Lean.Widget
public import Lean.CoreM
set_option doc.verso true

open Lean Widget

namespace VersoSlides

private def base64Table : Array Char :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toList.toArray

/-- Encodes a {name}`ByteArray` as a Base64 string. -/
public def base64Encode (data : ByteArray) : String := Id.run do
  let enc (n : UInt8) : Char := base64Table[n.toNat]!
  let mut out := ""
  let len := data.size
  let mut i := 0
  while h : i + 2 < len do
    let a := data[i]; let b := data[i+1]; let c := data[i+2]
    out := out.push (enc (a >>> 2))
    out := out.push (enc (((a &&& 3) <<< 4) ||| (b >>> 4)))
    out := out.push (enc (((b &&& 15) <<< 2) ||| (c >>> 6)))
    out := out.push (enc (c &&& 63))
    i := i + 3
  if h : i + 1 = len then
    let a := data[i]
    out := out.push (enc (a >>> 2))
    out := out.push (enc ((a &&& 3) <<< 4))
    out := out ++ "=="
  else if h : i + 2 = len then
    let a := data[i]; let b := data[i+1]
    out := out.push (enc (a >>> 2))
    out := out.push (enc (((a &&& 3) <<< 4) ||| (b >>> 4)))
    out := out.push (enc ((b &&& 15) <<< 2))
    out := out ++ "="
  return out

@[widget_module]
def imagePreviewWidget : Widget.Module where
  javascript := include_str "../widget/image-preview.js"

/-- Returns a MIME type for common image extensions, or {name}`none` for unknown types. -/
public def mimeType (path : System.FilePath) : Option String :=
  match path.extension.map (·.toLower) with
  | some "svg" => some "image/svg+xml"
  | some "png" => some "image/png"
  | some "jpg" | some "jpeg" => some "image/jpeg"
  | some "gif" => some "image/gif"
  | some "webp" => some "image/webp"
  | _ => none

/-- Builds a data URI for an image file. Returns {name}`none` if the MIME type is unknown. -/
public def mkDataUri (path : System.FilePath) : IO (Option String) := do
  let some mime := mimeType path
    | return none
  let data ← IO.FS.readBinFile path
  return some s!"data:{mime};base64,{base64Encode data}"

/--
Saves image preview widget info for a local file.
Reads the file and encodes it as a data URI.
-/
public def saveLocalImagePreview (path : String) (alt : String) : CoreM Unit := do
  let some dataUri ← mkDataUri path
    | return  -- unknown MIME type, skip widget
  let props : Json := json%{"src": $dataUri, "alt": $alt}
  savePanelWidgetInfo imagePreviewWidget.javascriptHash.val (pure props) (← getRef)

/--
Saves image preview widget info for a remote URL.
-/
public def saveRemoteImagePreview (url : String) (alt : String) : CoreM Unit := do
  let props : Json := json%{"src": $url, "alt": $alt}
  savePanelWidgetInfo imagePreviewWidget.javascriptHash.val (pure props) (← getRef)
