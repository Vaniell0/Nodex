# frozen_string_literal: true

module Nodex
  module Native
    # Pre-built LE uint16 lookup — avoids pack('v') per string field.
    U16_LE = Array.new(2048) { |i| [i].pack('v').freeze }.freeze

    class PackedBuilder
      CLOSE   = "\x02".b.freeze
      VCLOSE  = "\x09".b.freeze
      DOCTYPE = "\x0A".b.freeze

      # Pre-computed OPEN sequences for common tags
      TAG_OPEN = %w[
        div p span h1 h2 h3 h4 h5 h6 a li ul ol section article nav
        header footer main aside button form table thead tbody tr th td
        head body html title
      ].each_with_object({}) { |t, h|
        h[t] = ("\x01".b + U16_LE[t.bytesize] + t.b).freeze
      }.freeze

      # Pre-computed OPEN sequences for void tags
      VOID_OPEN = %w[br hr img input meta link].each_with_object({}) { |t, h|
        h[t] = ("\x01".b + U16_LE[t.bytesize] + t.b).freeze
      }.freeze

      attr_reader :buf

      def initialize
        @buf = String.new(capacity: 4096, encoding: Encoding::BINARY)
        @pending = nil
      end

      def to_opcodes
        _flush_pending
        @buf
      end

      def _flush_pending
        if @pending
          p = @pending
          @pending = nil
          p._emit_close
        end
      end

      def _splice(pos, bytes)
        @buf.insert(pos, bytes)
      end

      def _element(tag, text = nil, void: false, **attrs)
        _flush_pending

        # Emit OPEN (pre-computed for common tags)
        open_seq = void ? VOID_OPEN[tag] : TAG_OPEN[tag]
        if open_seq
          @buf << open_seq
        else
          s = tag.b
          @buf << "\x01" << (U16_LE[s.bytesize] || [s.bytesize].pack('v')) << s
        end

        # Emit initial attrs from kwargs
        attrs.each { |k, v| _emit_attr(k.to_s.tr('_', '-'), v.to_s) }
        splice_pos = @buf.bytesize

        proxy = Proxy.new(self, void)

        if block_given?
          _emit_text(text.to_s) if text
          yield
          _flush_pending
          if void
            @buf << VCLOSE
            proxy.instance_variable_set(:@closed, true)
          else
            proxy._mark_deferred(splice_pos)
            @pending = proxy
          end
        else
          proxy._pending_text = text
          if void
            @buf << VCLOSE
          else
            @pending = proxy
          end
        end
        proxy
      end

      # ── Emit helpers ──

      def _emit_close; @buf << CLOSE; end

      def _emit_text(str)
        s = str.to_s.b
        @buf << "\x03" << (U16_LE[s.bytesize] || [s.bytesize].pack('v')) << s
      end

      def _emit_raw(str)
        s = str.to_s.b
        @buf << "\x04" << (U16_LE[s.bytesize] || [s.bytesize].pack('v')) << s
      end

      def _emit_attr(k, v)
        kb = k.to_s.b; vb = v.to_s.b
        @buf << "\x05" <<
          (U16_LE[kb.bytesize] || [kb.bytesize].pack('v')) << kb <<
          (U16_LE[vb.bytesize] || [vb.bytesize].pack('v')) << vb
      end

      # ── Factory methods ──

      def text(content)
        _flush_pending
        _emit_text(content.to_s)
        nil
      end

      def raw(html)
        _flush_pending
        _emit_raw(html.to_s)
        nil
      end

      def div(text = nil, **a, &b)     = _element('div', text, **a, &b)
      def p(text = nil, **a, &b)       = _element('p', text, **a, &b)
      def span(text = nil, **a, &b)    = _element('span', text, **a, &b)
      def h1(text = nil, **a, &b)      = _element('h1', text, **a, &b)
      def h2(text = nil, **a, &b)      = _element('h2', text, **a, &b)
      def h3(text = nil, **a, &b)      = _element('h3', text, **a, &b)
      def h4(text = nil, **a, &b)      = _element('h4', text, **a, &b)
      def h5(text = nil, **a, &b)      = _element('h5', text, **a, &b)
      def h6(text = nil, **a, &b)      = _element('h6', text, **a, &b)
      def section(**a, &b)   = _element('section', nil, **a, &b)
      def article(**a, &b)   = _element('article', nil, **a, &b)
      def nav(**a, &b)       = _element('nav', nil, **a, &b)
      def header(**a, &b)    = _element('header', nil, **a, &b)
      def footer(**a, &b)    = _element('footer', nil, **a, &b)
      def main(**a, &b)      = _element('main', nil, **a, &b)
      def aside(**a, &b)     = _element('aside', nil, **a, &b)
      def ul(**a, &b)        = _element('ul', nil, **a, &b)
      def ol(**a, &b)        = _element('ol', nil, **a, &b)
      def li(text = nil, **a, &b) = _element('li', text, **a, &b)
      def a(text = nil, href: '#', target: '_self', **a, &b) = _element('a', text, href: href, target: target, **a, &b)
      def button(text = nil, **a, &b) = _element('button', text, **a, &b)
      def form(**a, &b)      = _element('form', nil, **a, &b)
      def table(**a, &b)     = _element('table', nil, **a, &b)
      def thead(**a, &b)     = _element('thead', nil, **a, &b)
      def tbody(**a, &b)     = _element('tbody', nil, **a, &b)
      def tr(**a, &b)        = _element('tr', nil, **a, &b)
      def th(text = nil, **a, &b) = _element('th', text, **a, &b)
      def td(text = nil, **a, &b) = _element('td', text, **a, &b)

      # Void elements
      def br(**a)    = _element('br', nil, void: true, **a)
      def hr(**a)    = _element('hr', nil, void: true, **a)
      def img(**a)   = _element('img', nil, void: true, **a)
      def input(**a) = _element('input', nil, void: true, **a)
      def meta(**a)  = _element('meta', nil, void: true, **a)
      def link(**a)  = _element('link', nil, void: true, **a)

      # Document helper
      def document(title, &body_block)
        @buf << DOCTYPE
        _element('html', nil, lang: 'en') {
          _element('head') {
            meta(charset: 'UTF-8')
            meta(name: 'viewport', content: 'width=device-width, initial-scale=1.0')
            _element('title', title)
          }
          _element('body', &body_block)
        }
      end
    end

    class Proxy
      attr_writer :_pending_text

      def initialize(builder, void = false)
        @b = builder
        @void = void
        @closed = void
        @_pending_text = nil
        @extra = nil
        @splice_pos = nil
      end

      def _mark_deferred(pos)
        @splice_pos = pos
        @extra = String.new(capacity: 64, encoding: Encoding::BINARY)
      end

      def _emit_close
        return if @closed
        @closed = true
        if @extra && @extra.bytesize > 0
          @b._splice(@splice_pos, @extra)
        end
        if @_pending_text
          s = @_pending_text.to_s.b
          @b.buf << "\x03" << (U16_LE[s.bytesize] || [s.bytesize].pack('v')) << s
        end
        @b._emit_close
      end

      def _target = @extra || @b.buf

      # Style methods
      def bold()            = _style('font-weight', 'bold')
      def italic()          = _style('font-style', 'italic')
      def underline()       = _style('text-decoration', 'underline')
      def color(c)          = _style('color', c)
      def bg_color(c)       = _style('background-color', c)
      def padding(v)        = _style('padding', v)
      def margin(v)         = _style('margin', v)
      def font_size(s)      = _style('font-size', s.is_a?(Integer) ? "#{s}px" : s)
      def width(w)          = _style('width', w)
      def height(h)         = _style('height', h)
      def border(b)         = _style('border', b)
      def border_radius(r)  = _style('border-radius', r.is_a?(Integer) ? "#{r}px" : r)
      def display(d)        = _style('display', d)
      def gap(g)            = _style('gap', g.is_a?(Integer) ? "#{g}px" : g)
      def opacity(v)        = _style('opacity', v.to_s)
      def text_align(v)     = _style('text-align', v)
      def flex_direction(v) = _style('flex-direction', v)
      def justify_content(v) = _style('justify-content', v)
      def align_items(v)    = _style('align-items', v)
      def max_width(v)      = _style('max-width', v)
      def min_height(v)     = _style('min-height', v)
      def overflow(v)       = _style('overflow', v)
      def cursor(v)         = _style('cursor', v)
      def position(v)       = _style('position', v)
      def top(v)            = _style('top', v)
      def left(v)           = _style('left', v)
      def right(v)          = _style('right', v)
      def bottom(v)         = _style('bottom', v)
      def z_index(v)        = _style('z-index', v.to_s)
      def line_height(v)    = _style('line-height', v)
      def font_family(v)    = _style('font-family', v)
      def box_shadow(v)     = _style('box-shadow', v)
      def transition(v)     = _style('transition', v)
      def transform(v)      = _style('transform', v)
      def white_space(v)    = _style('white-space', v)
      def text_overflow(v)  = _style('text-overflow', v)
      def list_style(v)     = _style('list-style', v)

      def add_class(cls)
        s = cls.to_s.b
        _target << "\x06" << (U16_LE[s.bytesize] || [s.bytesize].pack('v')) << s
        self
      end

      def set_id(id)
        s = id.to_s.b
        _target << "\x07" << (U16_LE[s.bytesize] || [s.bytesize].pack('v')) << s
        self
      end

      def set_attr(k, v)
        kb = k.to_s.b; vb = v.to_s.b
        _target << "\x05" <<
          (U16_LE[kb.bytesize] || [kb.bytesize].pack('v')) << kb <<
          (U16_LE[vb.bytesize] || [vb.bytesize].pack('v')) << vb
        self
      end

      def set_style(p, v) = _style(p, v)

      # HTMX shortcuts
      def hx_get(url)     = set_attr('hx-get', url)
      def hx_post(url)    = set_attr('hx-post', url)
      def hx_target(sel)  = set_attr('hx-target', sel)
      def hx_swap(s)      = set_attr('hx-swap', s)

      private

      def _style(prop, val)
        pb = prop.to_s.b; vb = val.to_s.b
        _target << "\x08" <<
          (U16_LE[pb.bytesize] || [pb.bytesize].pack('v')) << pb <<
          (U16_LE[vb.bytesize] || [vb.bytesize].pack('v')) << vb
        self
      end
    end
  end
end
