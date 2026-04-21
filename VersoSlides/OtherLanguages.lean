/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: David Thrane Christiansen
-/

import VersoSlides.Basic
import Verso.Doc.Elab.Monad

/-!
Code block handler for other (non-Lean) languages.

Produces `BlockExt.otherLanguage` blocks whose HTML rendering includes
a `language-*` class so that the bundled `reveal.js` highlight.js plugin
applies syntax highlighting at presentation time.

Usage:
````
```code rust
fn main() { println!("hello"); }
```

```code "c++"
#include <iostream>
int main() { std::cout << "hello"; }
```
````
The language name can be an identifier (`rust`, `python`) or a string
(`"c++"`, `"c#"`).
-/

open Lean Elab
open Verso Doc Elab
open Lean.Doc.Syntax

namespace VersoSlides

/-- A language name parsed from either an identifier or a string literal. -/
private def langName : Verso.ArgParse.ValDesc DocElabM String where
  description := "a language name"
  signature := { ident := true, string := true, num := false }
  get
    | .name x => pure (x.getId.toString (escape := false))
    | .str s => pure s.getString
    | other => throwError "Expected language name (identifier or string), got {repr other}"

/-- Configuration for the `code` block expander: a required language name. -/
private structure CodeConfig where
  language : String

instance : Verso.ArgParse.FromArgs CodeConfig DocElabM where
  fromArgs := CodeConfig.mk <$> .positional `language langName

/--
Uses `reveal.js`'s built-in syntax highlighting for code.
-/
@[code_block]
def code : CodeBlockExpanderOf CodeConfig
  | config, str =>
    ``(Verso.Doc.Block.other (BlockExt.otherLanguage $(quote config.language) $(quote str.getString)) #[])

end VersoSlides
