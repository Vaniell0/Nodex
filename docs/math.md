# Math Formulas

[← Main](index.md) · [ruby-dsl](ruby-dsl.md) · [documents](documents.md)

## Quick Start

```ruby
require 'nodex'
include Nodex::DSL

doc = div {
  h1 "Quadratic Formula"
  math_block("x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}")
}

doc.to_html   # → KaTeX-compatible HTML
doc.to_docx("formula.docx")  # → native Word equations (OMML)
```

## DSL

### Basic

```ruby
math("x^2 + y^2 = z^2")           # inline
math_block("E = mc^2")             # display (centered)
```

### Helpers

```ruby
frac("a", "b")                     # \frac{a}{b}
frac_display("a+b", "c-d")         # display mode fraction
msqrt("x+1")                       # \sqrt{x+1}
msqrt("x", n: 3)                   # \sqrt[3]{x}
msum("x_i", sub: "i=1", sup: "n")  # \sum_{i=1}^{n} x_i
mint("f(x)dx", sub: "a", sup: "b") # \int_a^b f(x)dx
mprod("a_k", sub: "k=1", sup: "N") # \prod_{k=1}^{N} a_k
```

### String Builders (composable)

Return LaTeX strings for composition — combine freely, then wrap in `math()` or `math_block()`:

```ruby
# Accents
tex_overline("x")          # → \overline{x}
tex_hat("x")               # → \hat{x}
tex_tilde("x")             # → \tilde{x}
tex_vec("x")               # → \vec{x}
tex_dot("x")               # → \dot{x}
tex_bar("x")               # → \bar{x}

# Sub/superscript
tex_sub("x", 1)            # → x_{1}
tex_sup("x", 2)            # → x^{2}

# Structures
tex_frac("a", "b")         # → \frac{a}{b}
tex_sqrt("x+1")            # → \sqrt{x+1}
tex_sqrt("x", n: 3)        # → \sqrt[3]{x}
```

Compose freely:

```ruby
# \overline{x}_{1} — negated variable with subscript
tex_sub(tex_overline("x"), 1)

# \frac{\overline{x}_{1} + x_{2}}{x_{3}}
tex_frac("#{tex_sub(tex_overline("x"), 1)} + #{tex_sub("x", 2)}", tex_sub("x", 3))

# Render as display equation
math_block("f(#{tex_tilde("x")}) = #{tex_sub(tex_overline("x"), 1)} \\lor #{tex_sub("x", 2)}")
```

### Raw LaTeX

Any LaTeX math string works — the OMML converter handles it:

```ruby
math("\\overline{x} \\cdot \\hat{y} + \\vec{z}")
math("\\left( \\frac{a}{b} \\right)^2")
math("\\alpha + \\beta \\leq \\gamma")
```

## Supported LaTeX

### Structures

| LaTeX | Description | Example |
|-------|-------------|---------|
| `\frac{a}{b}` | Fraction | a/b |
| `x^{2}` or `x^2` | Superscript | x squared |
| `x_{i}` or `x_i` | Subscript | x sub i |
| `x_{i}^{n}` | Both sub+sup | x sub i, sup n |
| `\sqrt{x}` | Square root | sqrt(x) |
| `\sqrt[n]{x}` | Nth root | nth root of x |
| `\sum_{i=0}^{n}` | Summation | sum with limits |
| `\prod_{k=1}^{N}` | Product | product with limits |
| `\int_{a}^{b}` | Integral | definite integral |
| `\left( \right)` | Delimiters | auto-sized parens |
| `\overline{x}` | Overline | x bar |
| `\hat{x}`, `\vec{x}`, `\dot{x}`, `\tilde{x}` | Accents | decorated x |
| `\text{word}` | Plain text | text inside formula |
| `{...}` | Grouping | treat as single unit |

### Greek Letters

| Lowercase | | Uppercase | |
|-----------|---|-----------|---|
| `\alpha` α | `\nu` ν | `\Gamma` Γ | `\Xi` Ξ |
| `\beta` β | `\xi` ξ | `\Delta` Δ | `\Pi` Π |
| `\gamma` γ | `\pi` π | `\Theta` Θ | `\Sigma` Σ |
| `\delta` δ | `\rho` ρ | `\Lambda` Λ | `\Phi` Φ |
| `\epsilon` ε | `\sigma` σ | `\Omega` Ω | `\Psi` Ψ |
| `\zeta` ζ | `\tau` τ | | |
| `\eta` η | `\phi` φ | | |
| `\theta` θ | `\chi` χ | | |
| `\iota` ι | `\psi` ψ | | |
| `\kappa` κ | `\omega` ω | | |
| `\lambda` λ | `\mu` μ | | |

### Operators & Symbols

| LaTeX | Symbol | | LaTeX | Symbol |
|-------|--------|---|-------|--------|
| `\pm` | ± | | `\leq` | ≤ |
| `\times` | × | | `\geq` | ≥ |
| `\div` | ÷ | | `\neq` | ≠ |
| `\cdot` | ⋅ | | `\approx` | ≈ |
| `\infty` | ∞ | | `\equiv` | ≡ |
| `\partial` | ∂ | | `\sim` | ∼ |
| `\nabla` | ∇ | | `\propto` | ∝ |
| `\forall` | ∀ | | `\in` | ∈ |
| `\exists` | ∃ | | `\notin` | ∉ |
| `\cup` | ∪ | | `\cap` | ∩ |
| `\subset` | ⊂ | | `\supset` | ⊃ |
| `\wedge` | ∧ | | `\vee` | ∨ |
| `\oplus` | ⊕ | | `\otimes` | ⊗ |
| `\to` | → | | `\Rightarrow` | ⇒ |
| `\emptyset` | ∅ | | `\neg` | ¬ |

## Output Formats

### HTML (KaTeX)

Math nodes render with KaTeX-compatible delimiters:
- Inline: `\( formula \)` inside `<span class="math-inline">`
- Display: `\[ formula \]` inside `<div class="math-display">`

Add `katex_head()` to your document for client-side rendering:

```ruby
document("Math Page",
  head: katex_head,
  body: [math_block("E = mc^2")]
)
```

### DOCX (OMML)

Math is converted to Office Math Markup Language via `Nodex::OMML.to_omml()`.
Equations are native Word objects — editable in Word and LibreOffice.

- Inline math: `<m:oMath>` inside paragraph
- Display math: `<m:oMathPara>` (centered, block-level)

### PDF

Via DOCX → LibreOffice conversion. Equations are rendered by LibreOffice's math engine.

## Markdown

Both `$...$` and `$$...$$` are supported:

```markdown
The quadratic formula is $x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$.

The sum formula:

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$
```

Works in both `Markdown.to_html` and `Markdown.to_node`:

```ruby
node = Nodex.markdown_node(md_text)
node.to_docx("article.docx")  # equations are native OMML
```

## OMML Converter API

For direct access:

```ruby
xml = Nodex::OMML.to_omml("\\frac{a}{b}")
# => "<m:f><m:num><m:r><m:t>a</m:t></m:r></m:num><m:den>..."

xml = Nodex::OMML.to_omml_para("E = mc^2")
# => "<m:oMathPara><m:oMath>...</m:oMath></m:oMathPara>"
```

## Limitations

- No matrix/array environments (`\begin{matrix}...`)
- No `\mathbb`, `\mathcal` font commands
- No equation numbering
- No alignment environments (`\begin{align}...`)
- Nested structures work but very deep nesting may produce suboptimal OMML
