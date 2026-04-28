# VersoSlides

VersoSlides is a Verso genre that generates `reveal.js` slide
presentations from Lean 4 documents. All third-party dependencies
(`reveal.js`, KaTeX, marked) are vendored and embedded at compile
time, so the generated output works fully offline. The output includes
full support for Verso's elaborated Lean code blocks, including syntax
highlighting and hover-based documentation tooltips.

The [demo slides](./Demo.lean) can be seen at
[this repository's GitHub pages](https://leanprover.github.io/verso-slides/).

## Requirements

VersoSlides requires the Lean 4 toolchain specified in
`lean-toolchain` and pulls Verso as a Lake dependency.

## Building and Running

Build the project with Lake, then run the executable to generate
slides:

```
lake build
lake exe demo-slides
```

The output is written to `_slides/` by default, containing
`index.html` and a `lib/` directory with the vendored `reveal.js`,
KaTeX, and marked assets. To view the presentation, serve the output
directory over HTTP:

```
python3 -m http.server -d _slides
```

## Writing a Presentation

A presentation is a Verso document declared with the `Slides` genre.
The document title becomes the HTML page title. Each top-level heading
(`#`) becomes a horizontal slide, and the content under it forms the
slide body.

```
import VersoSlides
import Verso.Doc.Concrete

open VersoSlides

#doc (Slides) "My Presentation" =>

# First Slide

Content of the first slide.

# Second Slide

Content of the second slide.
```

The document module must be imported in `Main.lean`, where the
`slidesMain` function generates the output. Document-level
configuration (theme, transition style, slide numbering, etc.) is set
on the `Config` passed to `slidesMain` — see
[Document-Level Configuration](#document-level-configuration).

### Vertical Slides

When a top-level section has `vertical := some true` in its metadata
block, its subsections (`##`) become vertical sub-slides arranged in a
column beneath the parent. Without this setting, subsections are
flattened into the parent slide without their own `<section>`
wrappers.

```
# Vertical Group

%%%
vertical := some true
%%%

Content on the first vertical sub-slide.

## Second Sub-Slide

This appears below the first when navigating down.
```

### Slide Metadata

Each slide can carry per-slide metadata in a `%%%` block immediately
after its heading. All fields are optional and fall back to
document-level defaults or `reveal.js` defaults when omitted. The
metadata is written as Lean structure field syntax.

```
# My Slide

%%%
transition := some "zoom"
backgroundColor := some "#2d1b69"
autoAnimate := some true
%%%
```

The available metadata fields are listed below. Each one maps directly
to a `data-*` attribute on the slide's `<section>` element.

| Field                   | Type            | `reveal.js` attribute                                               |
| ----------------------- | --------------- | ------------------------------------------------------------------- |
| `vertical`              | `Option Bool`   | Controls vertical sub-slide grouping (not rendered as an attribute) |
| `transition`            | `Option String` | `data-transition`                                                   |
| `transitionSpeed`       | `Option String` | `data-transition-speed`                                             |
| `backgroundColor`       | `Option String` | `data-background-color`                                             |
| `backgroundImage`       | `Option String` | `data-background-image`                                             |
| `backgroundSize`        | `Option String` | `data-background-size`                                              |
| `backgroundPosition`    | `Option String` | `data-background-position`                                          |
| `backgroundRepeat`      | `Option String` | `data-background-repeat`                                            |
| `backgroundOpacity`     | `Option Float`  | `data-background-opacity`                                           |
| `backgroundVideo`       | `Option String` | `data-background-video`                                             |
| `backgroundVideoLoop`   | `Option Bool`   | `data-background-video-loop`                                        |
| `backgroundVideoMuted`  | `Option Bool`   | `data-background-video-muted`                                       |
| `backgroundIframe`      | `Option String` | `data-background-iframe`                                            |
| `backgroundGradient`    | `Option String` | `data-background-gradient`                                          |
| `backgroundTransition`  | `Option String` | `data-background-transition`                                        |
| `backgroundInteractive` | `Option Bool`   | `data-background-interactive`                                       |
| `autoAnimate`           | `Option Bool`   | `data-auto-animate`                                                 |
| `autoAnimateId`         | `Option String` | `data-auto-animate-id`                                              |
| `autoAnimateEasing`     | `Option String` | `data-auto-animate-easing`                                          |
| `autoAnimateDuration`   | `Option Float`  | `data-auto-animate-duration`                                        |
| `autoAnimateUnmatched`  | `Option Bool`   | `data-auto-animate-unmatched`                                       |
| `autoAnimateRestart`    | `Option Bool`   | `data-auto-animate-restart`                                         |
| `timing`                | `Option Nat`    | `data-timing`                                                       |
| `visibility`            | `Option String` | `data-visibility`                                                   |
| `state`                 | `Option String` | `data-state`                                                        |
| `autoSlide`             | `Option Nat`    | `data-autoslide`                                                    |

## Directives

Directives are block-level constructs delimited by `:::` fences. They
apply `reveal.js` features to their content.

### Speaker Notes

The `notes` directive wraps its content in an `<aside class="notes">`
element, which `reveal.js` displays in the speaker view (opened with
the S key).

```
:::notes
Remember to explain this point carefully.
:::
```

### Fragments

The `fragment` directive makes its content appear incrementally. Each
child block receives the fragment class individually, so a directive
wrapping multiple paragraphs produces multiple independent animation
steps.

An optional positional argument sets the animation style. The style
name is written in camelCase and converted to the corresponding
reveal.js class (for example, `fadeUp` becomes `fade-up`). A named
`index` argument controls the ordering of fragment steps.

```
:::fragment fadeUp (index := 2)
This paragraph fades up at step 2.
:::
```

The built-in animation styles include `fadeUp`, `fadeDown`,
`fadeLeft`, `fadeRight`, `fadeIn`, `fadeOut`, `currentVisible`,
`highlightRed`, `highlightGreen`, `highlightBlue`, and others defined
by `reveal.js`.

### Fit Text, Stretch, and Frame

Three named directives apply common `reveal.js` utility classes to
their content.

The `fitText` directive causes `reveal.js` to scale the text to fill
the slide width. The `stretch` directive causes an element to expand
to fill the remaining vertical space on the slide. The `frame`
directive adds a default styled border around the content.

```
:::fitText
Large heading text
:::
```

### Layout: `stack`, `hstack`, `vstack`

The `stack`, `hstack`, and `vstack` directives wrap their children in
a container `<div>` with the corresponding `reveal.js` layout class.
Unlike the push-down directives described above, these create a
wrapper element around all the content rather than applying attributes
to each child individually.

The `stack` directive stacks elements on top of one another (useful
for layered animations). The `hstack` directive arranges elements
horizontally, and `vstack` arranges them vertically.

```
:::hstack
Left column content.

Right column content.
:::
```

### CSS Classes and IDs

The `class` directive pushes one or more CSS classes onto each child
block. Class names are given as positional string arguments and are
merged with any existing classes on the element.

```
:::class "custom-highlight" "another-class"
This paragraph receives both classes.
:::
```

The `id` directive similarly pushes an `id` attribute onto each child
block. It takes a single positional string argument.

```
:::id "important-paragraph"
This paragraph has the given ID.
:::
```

### Generic Attributes

The `attr` directive pushes arbitrary HTML attributes onto each child
block. Attribute names and values are given as named arguments.
Because Verso's argument parser uses Lean identifier syntax, attribute
names that contain hyphens (such as `data-id`) must be escaped with
guillemets.

```
:::attr («data-id» := "box") (style := "color: red")
This paragraph receives both attributes.
:::
```

This directive is particularly useful for auto-animate element
matching, where paired elements across adjacent slides need matching
`data-id` attributes.

### Tables

The `table` directive renders an HTML `<table>` from a nested list of
lists: each outer list item is a row, and each inner list item is a
cell. All rows must have the same number of cells.

```
:::table +colHeaders +stripedRows +border
*
  * Header A
  * Header B
*
  * Cell A1
  * Cell B1
*
  * Cell A2
  * Cell B2
:::
```

Cell contents are parsed as block content, so inline markup, Lean
code, images, and other directives are allowed inside cells.

All style options are off by default. Boolean flags are written as
`+name` (or `-name` to explicitly disable); `cellGap` takes a named
string argument:

- `+colHeaders` — the first row becomes a `<thead>` whose cells are
  `<th scope="col">`.
- `+rowHeaders` — the first cell of each body row becomes
  `<th scope="row">`.
- `+stripedRows` — alternating body rows receive a tinted background.
- `+stripedCols` — alternating columns receive a tinted background.
  Combined with `+stripedRows` it produces a checkerboard pattern.
- `+rowSeps` — draws horizontal separators between data rows (and
  between a header row and the first body row).
- `+colSeps` — draws vertical separators between data columns (and
  between a row-header column and the first data column).
- `+headerSep` — draws a thicker separator after the header row and/or
  header column.
- `+border` — draws separator lines along the four outer edges.
- `(cellGap := "0.4em 0.6em")` — overrides cell padding. The value is
  passed through unchanged as a CSS `padding` shorthand (one, two, or
  four lengths).

Colors derive from the current slide's text colour via `color-mix()`,
so tables automatically adapt to both light and dark themes. The
underlying custom properties (`--slide-table-stripe-row-a`,
`--slide-table-sep`, `--slide-table-cell-padding`, etc.) can be
overridden in your own CSS for per-presentation restyling.

### Nesting Directives

Directives can be nested by using a longer fence for the outer
directive. The inner directive uses the standard three-colon fence,
and the outer directive uses a fence with more colons to avoid
ambiguity.

```
:::::fitText
:::attr («data-id» := "title")
Scaled and tracked text.
:::
:::::
```

## Inline Roles

Roles are inline constructs written as `{roleName args}[content]`.
They wrap their content in a `<span>` element with the appropriate
attributes.

### Inline Fragments

The `fragment` role wraps inline content in a `<span>` with the
fragment class. Unlike the block directive, the role uses named
arguments for the style and index.

```
This is {fragment (style := highlightRed)}[highlighted] text.
```

### Inline Classes, IDs, and Attributes

The `class`, `id`, and `attr` roles are the inline counterparts of the
corresponding block directives. They wrap their content in a `<span>`
with the specified attributes.

```
This word is {class "custom"}[styled] differently.

This has an {id "target"}[identified span].

This is {attr («data-id» := "word")}[tracked] across slides.
```

## Math

Inline and display math are written with Verso's built-in math syntax
and rendered by KaTeX at page load:

```
Euler's identity: $`e^{i\pi} + 1 = 0`.

$$`\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}`
```

`$`…`$` is inline math and `$$`…`$$` is display math; both bodies are
wrapped in backticks and parsed as LaTeX. KaTeX is vendored, so math
renders fully offline.

### Prelude of Math Macros

Recurring notation can be declared once at the document level by
setting `Config.mathPrelude` to a string of prelude commands in the
math renderer's syntax (KaTeX).

```lean
slidesMain
  { mathPrelude :=
      "\\def\\RR{\\mathbb{R}}\n\\newcommand{\\Hom}[2]{\\mathrm{Hom}(#1, #2)}\n" }
  (%doc MyTalk)
```

After that, `$`…`\RR`…`$` and `$`…`\Hom{A}{B}`…`$` resolve on every
slide. Parse errors in the prelude are logged to the browser console
and do not abort rendering.

## Lean Code Blocks

Fenced code blocks tagged with `lean` are elaborated by the Lean
compiler and rendered with full syntax highlighting and hover
documentation. The code is type-checked at build time, so any errors
are caught before the slides are generated.

````
```lean
def factorial : Nat → Nat
  | 0 => 1
  | n + 1 => (n + 1) * factorial n
```
````

The generated HTML includes the necessary CSS and JavaScript for
Verso's highlighting system.

Instead of hovers, information about code is revealed on click. This
is to allow the presenter to point using the mouse without hover boxes
popping up over content.

### Tips

Use the `-show` flag to include Lean code that is not rendered. This
can set options, define variables, or create helpers:

````
```lean -show
section
set_option pp.all true
variable {α : Type} [ToString α]
```
```lean
#check List α
```
```lean -show
end
```
````

### Progressive Code Reveal

Inside elaborated Lean code blocks, special comments control how code
is revealed incrementally using `reveal.js` fragments. There are three
kinds of control comments: fragment breaks, click targets, and hidden
regions.

#### Fragment Breaks

A line comment of the form `-- !fragment` splits the code block at
that point. Everything from the break to the next break (or the end of
the block) appears as a separate `reveal.js` fragment, so successive
presses of the advance key reveal successive portions of the code.

An optional style name and numeric index may follow the keyword. The
style name is any identifier recognized by `reveal.js` (for example,
`fadeUp`), and the index controls the ordering of animation steps
across the slide.

````
```lean
def f := 1
-- !fragment
def g := 2
-- !fragment fadeUp 3
def h := 3
```
````

#### Click Targets

A line comment of the form `-- ^ !click` marks the token on the
preceding line at the column of the caret (`^`) as a "click target."
When that fragment step is reached, information about the code at that
position is revealed. An optional numeric index controls the ordering.

````
```lean
theorem foo : True := by
  intro n
-- ^ !click
  trivial
```
````

In this example, `intro n` is revealed normally, and then on the next
advance, the token at the caret column on the preceding line (here,
`intro`) receives a click highlight, resulting in the proof state for
`intro n` being revealed.

#### Hidden Regions

Code that should be elaborated but not displayed in the slides can be
wrapped in a hide region. The block comment `/- !hide -/` opens a
hidden region, and `/- !end hide -/` closes it. Everything between the
two markers is type-checked as usual but omitted from the rendered
output. This is useful for auxiliary definitions or imports that the
audience does not need to see.

````
```lean
/- !hide -/
def helper := 42
/- !end hide -/
theorem uses_helper : helper = 42 := rfl
```
````

Hide markers can appear inline (on the same line as code) or on their
own lines. They can also be nested: an inner `/- !hide -/` inside an
already-hidden region increments a depth counter, and the
corresponding `/- !end hide -/` decrements it. Code is only shown once
all hide regions have been closed.

#### Inline Fragment Regions

Block comments of the form `/- !fragment -/` and `/- !end fragment -/`
delimit an inline fragment region within a line. Unlike line-level
fragment breaks, which split the code block vertically, inline
fragment regions wrap a horizontal span of code in a reveal.js
fragment. An optional style name and index may appear between
`!fragment` and the closing `-/`.

````
```lean
def f := /- !fragment -/42/- !end fragment -/
```
````

### Library Code

The `leanLibCode` code block shows the current source of a
declaration, or a line range, from a library the presentation depends
on. The block body contains the expected code from the library, and it
is an error if it does not match.

If the library changes, the block stops matching and Lean offers a
clickable quickfix that replaces the block with the current source. In
line-range mode, when the body still appears in the library at a
different range (because lines were inserted or removed earlier in the
file), Lean additionally offers a quickfix that updates
`(startLine := …) (endLine := …)` to where the body is now. Small
character-level edits within lines (renames, typos) are tolerated when
locating the new range.

````
```leanLibCode MyLib.Foo (decl := MyLib.Foo.bar)
def bar : Nat := 42
```
````

````
```leanLibCode MyLib.Foo (startLine := 10) (endLine := 30)
-- lines 10..30 of MyLib.Foo
```
````

Arguments:

- The first positional argument is the module name.
- `package` — optional. Disambiguates when several packages may
  contain a module with the same name, or when the module is only
  resolvable with a package qualifier.
- `decl` — optional declaration name; extracts the item whose
  declarations include this name.
- `startLine` / `endLine`: optional 1-based inclusive line range;
  must be provided together and cannot combine with `decl`.
- `panel`: a flag that determines whether to show the interactive info panel under the slide
  (default `true`). Disable with `-panel`; re-enable explicitly with `+panel`.

Omitting `decl` and the line range shows the entire module.

#### Wiring up the Lake build

For this to work, the highlighted source code of the library must
be available for the slides to read. The highlighted code can be
built using the `highlighted` facet in Lake. To arrange for Lake
to build this automatically, the slides must declare a `needs`
dependency so Lake builds the facet before elaborating the slides.

In `lakefile.toml`:

```toml
[[lean_lib]]
name = "MySlides"
needs = ["@mypkg/+MyLib.Foo:highlighted"]
```

Or a whole package at once:

```toml
needs = ["@mypkg:highlighted"]
```

In `lakefile.lean`:

```lean
lean_lib MySlides where
  needs := #[`@mypkg/+MyLib.Foo:highlighted]
```

Or for an entire package:

```lean
lean_lib MySlides where
  needs := #[`@mypkg:highlighted]
```

With this declaration, `lake build` on the slides project produces
the highlighted JSON before Lean elaborates `leanLibCode` blocks. If
the facet isn't available, elaboration fails fast with a reminder to
add the `needs` entry. It won't silently trigger a large build while
elaborating the slides.

Lean's own prelude and `Std` modules don't need the `needs` configuration.

## Document-Level Configuration

Document-level `reveal.js` settings live on the `Config` value passed
to `slidesMain` from your `Main.lean`. They correspond to `reveal.js`
[`Reveal.initialize`](https://revealjs.com/config/) options and apply
to the whole presentation. `%%%` blocks on individual slides only
carry per-slide attributes (the table above); doc-level config does
not appear in `%%%` blocks at all.

```
import VersoSlides
import MyPresentation

open VersoSlides

def main : IO UInt32 :=
  slidesMain
    (config := { theme := "white", slideNumber := true,
                 transition := "fade", autoSlide := 5000 })
    (doc := %doc MyPresentation)
```

The available `Config` fields that map to `Reveal.initialize` options
are `theme`, `transition`, `width`, `height`, `margin`, `controls`,
`progress`, `slideNumber`, `hash`, `center`, `navigationMode`,
`autoSlide`, `autoSlideStoppable`, and `autoSlideMethod`. Each one
sets the document-wide default; some have a matching per-slide
override on the slide's `<section>` (see the table above) — for
example, `Config.transition` is the global default but a slide can
override it with `transition := some "zoom"` in its `%%%` block, which
becomes `data-transition="zoom"`.

`Config` also has presentation-level knobs that don't go through
`Reveal.initialize`:

- `extraCss : Array CssFile` — overlay stylesheets, see
  [Custom CSS](#custom-css).
- `extraJs : Array String` — extra `<script src=…>` tags appended to
  the page.
- `outputDir : System.FilePath` — where to write `index.html` and the
  vendored assets. Defaults to `_slides`.

### Auto-Advance

`autoSlide`, `autoSlideStoppable`, and `autoSlideMethod` together
expose the
[`reveal.js` auto-slide feature](https://revealjs.com/auto-slide/).

- `autoSlide : Nat` — auto-advance interval in milliseconds. `0` (the
  default) disables auto-advancing; any positive value advances slides
  every N ms and adds a play/pause control. The matching per-slide
  `autoSlide : Option Nat` field on `SlideMetadata` emits
  `data-autoslide="N"` and overrides the global default for that slide
  only.
- `autoSlideStoppable : Bool` — when `true` (the default),
  auto-sliding pauses as soon as the audience interacts with the deck.
  Set `false` for unattended kiosk-style playback. No per-slide
  override.
- `autoSlideMethod : AutoSlideMethod` — which navigation method
  `reveal.js` calls when auto-sliding advances. `.next` (the default)
  calls `Reveal.navigateNext()` (advance through fragments, then
  horizontal/vertical slides in order); `.right` calls
  `Reveal.right()`; `.down` calls `Reveal.down()`. For anything more
  exotic, `.js "<expr>"` emits the given JavaScript expression
  verbatim — it must evaluate to a function, e.g.
  `() => Reveal.left()`. No per-slide override.

The generated HTML loads the Notes, Highlight, and KaTeX Math plugins
automatically. All plugin assets are vendored and written to the
output directory, so no internet connection is required.

## Themes

The built-in `reveal.js` themes are the ones listed in the
[`reveal.js` themes documentation](https://revealjs.com/themes/), plus
the high-contrast `black-contrast` and `white-contrast` variants.
Select one by setting `theme := "white"` (or any of the other theme
names) on the `Config` you pass to `slidesMain`.

The `theme` field of `Config` is a `Theme` sum type: either
`.builtin name` (one of the bundled themes, selected by name) or
`.custom theme` (a user-supplied `CustomTheme` that fully replaces the
bundled theme). A bare string coerces to `.builtin` automatically, so
`theme := "black"` continues to work, and a bare `CssFile` coerces to
a `CustomTheme` with no bundled assets, so simple cases stay short.

### Writing a Custom Theme

A `reveal.js` theme is just a stylesheet that sets the theme variables
and base rules documented at
[revealjs.com/themes/#creating-a-theme](https://revealjs.com/themes/#creating-a-theme).
To replace the bundled theme, wrap your stylesheet in a `CustomTheme`
and pass it to `Config.theme`:

```
def customRevealTheme : CssFile where
  filename := "theme/my-reveal-theme.css"
  contents := ⟨include_str "my-reveal-theme.css"⟩

def main : IO UInt32 :=
  slidesMain
    (config := { theme := .custom customRevealTheme })
    (doc := %doc MyPresentation)
```

When `theme` is `.custom`, the bundled theme CSS is not written or
linked; the custom file stands on its own. The `filename` may contain
subdirectories (nested directories are created on demand) and is used
verbatim as the `href` of the emitted `<link>` tag.

#### Bundling Theme Assets (Images, Fonts, …)

A `CustomTheme` can carry any number of companion files — typically
anything the stylesheet references by URL — via its `assets` field:

```
structure CustomTheme where
  stylesheet : CssFile
  assets     : Array ThemeAsset := #[]

structure ThemeAsset where
  filename : String
  contents : ByteArray
```

The simplest way to populate `assets` is to drop every file the theme
needs into a single directory and pull the whole tree in at compile
time with Verso's `include_bin_dir`:

```
import VersoUtil.BinFiles

open VersoSlides
open Verso.BinFiles

def customReveal : CustomTheme where
  stylesheet := { filename := "my-theme/theme.css"
                  contents := ⟨include_str "my-theme-source.css"⟩ }
  -- `include_bin_dir "my-theme-assets"` returns an `Array (String ×
  -- ByteArray)` whose strings all start with "my-theme-assets/" — we
  -- feed it straight into `ThemeAsset.fromDir`, so the files land at
  -- the matching paths under the output directory.
  assets := ThemeAsset.fromDir (include_bin_dir "my-theme-assets")
```

Because the stylesheet URL at runtime is `my-theme/theme.css` and the
assets sit at `my-theme-assets/...`, the stylesheet should reference
them as `url("../my-theme-assets/foo.png")` (standard CSS relative-URL
resolution). For a single file, use `include_bin` directly:

```
{ filename := "my-theme/logo.png", contents := include_bin "logo.png" }
```

## Custom CSS

To layer additional CSS on top of a theme — tweaking colors, adding
per-slide utility classes, or overriding individual rules — pass the
`extraCss` field to `slidesMain` via the `config` argument. Each entry
is a `CssFile` carrying a `filename` and the CSS source to write at
that filename. The file is written alongside `index.html` in the
output directory and loaded by a `<link rel="stylesheet">` tag emitted
_after_ the theme, so its rules override the theme's.

Use `include_str` to embed the stylesheet at compile time so the
compiled executable stays self-contained:

```
import VersoSlides
import MyPresentation

open VersoSlides

def myExtraCss : CssFile where
  filename := "custom.css"
  contents := ⟨include_str "custom.css"⟩

def main : IO UInt32 :=
  slidesMain
    (config := { extraCss := #[myExtraCss] })
    (doc := %doc MyPresentation)
```

The `filename` is interpreted relative to the output directory (it may
contain subdirectories, which are created on demand) and is also used
verbatim as the `href` of the emitted link tag. Unlike a custom theme,
`extraCss` is additive: the bundled `reveal.js` theme is still loaded,
and each entry layers on top of it (and on top of each earlier
`extraCss` entry) in declaration order.

## Filename Collisions

`slidesMain` compiles the custom theme's stylesheet, every bundled
asset, and every `extraCss` entry into a single deduplicated write
plan before touching the filesystem:

- If two entries share a filename **and** have identical contents,
  they are merged: the file is written once and linked once. This is
  the expected case when two `include_bin_dir` bundles share a common
  font or logo, or when the same stylesheet is wired in twice from
  different paths.
- If two entries share a filename with **different contents**
  (including a text/binary mismatch, e.g. a stylesheet and a binary
  asset both claiming `theme.css`), `slidesMain` raises an
  `IO.userError` and writes nothing. The error names the offending
  filename and both sources so the conflict is easy to fix.
