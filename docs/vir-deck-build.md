# Lean formatting through VIR

Lean owns `Std.Format.prettyM`; VIR executes it. JavaScript converts
Verso's compact format, measures available columns and presents
text/annotations.

```sh
lake build
lake exe demo-slides
python3 -m http.server --directory _slides
```

Downstream decks keep ordinary `slidesMain`/`Config.outputDir`; see
`examples/default-deck`. The existing `VersoSlides` library owns the
formatter, and `VersoSlidesVendored` embeds its assets with VIR's
library-owned runtime:

```lean
lean_lib VersoSlidesVendored where
  needs := #[vendorAssets, `+VersoSlides.VirPrettyM:virResourcePack]
```

```lean
public import Vir.Resources.Assets

public def VersoSlides.VirPrettyMResources.resources : Vir.Resources.ResourceSet :=
  include_vir_assets (modules := #[VersoSlides.VirPrettyM])
```

The Lake dependency prepares the selected module's pack; the Lean
include uses those prepared assets. Keep the preparation dependency
configured. Downstream decks need no registration or generated-path
settings.

VIR prepares resources and supplies files/URLs through
`ResourceSet.forSite`. Slides uses its existing writer. No application
recipe, export list, producer paths, manual manifests or extra
libraries are required. The writer's existing
in-place/stale-file/failure behavior is unchanged.

The full-name call is `VersoSlides.VirPrettyM.formatSegments`:

```text
Std.Format → Nat → Nat → Array Pretty.Segment
```

Generated VIR metadata marshals inputs/results. Scalar inputs go
directly to VIR; tag IDs return as BigInts and use exact decimal
annotation keys. The Lean function preserves the trusted
generated-input model; budgets are deferred.

Initialization runs once. Static slides/navigation remain usable while
selected expressions show loading or failure; readiness renders the
current selection. A rejected request preserves an active program. A
failed runtime closes formatting without retry or a JavaScript
formatter fallback.

The VIR `4.35` tag pins source `225218e1` and selects public Lean
4.35.0 runtime `c9ecb67a` (resource compatibility 6). Its owning
library acquires and verifies the prebuilt runtime during the ordinary
build; applications use the URLs returned by `forSite`. No supplied
pack or Wasm source build is required.

## Tests

```sh
lake test
```

The normal test driver runs native segment tests, Node
presentation/initialization checks and Playwright. The fixture builder
also writes the native corpus for the browser tests, which compare
complete segments and annotation tags with the actual published Wasm
program. No separate site assembly is required.

Use `lake test -- --no-playwright` for the native/Node checks only. To
run just the formatter browser checks after generating the fixtures:

```sh
lake exe test-fixtures-build
uv run --project browser-tests pytest browser-tests/test_vir_prettym_*.py -v
```

The downstream example can be built and rendered independently:

```sh
cd examples/default-deck
lake build
lake exe my-talk
```
