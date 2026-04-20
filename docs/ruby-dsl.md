# Ruby DSL

[← Main](index.md) · [pipe-operator](pipe-operator.md) · [components](components.md) · [documents](documents.md)

## Quick Start

```ruby
require 'nodex'
include Nodex::DSL

page = document("My Page",
  head: [stylesheet("/style.css")],
  body: [
    div(class: "hero") {
      h1("Hello").bold.color("#333")
      p "Built with Nodex"
    }
  ]
)

puts page.to_html
page.to_docx("output.docx", preset: :report)
```

## DSL Mixin

```ruby
extend Nodex::DSL  # h1(), div(), Bold() etc. available without Nodex. prefix
```

## Block DSL

Zero-arity blocks use `instance_eval` — element calls auto-append to parent:

```ruby
div(class: "card", style: {padding: "20px"}) {
  h2 "Title"
  p  "Body text"
  ul {
    li "Item 1"
    li "Item 2"
  }
}
```

One-arg blocks yield the raw Node (backward compatible):

```ruby
div { |n| n.append(h1("Title")) }
```

Custom helpers work inside blocks via `method_missing` delegation:

```ruby
def card(title:, body:)
  div(class: "card") { h3 title; p body }
end

div(class: "grid") {
  card title: "Fast",   body: "Zero deps"
  card title: "Pretty", body: "Pipe DSL"
}
```

## Elements

### Text

| Method | HTML |
|--------|------|
| `h1(text)` — `h6(text)` | `<h1>` — `<h6>` |
| `p(text)` | `<p>` |
| `strong(text)`, `em(text)` | `<strong>`, `<em>` |
| `code(text)`, `pre(text)` | `<code>`, `<pre>` |
| `span_elem(text)` | `<span>` |

### Containers

All accept `children`, `**attrs`, `&block`:

| Method | HTML |
|--------|------|
| `div`, `section`, `article`, `nav` | `<div>`, `<section>`, etc. |
| `header`, `footer`, `main_elem`, `aside` | `<header>`, `<footer>`, etc. |
| `vbox(children)` | flex column |
| `hbox(children)` | flex row |

### Lists

```ruby
ul { li "A"; li "B" }
ol { li "First"; li "Second" }
```

### Tables

```ruby
table {
  tr { th "Name"; th "Value" }
  tr { td "Alpha"; td "100" }
}
```

### Forms

| Method | HTML |
|--------|------|
| `form(children)` | `<form>` |
| `input_elem(type, **attrs)` | `<input>` |
| `button(label)`, `label(content)` | `<button>`, `<label>` |
| `textarea(content)`, `select_elem(options)` | `<textarea>`, `<select>` |

### Links & Media

```ruby
a("GitHub", href: "https://github.com")
img("/photo.png", alt: "Photo")
```

### Math

```ruby
math("x^2 + y^2 = z^2")                      # inline
math_block("\\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}")  # display

# Add KaTeX to page head for rendering:
document("Math", head: katex_head, body: [...])
```

### Special

| Method | Description |
|--------|-------------|
| `br()`, `hr()` | line break, horizontal rule |
| `page_break()` | page break (for DOCX/PDF) |
| `fragment { ... }` | returns Array of siblings (no wrapper) |
| `raw(html)` | raw HTML, no escaping |
| `text(content)` | text node |

## Factory kwargs

Special kwargs are routed to proper Node fields:

```ruby
div(class: "card", id: "main", style: {padding: "20px", color: "red"})
div(data: {controller: "tabs", action: "click"})  # → data-controller="tabs"
button("Save", hx: {post: "/api", target: "#out"}) # → hx-post="/api"
```

## Chainable Methods

All return `self` for chaining:

```ruby
h1("Title").bold.italic.color("#333").font_size("2rem").center
```

Categories:
- **Typography**: `bold`, `italic`, `underline`, `strikethrough`, `font_size(s)`, `font_family(f)`, `letter_spacing(s)`, `line_height(h)`, `text_transform(t)`
- **Color**: `color(c)`, `bg_color(c)`
- **Layout**: `center`, `padding(v)`, `margin(v)`, `gap(g)`, `flex_wrap`, `flex_grow`, `justify_content(jc)`, `align_items(ai)`
- **Sizing**: `width(w)`, `height(h)`, `min_width`, `max_width`, `min_height`, `max_height`
- **Visual**: `border(b)`, `border_radius(r)`, `opacity(v)`, `box_shadow(s)`, `transform(t)`
- **Position**: `position(p)`, `z_index(z)`, `top/right/bottom/left(v)`
- **Attributes**: `set_attr(k, v)`, `set_style(p, v)`, `add_class(c)`, `set_class(c)`, `set_id(id)`, `data(k, v)`
- **HTMX**: `hx_get`, `hx_post`, `hx_target`, `hx_swap`, `hx_trigger`, `hx_push_url`, `hx_vals`, `hx_confirm`

## Pipe Operator

```ruby
h1("text") | Bold() | Color("red") | Padding("10px")
h1("text") | [Bold(), Color("red"), Center()]  # array of decorators
h1("text") | :bold                              # symbol → method call
```

Decorator composition via `Proc#>>`:

```ruby
Headline = Bold() >> FontSize("2rem") >> Color("#333")
h1("Title") | Headline
```

## Named Styles

```ruby
Nodex.define_style(:card, Padding(20) >> BorderRadius(8) >> Border("1px solid #eee"))
div | :card  # applies via pipe
```

## Append Operator

```ruby
container = div
container << h1("Title")
container << p("Body")
```

## Rendering

```ruby
node.to_html                        # HTML string
node.to_json                        # JSON AST
node.to_docx(preset: :gost)        # DOCX bytes (pure Ruby)
node.to_docx("file.docx")          # write to file
node.to_pdf("file.pdf")            # PDF via DOCX→LibreOffice
```

See [documents](documents.md) for DOCX/PDF details.

## Markdown

```ruby
markdown("# Hello\n\n**bold** text")           # → raw HTML node
markdown_node("# Hello\n\ntext with $x^2$")    # → proper Node tree
markdown_file("README.md")                       # from file → raw HTML
markdown_file_node("README.md")                  # from file → Node tree
```

`markdown_node` returns a real Node tree — can be piped, styled, rendered to DOCX/PDF.
Supports `$...$` inline and `$$...$$` display math.
