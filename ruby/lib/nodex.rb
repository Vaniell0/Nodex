# frozen_string_literal: true

# Nodex Ruby DSL — declarative HTML generation, pure Ruby.
#
# Usage:
#   require 'nodex'
#
#   page = Nodex.document("My Page",
#     head: [Nodex.style_elem("body { margin: 0; }")],
#     body: [Nodex.h1("Hello").bold.color("red")]
#   )
#   puts page.to_html

require 'json'
require 'open3'
require 'set'
require_relative 'nodex/version'
require_relative 'nodex/platform'
require_relative 'nodex/mime'
require_relative 'nodex/template'
require_relative 'nodex/server'
require_relative 'nodex/session'
require_relative 'nodex/docx'
require_relative 'nodex/omml'
require_relative 'nodex/odt'

module Nodex
  # HTML void elements (self-closing, no end tag)
  VOID_ELEMENTS = Set.new(%w[
    area base br col embed hr img input link meta param source track wbr
  ]).freeze

  # Characters that need HTML escaping
  ESCAPE_MAP = { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;' }.freeze

  def self.escape_html(str) = str.to_s.gsub(/[&<>"']/, ESCAPE_MAP)

  # ── Node ─────────────────────────────────────────────────────────
  #
  # Thread safety: Node is NOT thread-safe. Each request handler must build
  # its own Node tree and must not share a Node across threads. The Server
  # satisfies this automatically — route handlers run per-connection in
  # separate threads and should always return a freshly constructed tree.

  class Node
    attr_reader :tag, :children
    attr_accessor :text

    def initialize(tag, text: nil, raw_html: nil)
      @tag      = tag       # ivs[0]
      @text     = text       # ivs[1]
      @raw_html = raw_html   # ivs[2]
      @attrs    = nil         # ivs[3]
      @styles   = nil         # ivs[4]
      @classes  = nil         # ivs[5]
      @id       = nil         # ivs[6]
      @children = nil         # ivs[7]
      @parent   = nil         # ivs[8] — safe for ROBJECT_IVPTR (detect checks 0-7 only)
    end

    def invalidate_cache!
      node = self
      while node
        cache = node.instance_variable_get(:@_html_cache)
        return unless cache
        node.instance_variable_set(:@_html_cache, nil)
        node = node.instance_variable_get(:@parent)
      end
    end

    # --- Attributes ---

    def set_attr(key, value)
      (@attrs ||= {})[key.to_s] = value.to_s
      self
    end

    def set_style(property, value)
      (@styles ||= {})[property.to_s] = value.to_s
      self
    end

    def add_class(cls)
      @classes ||= []
      cls.to_s.split(/\s+/).each { |c| @classes << c unless @classes.include?(c) }
      self
    end

    def set_class(cls)
      @classes = cls.to_s.split(/\s+/)
      self
    end

    def set_id(id)
      @id = id.to_s
      self
    end

    def set_text(content)
      @text = content.to_s
      self
    end

    def styles(**pairs)
      s = (@styles ||= {})
      pairs.each { |k, v| s[k.to_s] = v.to_s }
      self
    end

    # --- Tree operations ---

    def append(child)
      child = child.is_a?(Node) ? child : Nodex.text(child.to_s)
      child.instance_variable_set(:@parent, self)
      (@children ||= []) << child
      self
    end

    def prepend(child)
      child = child.is_a?(Node) ? child : Nodex.text(child.to_s)
      child.instance_variable_set(:@parent, self)
      (@children ||= []).unshift(child)
      self
    end

    def <<(child)
      append(child)
      self
    end

    def child_count = @children ? @children.size : 0

    # --- Rendering ---

    def to_html
      return @raw_html if @raw_html
      return Nodex.escape_html(@text) if @tag == :text_node

      # Math formula rendering (KaTeX-compatible delimiters)
      if @tag == 'math'
        formula = @text || ''
        cls = @classes ? " #{@classes.join(' ')}" : ''
        sty = @styles ? " style=\"#{@styles.map { |k, v| "#{k}: #{v}" }.join('; ')}\"" : ''
        id_attr = @id ? " id=\"#{Nodex.escape_html(@id)}\"" : ''
        if @attrs && @attrs['display'] == 'block'
          return "<div class=\"math-display#{cls}\"#{id_attr}#{sty}>\\[#{formula}\\]</div>"
        else
          return "<span class=\"math-inline#{cls}\"#{id_attr}#{sty}>\\(#{formula}\\)</span>"
        end
      end

      s = +""
      s << "<!DOCTYPE html>\n" if @tag == 'html'
      s << "<#{@tag}"

      # id
      s << " id=\"#{Nodex.escape_html(@id)}\"" if @id

      # classes
      if @classes
        s << " class=\"#{Nodex.escape_html(@classes.join(' '))}\""
      end

      # styles
      if @styles
        style_str = @styles.map { |k, v| "#{k}: #{v}" }.join('; ')
        s << " style=\"#{Nodex.escape_html(style_str)}\""
      end

      # attributes
      if @attrs
        @attrs.each do |k, v|
          s << " #{k}=\"#{Nodex.escape_html(v)}\""
        end
      end

      if VOID_ELEMENTS.include?(@tag)
        s << ">"
      else
        s << ">"
        s << Nodex.escape_html(@text) if @text
        @children&.each { |c| s << c.to_html }
        s << "</#{@tag}>"
      end

      s
    end

    def to_json(indent: 2) = JSON.pretty_generate(to_hash, indent: ' ' * indent)

    # Render to DOCX (pure Ruby, zero deps).
    #
    #   docx = node.to_docx(preset: :gost)
    #   File.binwrite("report.docx", docx)
    def to_docx(output_path = nil, preset: nil, **opts)
      data = Nodex::DocxWriter.render(self, preset: preset, **opts)
      output_path ? File.binwrite(output_path, data) : data
    end

    # Render to ODT (pure Ruby, zero deps).
    #
    #   odt = node.to_odt(preset: :gost)
    #   File.binwrite("report.odt", odt)
    def to_odt(output_path = nil, preset: nil, **opts)
      data = Nodex::OdtWriter.render(self, preset: preset, **opts)
      output_path ? File.binwrite(output_path, data) : data
    end

    # Render to PDF via DOCX → LibreOffice conversion.
    # Requires `soffice` (LibreOffice) in PATH.
    #
    #   node.to_pdf("report.pdf", preset: :academic)
    def to_pdf(output_path = nil, preset: nil, **opts)
      require 'tempfile'
      require 'fileutils'

      docx_data = to_docx(preset: preset, **opts)
      tmp = Tempfile.new(['nodex', '.docx'])
      tmp.binmode
      tmp.write(docx_data)
      tmp.close

      tmp_dir = Dir.mktmpdir('nodex-pdf')
      result = system('soffice', '--headless', '--convert-to', 'pdf',
                       '--outdir', tmp_dir, tmp.path,
                       out: File::NULL, err: File::NULL)
      raise "soffice not found or conversion failed (is LibreOffice installed?)" unless result

      pdf_path = File.join(tmp_dir, File.basename(tmp.path, '.docx') + '.pdf')
      pdf_data = File.binread(pdf_path)

      FileUtils.rm_rf(tmp_dir)
      tmp.unlink

      output_path ? File.binwrite(output_path, pdf_data) : pdf_data
    end

    def to_hash
      # Handle special Ruby-only node types for C++ compatibility
      if @raw_html
        return { tag: '', text: @raw_html, raw: true }
      end
      if @tag == :text_node
        return { tag: '', text: @text || '' }
      end

      h = { tag: @tag }
      h[:id] = @id if @id
      h[:classes] = @classes if @classes
      h[:styles] = @styles if @styles
      h[:attrs] = @attrs if @attrs
      h[:text] = @text if @text
      h[:children] = @children.map(&:to_hash) if @children
      h
    end

    # --- Pipe operator ---
    #
    # Supports:
    #   node | :bold                      — Symbol: calls node.bold
    #   node | Bold()                     — Proc: applies decorator
    #   node | [Bold(), Color("red")]     — Array of Procs: applies each in order
    #   node | [:color, "red"]            — Legacy: send(:color, "red")
    #   node | Nodex.style(:headline)      — Named style preset (returns Proc)
    #
    # Decorator composition via Ruby's built-in Proc#>>:
    #   Headline = Bold() >> FontSize("2rem") >> Color("#333")
    #   node | Headline

    def |(decorator)
      case decorator
      when Symbol
        if Nodex.named_style?(decorator)
          Nodex.style(decorator).call(self)
        else
          send(decorator)
        end
      when Proc
        decorator.call(self)
      when Array
        if decorator.first.is_a?(Proc)
          decorator.each { |d| d.call(self) }
          self
        else
          send(decorator[0], *decorator[1..])
        end
      else self
      end
    end

    # --- Decorator-style methods (chainable) ---

    def bold              = set_style('font-weight', 'bold')
    def italic            = set_style('font-style', 'italic')
    def underline         = set_style('text-decoration', 'underline')
    def strikethrough     = set_style('text-decoration', 'line-through')
    def color(c)          = set_style('color', c)
    def bg_color(c)       = set_style('background-color', c)

    def font_size(size)
      size = "#{size}px" if size.is_a?(Integer)
      set_style('font-size', size)
    end

    def center        = styles(display: 'flex', 'justify-content': 'center', 'align-items': 'center')
    def padding(val)  = set_style('padding', val.is_a?(Integer) ? "#{val}px" : val)
    def margin(val)   = set_style('margin', val.is_a?(Integer) ? "#{val}px" : val)
    def width(w)      = set_style('width', w)
    def height(h)     = set_style('height', h)

    # --- Visual effects ---

    def transform(t)        = set_style('transform', t)
    def box_shadow(s)       = set_style('box-shadow', s)
    def text_shadow(s)      = set_style('text-shadow', s)
    def filter(f)           = set_style('filter', f)
    def backdrop_filter(f)  = set_style('backdrop-filter', f)
    def opacity(v)          = set_style('opacity', v.to_s)
    def border(b)           = set_style('border', b)
    def border_radius(r)
      r = "#{r}px" if r.is_a?(Integer)
      set_style('border-radius', r)
    end

    def transition(prop, duration: '0.3s', easing: 'ease')     = set_style('transition', "#{prop} #{duration} #{easing}")
    def transition_all(duration: '0.3s', easing: 'ease')      = transition('all', duration: duration, easing: easing)

    # --- Positioning ---

    def position(pos)   = set_style('position', pos)
    def z_index(z)      = set_style('z-index', z.to_s)
    def top(v)          = set_style('top', v)
    def right(v)        = set_style('right', v)
    def bottom(v)       = set_style('bottom', v)
    def left(v)         = set_style('left', v)
    def inset(v)        = set_style('inset', v)
    def overflow(v)     = set_style('overflow', v)
    def overflow_x(v)   = set_style('overflow-x', v)
    def overflow_y(v)   = set_style('overflow-y', v)

    # --- Extended layout ---

    def gap(g)
      g = "#{g}px" if g.is_a?(Integer)
      set_style('gap', g)
    end

    def row_gap(g)          = set_style('row-gap', g)
    def column_gap(g)       = set_style('column-gap', g)
    def justify_content(jc) = set_style('justify-content', jc)
    def align_items(ai)     = set_style('align-items', ai)
    def align_self(as_val)  = set_style('align-self', as_val)
    def flex_wrap(w = 'wrap') = set_style('flex-wrap', w)
    def flex_shrink(v)      = set_style('flex-shrink', v.to_s)
    def flex_basis(b)       = set_style('flex-basis', b)
    def flex_grow(v = 1)    = set_style('flex-grow', v.to_s)
    def grid_column(c)      = set_style('grid-column', c)
    def grid_row(r)         = set_style('grid-row', r)

    # --- Interaction ---

    def cursor(c)           = set_style('cursor', c)
    def user_select(s)      = set_style('user-select', s)
    def pointer_events(pe)  = set_style('pointer-events', pe)

    # --- CSS custom properties ---

    def css_var(name, value)
      prop = name.start_with?('--') ? name : "--#{name}"
      set_style(prop, value)
    end

    # --- Data attributes ---

    def data(key, value) = set_attr("data-#{key}", value.to_s)

    # --- Display ---

    def display(d)      = set_style('display', d)
    def visibility(v)   = set_style('visibility', v)

    # --- Typography extras ---

    def font_family(f)      = set_style('font-family', f)
    def letter_spacing(s)   = set_style('letter-spacing', s)
    def line_height(h)      = set_style('line-height', h)
    def text_transform(t)   = set_style('text-transform', t)
    def word_break(wb)      = set_style('word-break', wb)
    def white_space(ws)     = set_style('white-space', ws)

    # --- Sizing extras ---

    def min_width(w)  = set_style('min-width', w)
    def max_width(w)  = set_style('max-width', w)
    def min_height(h) = set_style('min-height', h)
    def max_height(h) = set_style('max-height', h)

    # --- HTMX attributes ---

    def hx_get(url)    = set_attr('hx-get', url)
    def hx_post(url)   = set_attr('hx-post', url)
    def hx_put(url)    = set_attr('hx-put', url)
    def hx_patch(url)  = set_attr('hx-patch', url)
    def hx_delete(url) = set_attr('hx-delete', url)
    def hx_target(sel)  = set_attr('hx-target', sel)
    def hx_swap(strat)  = set_attr('hx-swap', strat)
    def hx_trigger(trg) = set_attr('hx-trigger', trg)
    def hx_push_url(u = 'true') = set_attr('hx-push-url', u)
    def hx_select(sel)  = set_attr('hx-select', sel)
    def hx_vals(json)   = set_attr('hx-vals', json)
    def hx_confirm(msg) = set_attr('hx-confirm', msg)
    def hx_indicator(s) = set_attr('hx-indicator', s)
    def hx_boost(e = true) = set_attr('hx-boost', e.to_s)

    # Pre-built LE uint16 lookup — avoids pack('v') per string field.
    # 2048 entries covers all realistic tag/class/style/attr/text lengths.
    # Anything longer falls back to pack.
  end

  # ── Factory methods ──────────────────────────────────────────────

  module_function

  def node(tag, children: [], text: nil, **attrs, &block)
    n = Node.new(tag.to_s, text: text)

    # Route special kwargs to proper Node fields.
    n.set_class(attrs.delete(:class))   if attrs.key?(:class)
    n.set_id(attrs.delete(:id).to_s)   if attrs.key?(:id)

    # style: Hash or CSS string → set_style per property.
    if (sty = attrs.delete(:style))
      case sty
      when Hash
        sty.each { |k, v| n.set_style(k.to_s.tr('_', '-'), v.to_s) }
      when String
        sty.split(';').each do |decl|
          k, v = decl.split(':', 2).map(&:strip)
          n.set_style(k, v) if k && !k.empty? && v
        end
      end
    end

    # data: {key: val} → data-key="val"  (Stimulus, Turbo, etc.)
    if (dh = attrs.delete(:data))
      dh.each { |k, v| n.set_attr("data-#{k.to_s.tr('_', '-')}", v.to_s) }
    end

    # hx: {post: "/url", target: "#id"} → hx-post="/url" hx-target="#id"
    if (hh = attrs.delete(:hx))
      hh.each { |k, v| n.set_attr("hx-#{k.to_s.tr('_', '-')}", v.to_s) }
    end

    attrs.each { |k, v| n.set_attr(k.to_s.tr('_', '-'), v.to_s) }
    children.each { |c| n.append(c) }

    if block
      if block.arity == 0
        # DSL block: h1/p/div etc. called inside are auto-appended.
        # self changes to NodeBuilder; outer locals are still accessible.
        # Unknown methods delegate to the object that created the block.
        outer = (block.binding.receiver rescue nil)
        NodeBuilder.new(n, outer).instance_eval(&block)
      else
        yield n
      end
    end

    n
  end

  def text(content) = Node.new(:text_node, text: content.to_s)
  def raw(html)     = Node.new(:raw_node, raw_html: html.to_s)

  # Returns an Array of child nodes without a wrapper element.
  # Inside NodeBuilder, the array is spread into the parent:
  #
  #   def sidebar_items
  #     fragment { li "A"; li "B"; li "C" }
  #   end
  #
  #   ul { sidebar_items }  # appends li A, B, C directly to ul
  def fragment(&block)
    tmp = Node.new(:fragment)
    if block
      if block.arity == 0
        outer = (block.binding.receiver rescue nil)
        NodeBuilder.new(tmp, outer).instance_eval(&block)
      else
        yield tmp
      end
    end
    tmp.children || []
  end

  SLOT_PREFIX = "__Nodex_SLOT_"
  SLOT_SUFFIX = "__"

  # Returns marker string for use in text content or attribute values.
  #   Nodex.h1(Nodex.slot(:title))           # text slot
  #   Nodex.a("link", href: Nodex.slot(:url)) # attribute slot
  def slot(name)      = "#{SLOT_PREFIX}#{name}#{SLOT_SUFFIX}"
  def slot_attr(name) = slot(name)

  # --- Text elements ---

  def h1(content) = node('h1', text: content)
  def h2(content) = node('h2', text: content)
  def h3(content) = node('h3', text: content)
  def h4(content) = node('h4', text: content)
  def h5(content) = node('h5', text: content)
  def h6(content) = node('h6', text: content)
  def p(content)  = node('p',  text: content)
  def span_elem(content) = node('span', text: content)
  def code(content) = node('code', text: content)
  def pre(content)  = node('pre',  text: content)
  def strong(content) = node('strong', text: content)
  def em(content)     = node('em', text: content)

  # --- Containers ---

  def div(children = [], **attrs, &block) = node('div', children: children, **attrs, &block)
  def section(children = [], **attrs, &block) = node('section', children: children, **attrs, &block)
  def article(children = [], **attrs, &block) = node('article', children: children, **attrs, &block)
  def nav(children = [], **attrs, &block) = node('nav', children: children, **attrs, &block)
  def header(children = [], **attrs, &block) = node('header', children: children, **attrs, &block)
  def footer(children = [], **attrs, &block) = node('footer', children: children, **attrs, &block)
  def main_elem(children = [], **attrs, &block) = node('main', children: children, **attrs, &block)
  def aside(children = [], **attrs, &block) = node('aside', children: children, **attrs, &block)

  # --- Layout ---

  def vbox(children = [], **attrs, &block)
    n = div(children, **attrs, &block)
    n.set_style('display', 'flex')
    n.set_style('flex-direction', 'column')
    n
  end

  def hbox(children = [], **attrs, &block)
    n = div(children, **attrs, &block)
    n.set_style('display', 'flex')
    n.set_style('flex-direction', 'row')
    n
  end

  # --- Lists ---

  def ul(items = [], **attrs, &block) = node('ul', children: items, **attrs, &block)
  def ol(items = [], **attrs, &block) = node('ol', children: items, **attrs, &block)

  def li(content = nil, **attrs, &block)
    if block
      node('li', **attrs, &block)
    elsif content.is_a?(String)
      node('li', text: content, **attrs)
    elsif content
      node('li', children: [content], **attrs)
    else
      node('li', **attrs)
    end
  end

  # --- Forms ---

  def form(children = [], **attrs, &block) = node('form', children: children, **attrs, &block)
  def input_elem(type, **attrs) = node('input', type: type, **attrs)
  def textarea(content = '', **attrs) = node('textarea', text: content, **attrs)
  def button(label, **attrs) = node('button', text: label, **attrs)
  def label(content, **attrs) = node('label', text: content, **attrs)
  def select_elem(options = [], **attrs) = node('select', children: options, **attrs)
  def option(label, value:) = node('option', text: label, value: value)

  # --- Links ---

  def a(content, href: '#', target: '_self') = node('a', text: content, href: href, target: target)

  # --- Media ---

  def img(src, alt: '') = node('img', src: src, alt: alt)

  def video(src = nil, children: [], **attrs)
    if src
      node('video', children: children, src: src, **attrs)
    else
      node('video', children: children, **attrs)
    end
  end

  def audio(src = nil, children: [], **attrs)
    if src
      node('audio', children: children, src: src, **attrs)
    else
      node('audio', children: children, **attrs)
    end
  end

  def canvas(**attrs) = node('canvas', **attrs)

  def source_elem(src, type:)        = node('source', src: src, type: type)
  def picture(sources, fallback_img) = node('picture', children: [*sources, fallback_img])

  def figure(content, caption:)
    children = content.is_a?(Array) ? content : [content]
    cap = node('figcaption', text: caption)
    node('figure', children: [*children, cap])
  end

  def iframe(src, **attrs) = node('iframe', src: src, **attrs)

  def svg(content, **attrs) = raw("<svg#{attrs.map { |k, v| " #{k}=\"#{v}\"" }.join}>#{content}</svg>")

  # --- Tables ---

  def table(rows = [], **attrs, &block) = node('table', children: rows, **attrs, &block)
  def thead(rows = [], &block) = node('thead', children: rows, &block)
  def tbody(rows = [], &block) = node('tbody', children: rows, &block)
  def tr(cells = [], &block)   = node('tr', children: cells, &block)

  def th(content = nil, **attrs, &block)
    block ? node('th', **attrs, &block) :
      content.is_a?(String) ? node('th', text: content, **attrs) : node('th', children: [content], **attrs)
  end

  def td(content = nil, **attrs, &block)
    block ? node('td', **attrs, &block) :
      content.is_a?(String) ? node('td', text: content, **attrs) : node('td', children: [content], **attrs)
  end

  # --- Semantic inline ---

  def br() = node('br')
  def hr() = node('hr')
  def page_break() = node('__page_break__')
  def separator() = hr().set_style('border', '1px solid #ccc')

  # --- Math formulas ---
  #
  # Inline:  math("x^2 + y^2")           → \( x^2 + y^2 \)
  # Display: math("E = mc^2", display: true)  → \[ E = mc^2 \]
  #          math_block("\\frac{a}{b}")        → \[ \frac{a}{b} \]
  #
  # Requires KaTeX on the page — use katex_head() in document head.

  def math(formula, display: false)
    n = Node.new('math', text: formula)
    n.set_attr('display', 'block') if display
    n
  end

  def math_block(formula) = math(formula, display: true)

  # Math DSL helpers — generate LaTeX strings, render via math()
  #
  # Two categories:
  #   1. String builders (return LaTeX string for composition):
  #      tex_overline, tex_sub, tex_sup, tex_frac, tex_sqrt
  #   2. Node builders (return Math Node for document tree):
  #      frac, frac_display, msqrt, msum, mint, mprod

  # ── String builders (composable LaTeX fragments) ──────────────
  def tex_overline(expr)         = "\\overline{#{expr}}"
  def tex_hat(expr)              = "\\hat{#{expr}}"
  def tex_tilde(expr)            = "\\tilde{#{expr}}"
  def tex_vec(expr)              = "\\vec{#{expr}}"
  def tex_dot(expr)              = "\\dot{#{expr}}"
  def tex_bar(expr)              = "\\bar{#{expr}}"
  def tex_sub(base, idx)         = "#{base}_{#{idx}}"
  def tex_sup(base, exp)         = "#{base}^{#{exp}}"
  def tex_frac(num, den)         = "\\frac{#{num}}{#{den}}"
  def tex_sqrt(expr, n: nil)     = n ? "\\sqrt[#{n}]{#{expr}}" : "\\sqrt{#{expr}}"

  # ── Node builders (return Math Node) ─────────────────────────
  def frac(num, den)             = math("\\frac{#{num}}{#{den}}")
  def frac_display(num, den)     = math_block("\\frac{#{num}}{#{den}}")
  def msqrt(expr, n: nil)        = math(n ? "\\sqrt[#{n}]{#{expr}}" : "\\sqrt{#{expr}}")
  def msum(expr = "", sub: nil, sup: nil)
    s = "\\sum"
    s += "_{#{sub}}" if sub
    s += "^{#{sup}}" if sup
    s += " #{expr}" unless expr.empty?
    math(s)
  end
  def mint(expr = "", sub: nil, sup: nil)
    s = "\\int"
    s += "_{#{sub}}" if sub
    s += "^{#{sup}}" if sup
    s += " #{expr}" unless expr.empty?
    math(s)
  end
  def mprod(expr = "", sub: nil, sup: nil)
    s = "\\prod"
    s += "_{#{sub}}" if sub
    s += "^{#{sup}}" if sup
    s += " #{expr}" unless expr.empty?
    math(s)
  end

  # KaTeX CDN head elements — add to document(head: katex_head + [...])
  KATEX_VERSION = '0.16.21'

  def katex_head
    [
      link_elem(rel: 'stylesheet', href: "https://cdn.jsdelivr.net/npm/katex@#{KATEX_VERSION}/dist/katex.min.css"),
      script("https://cdn.jsdelivr.net/npm/katex@#{KATEX_VERSION}/dist/katex.min.js"),
      script("https://cdn.jsdelivr.net/npm/katex@#{KATEX_VERSION}/dist/contrib/auto-render.min.js"),
      script_inline('document.addEventListener("DOMContentLoaded",function(){renderMathInElement(document.body,{delimiters:[{left:"\\\\[",right:"\\\\]",display:true},{left:"\\\\(",right:"\\\\)",display:false}]})})'),
    ]
  end

  # --- Document structure ---

  def meta_elem(**attrs) = node('meta', **attrs)
  def link_elem(**attrs) = node('link', **attrs)

  def script(src) = node('script', src: src)

  def script_inline(code)
    n = Node.new('script', text: nil)
    # Script content must not be escaped
    n.instance_variable_set(:@raw_html, "<script>#{code}</script>")
    n
  end

  def style_elem(css)  = raw("<style>#{css}</style>")
  def title_elem(text) = node('title', text: text)

  def document(title, head: [], body: [], body_attrs: {})
    head_children = [
      meta_elem(charset: 'UTF-8'),
      meta_elem(name: 'viewport', content: 'width=device-width, initial-scale=1.0'),
      title_elem(title),
      *head,
    ]

    body_node = node('body', children: body)
    body_attrs.each { |k, v| body_node.set_attr(k.to_s, v.to_s) }

    html_node = node('html', children: [
      node('head', children: head_children),
      body_node,
    ], lang: 'en')

    html_node
  end

  # --- File-based helpers ---

  def stylesheet(href, **attrs) = link_elem(rel: 'stylesheet', href: href, **attrs)

  def style_file(path)
    css = File.read(path)
    style_elem(css)
  end

  def script_file(path)
    js = File.read(path)
    script_inline(js)
  end

  def html_file(path) = raw(File.read(path))

  def google_font(family)
    encoded = family.tr(' ', '+')
    stylesheet("https://fonts.googleapis.com/css2?family=#{encoded}&display=swap")
  end

  def version = VERSION

  # ── Layout factory ──────────────────────────────────────────────
  # Standard page structure: navbar + container + footer.
  #
  #   layout("My Site",
  #     head: [stylesheet("/static/style.css")],
  #     navbar: [a("Home", href: "/"), a("About", href: "/about")],
  #     body: [h1("Hello"), p("World")],
  #     footer: [p("Built with Nodex")]
  #   )

  def layout(title, head: [], navbar: [], body: [], footer: [], body_attrs: {})
    nav_node  = navbar.empty? ? nil : nav(navbar) | Class("navbar")
    foot_node = footer.empty? ? nil : self.footer(footer) | Class("footer")
    content   = div(body) | Class("container")

    body_children = [nav_node, content, foot_node].compact

    document(title, head: head, body: body_children, body_attrs: body_attrs)
  end


  # ── Decorator factories (for pipe operator) ─────────────────────
  # Usage: p("Hello") | Bold() | Color("red") | Margin("10px")

  def Bold()              = ->(n) { n.bold }
  def Italic()            = ->(n) { n.italic }
  def Underline()         = ->(n) { n.underline }
  def Strikethrough()     = ->(n) { n.strikethrough }
  def Color(c)            = ->(n) { n.color(c) }
  def BgColor(c)          = ->(n) { n.bg_color(c) }
  def FontSize(s)         = ->(n) { n.font_size(s) }
  def FontFamily(f)       = ->(n) { n.font_family(f) }
  def Center()            = ->(n) { n.center }
  def Padding(v)          = ->(n) { n.padding(v) }
  def Margin(v)           = ->(n) { n.margin(v) }
  def Width(w)            = ->(n) { n.width(w) }
  def Height(h)           = ->(n) { n.height(h) }
  def Border(b)           = ->(n) { n.border(b) }
  def BorderRadius(r)     = ->(n) { n.border_radius(r) }
  def Opacity(v)          = ->(n) { n.opacity(v) }
  def Gap(g)              = ->(n) { n.gap(g) }
  def FlexWrap(w = 'wrap') = ->(n) { n.flex_wrap(w) }
  def FlexGrow(v = 1)     = ->(n) { n.flex_grow(v) }
  def Display(d)          = ->(n) { n.display(d) }
  def Position(p)         = ->(n) { n.position(p) }
  def Transform(t)        = ->(n) { n.transform(t) }
  def BoxShadow(s)        = ->(n) { n.box_shadow(s) }
  def Cursor(c)           = ->(n) { n.cursor(c) }
  def Transition(prop, duration: '0.3s', easing: 'ease') = ->(n) { n.transition(prop, duration: duration, easing: easing) }

  # Attribute/class/id decorators
  def Class(cls)          = ->(n) { n.set_class(cls) }
  def AddClass(cls)       = ->(n) { n.add_class(cls) }
  def Id(id)              = ->(n) { n.set_id(id) }
  def Style(prop, val)    = ->(n) { n.set_style(prop, val) }
  def Attr(key, val)      = ->(n) { n.set_attr(key, val) }
  def Data(key, val)      = ->(n) { n.data(key, val) }

  # HTMX decorators
  def HxGet(url)          = ->(n) { n.hx_get(url) }
  def HxPost(url)         = ->(n) { n.hx_post(url) }
  def HxTarget(sel)       = ->(n) { n.hx_target(sel) }
  def HxSwap(s)           = ->(n) { n.hx_swap(s) }
  def HxTrigger(t)        = ->(n) { n.hx_trigger(t) }

  # ── Named style presets ─────────────────────────────────────────
  #
  # Define reusable decorator combinations and apply via pipe:
  #
  #   Nodex.define_style(:headline, Nodex::Bold() >> Nodex::FontSize("2rem") >> Nodex::Color("#333"))
  #   h1("Title") | :headline
  #   h1("Title") | Nodex.style(:headline)   # explicit form
  #
  # Styles are global to the module; useful for design-system tokens.

  @_styles = {}

  def self.define_style(name, decorator)
    @_styles[name.to_sym] = decorator
    self
  end

  def self.style(name)
    @_styles.fetch(name.to_sym) { raise KeyError, "Unknown style: #{name.inspect}" }
  end

  def self.named_style?(name)
    @_styles.key?(name.to_sym)
  end

  # ── DSL mixin ───────────────────────────────────────────────────
  # Delegates all Nodex methods so you can write h1("...") instead of Nodex.h1("...").
  # Like C++ `using namespace nodex`.
  #
  # Usage:
  #   module Pages::MyPage
  #     extend Nodex::DSL
  #     def self.build
  #       h1("Hello") | Bold() | Color("red")
  #     end
  #   end

  module DSL
    Nodex.singleton_methods(false).each do |name|
      define_method(name) { |*a, **kw, &b| Nodex.send(name, *a, **kw, &b) }
    end
  end

  # ── NodeBuilder ─────────────────────────────────────────────────
  # Used internally by block DSL. When a factory is called with a
  # zero-arity block, the block is instance_eval'd in a NodeBuilder
  # context — every element factory call inside auto-appends its result
  # to the parent node.
  #
  #   div(class: "card") {        # NodeBuilder context
  #     h2 "Title"               # appended to div
  #     p  "Body"                # appended to div
  #     ul {                     # nested NodeBuilder for ul
  #       li "Item 1"
  #       li "Item 2"
  #     }
  #   }
  #
  # User-defined helper methods are accessible via method_missing —
  # NodeBuilder delegates unknown calls to the outer object that
  # created the block. If the helper returns a Node, it is auto-appended.
  #
  #   extend Nodex::DSL
  #   def card(title:, body:)
  #     div(class: "card") { h3 title; p body }
  #   end
  #
  #   div(class: "grid") {
  #     card(title: "Fast", body: "Zero deps")   # works — delegated to outer self
  #     card(title: "Beautiful", body: "Pipe DSL")
  #   }
  #
  # Outer local variables are accessible (closure); instance variables
  # of the calling object are NOT — capture them in locals first.

  class NodeBuilder
    Nodex.singleton_methods(false).each do |name|
      define_method(name) do |*a, **kw, &b|
        result = Nodex.send(name, *a, **kw, &b)
        case result
        when Array then result.each { |r| @parent << r if r.is_a?(Nodex::Node) }
        when Nodex::Node then @parent << result
        end
        result
      end
    end

    def initialize(parent, outer_self = nil)
      @parent = parent
      @outer_self = outer_self
    end

    def method_missing(name, *args, **kwargs, &block)
      if @outer_self&.respond_to?(name, true)
        result = @outer_self.send(name, *args, **kwargs, &block)
        @parent << result if result.is_a?(Nodex::Node)
        result
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      @outer_self&.respond_to?(name, include_private) || super
    end
  end
end

require_relative 'nodex/registry'
require_relative 'nodex/page_loader'
require_relative 'nodex/markdown'
