# frozen_string_literal: true

# LaTeX → OMML (Office Math Markup Language) converter.
# Pure Ruby, zero dependencies. Handles a practical subset of LaTeX math.
#
# Usage:
#   Nodex::OMML.to_omml("\\frac{a}{b}")
#   # => "<m:f><m:num><m:r><m:t>a</m:t></m:r></m:num>..."
#
#   Nodex::OMML.to_omml_para("E = mc^2")  # display (centered)
#
# Supported: \frac, ^, _, \sqrt, \sum/\prod/\int with limits,
# \left/\right delimiters, \overline/\hat/\vec/\bar/\dot/\tilde,
# \text, Greek letters, operators (\pm, \times, \leq, etc.),
# {group} braces.

module Nodex
  module OMML
    # ── Greek letters ──────────────────────────────────────────

    GREEK = {
      'alpha' => "\u03B1", 'beta' => "\u03B2", 'gamma' => "\u03B3", 'delta' => "\u03B4",
      'epsilon' => "\u03B5", 'varepsilon' => "\u03B5", 'zeta' => "\u03B6", 'eta' => "\u03B7",
      'theta' => "\u03B8", 'vartheta' => "\u03D1", 'iota' => "\u03B9", 'kappa' => "\u03BA",
      'lambda' => "\u03BB", 'mu' => "\u03BC", 'nu' => "\u03BD", 'xi' => "\u03BE",
      'pi' => "\u03C0", 'rho' => "\u03C1", 'sigma' => "\u03C3", 'tau' => "\u03C4",
      'upsilon' => "\u03C5", 'phi' => "\u03C6", 'varphi' => "\u03D5", 'chi' => "\u03C7",
      'psi' => "\u03C8", 'omega' => "\u03C9",
      'Gamma' => "\u0393", 'Delta' => "\u0394", 'Theta' => "\u0398", 'Lambda' => "\u039B",
      'Xi' => "\u039E", 'Pi' => "\u03A0", 'Sigma' => "\u03A3", 'Phi' => "\u03A6",
      'Psi' => "\u03A8", 'Omega' => "\u03A9",
    }.freeze

    # ── Operators / symbols ────────────────────────────────────

    SYMBOLS = {
      'pm' => "\u00B1", 'mp' => "\u2213", 'times' => "\u00D7", 'div' => "\u00F7",
      'cdot' => "\u22C5", 'ast' => "\u2217", 'star' => "\u22C6", 'circ' => "\u2218",
      'leq' => "\u2264", 'le' => "\u2264", 'geq' => "\u2265", 'ge' => "\u2265",
      'neq' => "\u2260", 'ne' => "\u2260", 'approx' => "\u2248", 'equiv' => "\u2261",
      'sim' => "\u223C", 'propto' => "\u221D", 'll' => "\u226A", 'gg' => "\u226B",
      'subset' => "\u2282", 'supset' => "\u2283", 'subseteq' => "\u2286", 'supseteq' => "\u2287",
      'in' => "\u2208", 'notin' => "\u2209", 'ni' => "\u220B",
      'cup' => "\u222A", 'cap' => "\u2229", 'setminus' => "\u2216",
      'emptyset' => "\u2205", 'varnothing' => "\u2205",
      'infty' => "\u221E", 'partial' => "\u2202", 'nabla' => "\u2207",
      'forall' => "\u2200", 'exists' => "\u2203",
      'neg' => "\u00AC", 'lnot' => "\u00AC",
      'wedge' => "\u2227", 'land' => "\u2227", 'vee' => "\u2228", 'lor' => "\u2228",
      'oplus' => "\u2295", 'otimes' => "\u2297",
      'to' => "\u2192", 'rightarrow' => "\u2192", 'leftarrow' => "\u2190",
      'Rightarrow' => "\u21D2", 'Leftarrow' => "\u21D0", 'Leftrightarrow' => "\u21D4",
      'dots' => "\u2026", 'ldots' => "\u2026", 'cdots' => "\u22EF", 'vdots' => "\u22EE",
      'quad' => "  ", 'qquad' => "    ",
      'colon' => ":", 'mid' => "\u2223",
    }.freeze

    NARY_CHARS = {
      'sum' => "\u2211", 'prod' => "\u220F", 'coprod' => "\u2210",
      'int' => "\u222B", 'iint' => "\u222C", 'iiint' => "\u222D",
      'oint' => "\u222E",
      'bigcup' => "\u22C3", 'bigcap' => "\u22C2",
      'bigoplus' => "\u2A01", 'bigotimes' => "\u2A02",
    }.freeze

    ACCENTS = {
      'hat' => "\u0302", 'check' => "\u030C", 'tilde' => "\u0303",
      'acute' => "\u0301", 'grave' => "\u0300", 'dot' => "\u0307",
      'ddot' => "\u0308", 'breve' => "\u0306",
      'bar' => "\u0305", 'overline' => "\u0305",
      'vec' => "\u20D7",
    }.freeze

    DELIMITERS = {
      '(' => '(', ')' => ')', '[' => '[', ']' => ']',
      '\\{' => '{', '\\}' => '}', '|' => '|',
      '\\langle' => "\u27E8", '\\rangle' => "\u27E9",
      '.' => '',  # invisible delimiter
    }.freeze

    module_function

    # ── Public API ─────────────────────────────────────────────

    def to_omml(latex)
      tokens = tokenize(latex.strip)
      ast = parse(tokens)
      emit(ast)
    end

    def to_omml_para(latex)
      inner = to_omml(latex)
      "<m:oMathPara><m:oMath>#{inner}</m:oMath></m:oMathPara>"
    end

    # ── Tokenizer ──────────────────────────────────────────────

    Token = Struct.new(:type, :value)

    def tokenize(s)
      tokens = []
      i = 0
      while i < s.length
        c = s[i]
        case c
        when ' ', "\t", "\n"
          i += 1
        when '\\' # command
          j = i + 1
          if j < s.length && s[j] =~ /[a-zA-Z]/
            j += 1 while j < s.length && s[j] =~ /[a-zA-Z]/
            cmd = s[i+1...j]
            tokens << Token.new(:cmd, cmd)
            i = j
          elsif j < s.length
            tokens << Token.new(:char, s[j])
            i = j + 1
          else
            i += 1
          end
        when '{' then tokens << Token.new(:lbrace, '{'); i += 1
        when '}' then tokens << Token.new(:rbrace, '}'); i += 1
        when '^' then tokens << Token.new(:sup, '^'); i += 1
        when '_' then tokens << Token.new(:sub, '_'); i += 1
        else
          tokens << Token.new(:char, c)
          i += 1
        end
      end
      tokens
    end

    # ── Parser → AST ──────────────────────────────────────────

    # AST node types:
    #   [:run, "text"]           — plain text run
    #   [:frac, num_ast, den_ast]
    #   [:sqrt, degree_ast_or_nil, body_ast]
    #   [:sup, base_ast, exp_ast]
    #   [:sub, base_ast, idx_ast]
    #   [:subsup, base_ast, idx_ast, exp_ast]
    #   [:nary, char, sub_ast, sup_ast, body_ast]
    #   [:delim, left_char, body_ast, right_char]
    #   [:accent, combining_char, body_ast]
    #   [:text, "plain text"]
    #   [:group, [children...]]

    def parse(tokens)
      ctx = ParseCtx.new(tokens)
      children = parse_sequence(ctx)
      children.length == 1 ? children[0] : [:group, children]
    end

    class ParseCtx
      attr_accessor :pos
      def initialize(tokens) @tokens = tokens; @pos = 0 end
      def peek() @pos < @tokens.length ? @tokens[@pos] : nil end
      def advance() t = @tokens[@pos]; @pos += 1; t end
      def eof?() @pos >= @tokens.length end
    end

    def parse_sequence(ctx, stop_at_rbrace: false)
      children = []
      while !ctx.eof?
        t = ctx.peek
        break if stop_at_rbrace && t.type == :rbrace

        node = parse_atom(ctx)
        next unless node

        # Check for sub/sup after atom
        node = parse_scripts(ctx, node)
        children << node
      end
      children
    end

    def parse_atom(ctx)
      t = ctx.peek
      return nil unless t

      case t.type
      when :cmd
        parse_command(ctx)
      when :lbrace
        parse_group(ctx)
      when :rbrace
        nil # handled by caller
      when :sup, :sub
        # Orphan sub/sup with no base — use empty run
        parse_scripts(ctx, [:run, ""])
      when :char
        ctx.advance
        [:run, t.value]
      else
        ctx.advance
        [:run, t.value]
      end
    end

    def parse_command(ctx)
      t = ctx.advance # consume :cmd
      cmd = t.value

      # Greek letters
      if GREEK[cmd]
        return [:run, GREEK[cmd]]
      end

      # Symbols/operators
      if SYMBOLS[cmd]
        return [:run, SYMBOLS[cmd]]
      end

      # Nary operators (sum, prod, int)
      if NARY_CHARS[cmd]
        return parse_nary(ctx, NARY_CHARS[cmd])
      end

      case cmd
      when 'frac'
        num = parse_required_group(ctx)
        den = parse_required_group(ctx)
        [:frac, num, den]

      when 'sqrt'
        degree = nil
        if ctx.peek&.type == :char && ctx.peek.value == '['
          ctx.advance # [
          deg_chars = []
          while !ctx.eof? && !(ctx.peek.type == :char && ctx.peek.value == ']')
            deg_chars << ctx.advance.value
          end
          ctx.advance if ctx.peek&.type == :char # ]
          degree = [:run, deg_chars.join]
        end
        body = parse_required_group(ctx)
        [:sqrt, degree, body]

      when 'left'
        left_delim = parse_delimiter(ctx)
        body = parse_sequence(ctx)
        # Expect \right
        if ctx.peek&.type == :cmd && ctx.peek.value == 'right'
          ctx.advance
          right_delim = parse_delimiter(ctx)
        else
          right_delim = ''
        end
        [:delim, left_delim, [:group, body], right_delim]

      when 'right'
        # Orphan \right — return empty (handled by \left parser)
        nil

      when 'overline', 'hat', 'vec', 'bar', 'dot', 'ddot', 'tilde', 'check', 'breve', 'acute', 'grave'
        body = parse_required_group(ctx)
        [:accent, ACCENTS[cmd], body]

      when 'text', 'mathrm', 'textrm'
        body = parse_required_group_raw(ctx)
        [:text, body]

      when 'mathbf', 'textbf'
        body = parse_required_group(ctx)
        # Just render normally (no bold in OMML math runs by default)
        body

      else
        # Unknown command — render as text
        [:run, "\\#{cmd}"]
      end
    end

    def parse_nary(ctx, char)
      # Collect sub/sup if present
      sub_ast = nil
      sup_ast = nil
      2.times do
        if ctx.peek&.type == :sub
          ctx.advance
          sub_ast = parse_required_group(ctx)
        elsif ctx.peek&.type == :sup
          ctx.advance
          sup_ast = parse_required_group(ctx)
        end
      end
      # The body is the next atom (or empty)
      body = ctx.peek && ctx.peek.type != :cmd ? parse_atom(ctx) : [:run, ""]
      body = parse_scripts(ctx, body) if body
      [:nary, char, sub_ast, sup_ast, body || [:run, ""]]
    end

    def parse_scripts(ctx, base)
      sub_ast = nil
      sup_ast = nil
      2.times do
        if ctx.peek&.type == :sub
          ctx.advance
          sub_ast = parse_required_group(ctx)
        elsif ctx.peek&.type == :sup
          ctx.advance
          sup_ast = parse_required_group(ctx)
        end
      end
      if sub_ast && sup_ast
        [:subsup, base, sub_ast, sup_ast]
      elsif sup_ast
        [:sup, base, sup_ast]
      elsif sub_ast
        [:sub, base, sub_ast]
      else
        base
      end
    end

    def parse_group(ctx)
      ctx.advance # consume {
      children = parse_sequence(ctx, stop_at_rbrace: true)
      ctx.advance if ctx.peek&.type == :rbrace # consume }
      children.length == 1 ? children[0] : [:group, children]
    end

    def parse_required_group(ctx)
      if ctx.peek&.type == :lbrace
        parse_group(ctx)
      elsif ctx.peek && ctx.peek.type != :rbrace
        parse_atom(ctx) || [:run, ""]
      else
        [:run, ""]
      end
    end

    def parse_required_group_raw(ctx)
      if ctx.peek&.type == :lbrace
        ctx.advance # {
        text = +""
        depth = 1
        while !ctx.eof? && depth > 0
          t = ctx.advance
          if t.type == :lbrace then depth += 1; text << '{'
          elsif t.type == :rbrace then depth -= 1; text << '}' if depth > 0
          else text << (t.value || '')
          end
        end
        text
      else
        t = ctx.advance
        t ? t.value : ""
      end
    end

    def parse_delimiter(ctx)
      t = ctx.peek
      return '' unless t
      if t.type == :char
        ctx.advance
        DELIMITERS[t.value] || t.value
      elsif t.type == :cmd
        ctx.advance
        key = "\\#{t.value}"
        DELIMITERS[key] || t.value
      else
        ''
      end
    end

    # ── OMML Emitter ──────────────────────────────────────────

    def emit(ast)
      return '' unless ast

      case ast[0]
      when :run
        run(ast[1])

      when :group
        ast[1].map { |c| emit(c) }.join

      when :frac
        "<m:f><m:num>#{emit(ast[1])}</m:num><m:den>#{emit(ast[2])}</m:den></m:f>"

      when :sqrt
        deg = ast[1]
        body = ast[2]
        if deg
          "<m:rad><m:radPr><m:degHide m:val=\"0\"/></m:radPr><m:deg>#{emit(deg)}</m:deg><m:e>#{emit(body)}</m:e></m:rad>"
        else
          "<m:rad><m:radPr><m:degHide m:val=\"1\"/></m:radPr><m:deg/><m:e>#{emit(body)}</m:e></m:rad>"
        end

      when :sup
        "<m:sSup><m:e>#{emit(ast[1])}</m:e><m:sup>#{emit(ast[2])}</m:sup></m:sSup>"

      when :sub
        "<m:sSub><m:e>#{emit(ast[1])}</m:e><m:sub>#{emit(ast[2])}</m:sub></m:sSub>"

      when :subsup
        "<m:sSubSup><m:e>#{emit(ast[1])}</m:e><m:sub>#{emit(ast[2])}</m:sub><m:sup>#{emit(ast[3])}</m:sup></m:sSubSup>"

      when :nary
        chr, sub_a, sup_a, body = ast[1], ast[2], ast[3], ast[4]
        s = +"<m:nary><m:naryPr><m:chr m:val=\"#{esc(chr)}\"/>"
        s << '<m:subHide m:val="1"/>' unless sub_a
        s << '<m:supHide m:val="1"/>' unless sup_a
        s << '</m:naryPr>'
        s << "<m:sub>#{sub_a ? emit(sub_a) : ''}</m:sub>"
        s << "<m:sup>#{sup_a ? emit(sup_a) : ''}</m:sup>"
        s << "<m:e>#{emit(body)}</m:e>"
        s << '</m:nary>'

      when :delim
        left, body, right = ast[1], ast[2], ast[3]
        s = +'<m:d>'
        s << '<m:dPr>'
        s << "<m:begChr m:val=\"#{esc(left)}\"/>" unless left == '('
        s << "<m:endChr m:val=\"#{esc(right)}\"/>" unless right == ')'
        s << '</m:dPr>'
        s << "<m:e>#{emit(body)}</m:e>"
        s << '</m:d>'

      when :accent
        combining, body = ast[1], ast[2]
        "<m:acc><m:accPr><m:chr m:val=\"#{esc(combining)}\"/></m:accPr><m:e>#{emit(body)}</m:e></m:acc>"

      when :text
        "<m:r><m:rPr><m:nor/></m:rPr><m:t>#{esc(ast[1])}</m:t></m:r>"

      else
        ''
      end
    end

    def run(text)
      return '' if text.nil? || text.empty?
      "<m:r><m:t>#{esc(text)}</m:t></m:r>"
    end

    def esc(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end
  end
end
