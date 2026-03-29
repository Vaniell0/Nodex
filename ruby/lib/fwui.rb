# frozen_string_literal: true

# FWUI Ruby DSL — declarative HTML generation, pure Ruby.
#
# Usage:
#   require 'fwui'
#
#   page = FWUI.document("My Page",
#     head: [FWUI.style_elem("body { margin: 0; }")],
#     body: [FWUI.h1("Hello").bold.color("red")]
#   )
#   puts page.to_html

require 'json'
require 'open3'
require 'set'
require_relative 'fwui/version'
require_relative 'fwui/platform'

module FWUI
  # HTML void elements (self-closing, no end tag)
  VOID_ELEMENTS = Set.new(%w[
    area base br col embed hr img input link meta param source track wbr
  ]).freeze

  # Characters that need HTML escaping
  ESCAPE_MAP = { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;' }.freeze

  def self.escape_html(str) = str.to_s.gsub(/[&<>"']/, ESCAPE_MAP)

  # ── Node ─────────────────────────────────────────────────────────

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
      child = child.is_a?(Node) ? child : FWUI.text(child.to_s)
      child.instance_variable_set(:@parent, self)
      (@children ||= []) << child
      self
    end

    def prepend(child)
      child = child.is_a?(Node) ? child : FWUI.text(child.to_s)
      child.instance_variable_set(:@parent, self)
      (@children ||= []).unshift(child)
      self
    end

    def child_count = @children ? @children.size : 0

    # --- Rendering ---

    def to_html
      return @raw_html if @raw_html
      return FWUI.escape_html(@text) if @tag == :text_node

      s = +""
      s << "<!DOCTYPE html>\n" if @tag == 'html'
      s << "<#{@tag}"

      # id
      s << " id=\"#{FWUI.escape_html(@id)}\"" if @id

      # classes
      if @classes
        s << " class=\"#{FWUI.escape_html(@classes.join(' '))}\""
      end

      # styles
      if @styles
        style_str = @styles.map { |k, v| "#{k}: #{v}" }.join('; ')
        s << " style=\"#{FWUI.escape_html(style_str)}\""
      end

      # attributes
      if @attrs
        @attrs.each do |k, v|
          s << " #{k}=\"#{FWUI.escape_html(v)}\""
        end
      end

      if VOID_ELEMENTS.include?(@tag)
        s << ">"
      else
        s << ">"
        s << FWUI.escape_html(@text) if @text
        @children&.each { |c| s << c.to_html }
        s << "</#{@tag}>"
      end

      s
    end

    def to_json(indent: 2) = JSON.pretty_generate(to_hash, indent: ' ' * indent)

    # Render this node tree to PDF via the fwui-pdf CLI.
    # Returns PDF data as a binary string, or writes to output_path if given.
    #
    #   node.to_pdf                              # => "\x25PDF-..."
    #   node.to_pdf("report.pdf")                # writes file, returns bytes written
    #   node.to_pdf(title: "Report", page_numbers: true)
    def to_pdf(output_path = nil, title: nil, author: nil, page_size: nil,
               page_numbers: false, font_size: nil, margins: nil)
      json_str = to_json
      args = ['fwui-pdf', '-i', '-', '-o', '-']
      args += ['--title', title]       if title
      args += ['--author', author]     if author
      args += ['--page-size', page_size] if page_size
      args += ['--font-size', font_size.to_s] if font_size
      args += ['--margins', margins]   if margins
      args += ['--page-numbers']       if page_numbers

      pdf_data, status = Open3.capture2(*args, stdin_data: json_str, binmode: true)
      raise "fwui-pdf failed (exit #{status.exitstatus})" unless status.success?

      if output_path
        File.binwrite(output_path, pdf_data)
      else
        pdf_data
      end
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

    # --- Pipe operator (C++ style: node | Bold() | Color("red")) ---

    def |(decorator)
      case decorator
      when Symbol then send(decorator)
      when Proc   then decorator.call(self)
      when Array  then send(decorator[0], *decorator[1..])
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

  def node(tag, children: [], text: nil, **attrs)
    n = Node.new(tag.to_s, text: text)
    attrs.each { |k, v| n.set_attr(k.to_s.tr('_', '-'), v.to_s) }
    children.each { |c| n.append(c) }
    yield n if block_given?
    n
  end

  def text(content) = Node.new(:text_node, text: content.to_s)
  def raw(html)     = Node.new(:raw_node, raw_html: html.to_s)

  SLOT_PREFIX = "__FWUI_SLOT_"
  SLOT_SUFFIX = "__"

  # Returns marker string for use in text content or attribute values.
  #   FWUI.h1(FWUI.slot(:title))           # text slot
  #   FWUI.a("link", href: FWUI.slot(:url)) # attribute slot
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

  def ul(items = [], **attrs) = node('ul', children: items, **attrs)
  def ol(items = [], **attrs) = node('ol', children: items, **attrs)
  def li(content) = content.is_a?(String) ? node('li', text: content) : node('li', children: [content])

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

  def table(rows = [], **attrs) = node('table', children: rows, **attrs)
  def thead(rows) = node('thead', children: rows)
  def tbody(rows) = node('tbody', children: rows)
  def tr(cells)   = node('tr', children: cells)
  def th(content) = content.is_a?(String) ? node('th', text: content) : node('th', children: [content])
  def td(content) = content.is_a?(String) ? node('td', text: content) : node('td', children: [content])

  # --- Semantic inline ---

  def br() = node('br')
  def hr() = node('hr')
  def separator() = hr().set_style('border', '1px solid #ccc')

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
  #     footer: [p("Built with FWUI")]
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

  # ── DSL mixin ───────────────────────────────────────────────────
  # Delegates all FWUI methods so you can write h1("...") instead of FWUI.h1("...").
  # Like C++ `using namespace fwui`.
  #
  # Usage:
  #   module Pages::MyPage
  #     extend FWUI::DSL
  #     def self.build
  #       h1("Hello") | Bold() | Color("red")
  #     end
  #   end

  module DSL
    FWUI.singleton_methods(false).each do |name|
      define_method(name) { |*a, **kw, &b| FWUI.send(name, *a, **kw, &b) }
    end
  end
end

require_relative 'fwui/registry'
require_relative 'fwui/page_loader'
