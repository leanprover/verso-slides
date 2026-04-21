/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/
module
public import VersoSlides.Basic

set_option doc.verso true

namespace VersoSlides

/--
Converts a {name}`SlideMetadata` to an array of {lit}`data-*` HTML attributes for a {lit}`<section>`
element. The {name}`vertical` field is consumed by the section-to-slide mapping logic and not
rendered.
-/
public def SlideMetadata.toAttrs (m : SlideMetadata) : Array (String × String) := Id.run do
  let mut attrs : Array (String × String) := #[]
  if let some v := m.transition then
    attrs := attrs.push ("data-transition", v)
  if let some v := m.transitionSpeed then
    attrs := attrs.push ("data-transition-speed", v)
  if let some v := m.backgroundColor then
    attrs := attrs.push ("data-background-color", v)
  if let some v := m.backgroundImage then
    attrs := attrs.push ("data-background-image", v)
  if let some v := m.backgroundSize then
    attrs := attrs.push ("data-background-size", v)
  if let some v := m.backgroundPosition then
    attrs := attrs.push ("data-background-position", v)
  if let some v := m.backgroundRepeat then
    attrs := attrs.push ("data-background-repeat", v)
  if let some v := m.backgroundOpacity then
    attrs := attrs.push ("data-background-opacity", toString v)
  if let some v := m.backgroundVideo then
    attrs := attrs.push ("data-background-video", v)
  if let some v := m.backgroundVideoLoop then
    attrs := attrs.push ("data-background-video-loop", if v then "true" else "false")
  if let some v := m.backgroundVideoMuted then
    attrs := attrs.push ("data-background-video-muted", if v then "true" else "false")
  if let some v := m.backgroundIframe then
    attrs := attrs.push ("data-background-iframe", v)
  if let some v := m.autoAnimate then
    if v then attrs := attrs.push ("data-auto-animate", "")
  if let some v := m.autoAnimateId then
    attrs := attrs.push ("data-auto-animate-id", v)
  if let some v := m.autoAnimateEasing then
    attrs := attrs.push ("data-auto-animate-easing", v)
  if let some v := m.autoAnimateDuration then
    attrs := attrs.push ("data-auto-animate-duration", toString v)
  if let some v := m.autoAnimateUnmatched then
    if !v then attrs := attrs.push ("data-auto-animate-unmatched", "false")
  if m.autoAnimateRestart == some true then
    attrs := attrs.push ("data-auto-animate-restart", "")
  if let some v := m.backgroundGradient then
    attrs := attrs.push ("data-background-gradient", v)
  if let some v := m.backgroundTransition then
    attrs := attrs.push ("data-background-transition", v)
  if let some v := m.backgroundInteractive then
    if v then attrs := attrs.push ("data-background-interactive", "")
  if let some v := m.timing then
    attrs := attrs.push ("data-timing", toString v)
  if let some v := m.visibility then
    attrs := attrs.push ("data-visibility", v)
  if let some v := m.state then
    attrs := attrs.push ("data-state", v)
  if let some v := m.autoSlide then
    attrs := attrs.push ("data-autoslide", toString v)
  attrs

/-- Returns the `data-*` attributes for a section, given optional metadata. -/
public def sectionAttrs (metadata : Option SlideMetadata) : Array (String × String) :=
  match metadata with
  | none => #[]
  | some m => m.toAttrs
