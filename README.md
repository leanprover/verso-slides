# VersoSlides

VersoSlides is a Verso genre that generates reveal.js slide
presentations from Lean 4 documents. All third-party dependencies
(reveal.js, KaTeX, marked) are vendored and embedded at compile time,
so the generated output works fully offline. The output includes full
support for Verso's elaborated Lean code blocks, including syntax
highlighting and hover-based documentation tooltips.

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
`index.html` and a `lib/` directory with the vendored reveal.js,
KaTeX, and marked assets. To view the presentation, serve the output
directory over HTTP:

```
python3 -m http.server -d _slides
```

You can override the output directory and theme from the command line:

```
lake exe demo-slides --output path/to/dir --theme white
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
in a `%%%` metadata block at the top of the document rather than in
`Main.lean`.

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

## Second Sub-slide

This appears below the first when navigating down.
```

### Slide Metadata

Each slide can carry per-slide metadata in a `%%%` block immediately
after its heading. All fields are optional and fall back to
document-level defaults or reveal.js defaults when omitted. The
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

| Field                   | Type            | reveal.js attribute                                                 |
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

## Directives

Directives are block-level constructs delimited by `:::` fences. They
apply reveal.js features to their content.

### Speaker Notes

The `notes` directive wraps its content in an `<aside class="notes">`
element, which reveal.js displays in the speaker view (opened with the
S key).

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
by reveal.js.

### Fit Text, Stretch, and Frame

Three named directives apply common reveal.js utility classes to their
content.

The `fitText` directive causes reveal.js to scale the text to fill the
slide width. The `stretch` directive causes an element to expand to
fill the remaining vertical space on the slide. The `frame` directive
adds a default styled border around the content.

```
:::fitText
Large heading text
:::
```

### Layout: `stack`, `hstack`, `vstack`

The `stack`, `hstack`, and `vstack` directives wrap their children in
a container `<div>` with the corresponding reveal.js layout class.
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

## Document-Level Configuration

Document-level `reveal.js` settings are specified in a `%%%` metadata
block at the top of the document (before the first `#` heading). These
serve as defaults that individual slides can override through their
own metadata blocks.

```
#doc (Slides) "My Presentation" =>

%%%
theme := some "black"
slideNumber := some true
transition := some "slide"
%%%

# First Slide
...
```

The available document-level fields are `theme`, `transition`,
`width`, `height`, `margin`, `controls`, `progress`, `slideNumber`,
`hash`, `center`, and `navigationMode`. The `--output` and `--theme`
command-line flags can further override the output directory and
theme.

The generated HTML loads the Notes, Highlight, and KaTeX Math plugins
automatically. All plugin assets are vendored and written to the
output directory, so no internet connection is required.
