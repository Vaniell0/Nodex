# frozen_string_literal: true

# Minimal Markdown → HTML converter, pure Ruby, zero dependencies.
# Supports: headers, bold, italic, links, inline code, code blocks,
# unordered/ordered lists, horizontal rules, paragraphs, math ($/$$ via KaTeX).

module Nodex
  module Markdown
    module_function

    def to_html(text)
      lines = text.gsub("\r\n", "\n").split("\n")
      html = +""
      i = 0

      while i < lines.length
        line = lines[i]

        # Blank line
        if line.strip.empty?
          i += 1
          next
        end

        # Fenced code block (```)
        if line.strip.start_with?('```')
          lang = line.strip.sub('```', '').strip
          code_lines = []
          i += 1
          while i < lines.length && !lines[i].strip.start_with?('```')
            code_lines << escape(lines[i])
            i += 1
          end
          i += 1 # skip closing ```
          cls = lang.empty? ? '' : " class=\"language-#{escape(lang)}\""
          html << "<pre><code#{cls}>#{code_lines.join("\n")}</code></pre>\n"
          next
        end

        # Display math ($$...$$) — single-line or multi-line
        if line.strip.start_with?('$$')
          rest = line.strip.delete_prefix('$$')
          if rest.end_with?('$$') && !rest.empty?
            # Single-line: $$ formula $$
            math_content = rest.delete_suffix('$$').strip
            i += 1
          else
            # Multi-line: collect until closing $$
            math_lines = [rest]
            i += 1
            while i < lines.length && !lines[i].strip.end_with?('$$')
              math_lines << lines[i]
              i += 1
            end
            if i < lines.length
              math_lines << lines[i].strip.delete_suffix('$$')
              i += 1
            end
            math_content = math_lines.join("\n").strip
          end
          html << "<div class=\"math-display\">\\[#{escape(math_content)}\\]</div>\n"
          next
        end

        # Horizontal rule
        if line.strip.match?(/\A(-{3,}|\*{3,}|_{3,})\z/)
          html << "<hr>\n"
          i += 1
          next
        end

        # Headers
        if line =~ /\A(\#{1,6})\s+(.*)/
          level = $1.length
          content = inline($2)
          html << "<h#{level}>#{content}</h#{level}>\n"
          i += 1
          next
        end

        # Unordered list
        if line =~ /\A\s*[-*+]\s+(.*)/
          html << "<ul>\n"
          while i < lines.length && lines[i] =~ /\A\s*[-*+]\s+(.*)/
            html << "  <li>#{inline($1)}</li>\n"
            i += 1
          end
          html << "</ul>\n"
          next
        end

        # Ordered list
        if line =~ /\A\s*\d+\.\s+(.*)/
          html << "<ol>\n"
          while i < lines.length && lines[i] =~ /\A\s*\d+\.\s+(.*)/
            html << "  <li>#{inline($1)}</li>\n"
            i += 1
          end
          html << "</ol>\n"
          next
        end

        # Blockquote
        if line.start_with?('>')
          quote_lines = []
          while i < lines.length && lines[i].start_with?('>')
            quote_lines << lines[i].sub(/\A>\s?/, '')
            i += 1
          end
          html << "<blockquote>#{to_html(quote_lines.join("\n"))}</blockquote>\n"
          next
        end

        # Paragraph (collect consecutive non-empty lines)
        para_lines = []
        while i < lines.length && !lines[i].strip.empty? &&
              !lines[i].match?(/\A\#{1,6}\s/) &&
              !lines[i].match?(/\A\s*[-*+]\s/) &&
              !lines[i].match?(/\A\s*\d+\.\s/) &&
              !lines[i].start_with?('```') &&
              !lines[i].strip.start_with?('$$') &&
              !lines[i].start_with?('>')  &&
              !lines[i].strip.match?(/\A(-{3,}|\*{3,}|_{3,})\z/)
          para_lines << lines[i]
          i += 1
        end
        unless para_lines.empty?
          html << "<p>#{inline(para_lines.join("\n"))}</p>\n"
        end
      end

      html
    end

    # Parse Markdown into a Nodex Node tree instead of an HTML string.
    # Block-level elements are proper Nodes; inline content within them
    # is parsed into child text/inline Nodes.
    #
    #   node = Nodex::Markdown.to_node("# Hello\n\nSome **bold** text")
    #   node.to_html         # works
    #   node | Padding(20)   # works — it's a real Node
    #   node.to_docx         # works via C extension
    def to_node(text)
      lines = text.gsub("\r\n", "\n").split("\n")
      children = []
      i = 0

      while i < lines.length
        line = lines[i]

        if line.strip.empty?
          i += 1
          next
        end

        # Fenced code block
        if line.strip.start_with?('```')
          lang = line.strip.sub('```', '').strip
          code_lines = []
          i += 1
          while i < lines.length && !lines[i].strip.start_with?('```')
            code_lines << lines[i]
            i += 1
          end
          i += 1
          code_node = Nodex.pre(nil)
          inner = Nodex.code(code_lines.join("\n"))
          inner.add_class("language-#{lang}") unless lang.empty?
          code_node.append(inner)
          children << code_node
          next
        end

        # Display math
        if line.strip.start_with?('$$')
          math_content = line.strip.delete_prefix('$$')
          if math_content.end_with?('$$')
            math_content = math_content.delete_suffix('$$').strip
            i += 1
          else
            math_lines = [math_content]
            i += 1
            while i < lines.length && !lines[i].strip.end_with?('$$')
              math_lines << lines[i]
              i += 1
            end
            if i < lines.length
              math_lines << lines[i].strip.delete_suffix('$$')
              i += 1
            end
            math_content = math_lines.join("\n").strip
          end
          children << Nodex.math_block(math_content)
          next
        end

        # Horizontal rule
        if line.strip.match?(/\A(-{3,}|\*{3,}|_{3,})\z/)
          children << Nodex.hr
          i += 1
          next
        end

        # Headers
        if line =~ /\A(\#{1,6})\s+(.*)/
          level = $1.length
          heading = Nodex.send("h#{level}", nil)
          inline_nodes($2).each { |n| heading.append(n) }
          children << heading
          i += 1
          next
        end

        # Unordered list
        if line =~ /\A\s*[-*+]\s+(.*)/
          items = []
          while i < lines.length && lines[i] =~ /\A\s*[-*+]\s+(.*)/
            item = Nodex.li(nil)
            inline_nodes($1).each { |n| item.append(n) }
            items << item
            i += 1
          end
          children << Nodex.ul(items)
          next
        end

        # Ordered list
        if line =~ /\A\s*\d+\.\s+(.*)/
          items = []
          while i < lines.length && lines[i] =~ /\A\s*\d+\.\s+(.*)/
            item = Nodex.li(nil)
            inline_nodes($1).each { |n| item.append(n) }
            items << item
            i += 1
          end
          children << Nodex.ol(items)
          next
        end

        # Blockquote
        if line.start_with?('>')
          quote_lines = []
          while i < lines.length && lines[i].start_with?('>')
            quote_lines << lines[i].sub(/\A>\s?/, '')
            i += 1
          end
          inner = to_node(quote_lines.join("\n"))
          bq = Nodex.node('blockquote')
          inner.children&.each { |c| bq.append(c) }
          children << bq
          next
        end

        # Paragraph
        para_lines = []
        while i < lines.length && !lines[i].strip.empty? &&
              !lines[i].match?(/\A\#{1,6}\s/) &&
              !lines[i].match?(/\A\s*[-*+]\s/) &&
              !lines[i].match?(/\A\s*\d+\.\s/) &&
              !lines[i].start_with?('```') &&
              !lines[i].strip.start_with?('$$') &&
              !lines[i].start_with?('>') &&
              !lines[i].strip.match?(/\A(-{3,}|\*{3,}|_{3,})\z/)
          para_lines << lines[i]
          i += 1
        end
        unless para_lines.empty?
          para = Nodex.node('p')
          inline_nodes(para_lines.join("\n")).each { |n| para.append(n) }
          children << para
        end
      end

      Nodex.div(children, class: 'markdown')
    end

    # Parse inline Markdown into an array of Nodex Nodes.
    # Handles: inline math ($...$), bold, italic, code, links, images, plain text.
    def inline_nodes(text)
      nodes = []
      # Tokenize by inline patterns, emit text and inline nodes
      # Order: code > math > image > link > bold > italic
      remaining = text

      while remaining && !remaining.empty?
        # Find the earliest match
        patterns = {
          code:   /`([^`]+)`/,
          math:   /\$([^\$\n]+)\$/,
          img:    /!\[([^\]]*)\]\(([^)]+)\)/,
          link:   /\[([^\]]+)\]\(([^)]+)\)/,
          bold:   /\*\*(.+?)\*\*/,
          italic: /\*(.+?)\*/,
        }

        earliest = nil
        earliest_type = nil
        patterns.each do |type, re|
          m = re.match(remaining)
          if m && (earliest.nil? || m.begin(0) < earliest.begin(0))
            earliest = m
            earliest_type = type
          end
        end

        unless earliest
          nodes << Nodex.text(remaining)
          break
        end

        # Text before match
        if earliest.begin(0) > 0
          nodes << Nodex.text(remaining[0...earliest.begin(0)])
        end

        case earliest_type
        when :code
          nodes << Nodex.code(earliest[1])
        when :math
          nodes << Nodex.math(earliest[1])
        when :img
          nodes << Nodex.img(earliest[2], alt: earliest[1])
        when :link
          nodes << Nodex.a(earliest[1], href: earliest[2])
        when :bold
          nodes << Nodex.strong(earliest[1])
        when :italic
          nodes << Nodex.em(earliest[1])
        end

        remaining = remaining[earliest.end(0)..]
      end

      nodes
    end

    # Process inline formatting (returns HTML string for to_html)
    def inline(text)
      s = escape(text)

      # Inline code (must be before bold/italic to avoid conflicts)
      s = s.gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }

      # Inline math: $...$
      s = s.gsub(/\$([^\$\n]+)\$/) { "<span class=\"math-inline\">\\(#{$1}\\)</span>" }

      # Images: ![alt](src)
      s = s.gsub(/!\[([^\]]*)\]\(([^)]+)\)/) { "<img src=\"#{$2}\" alt=\"#{$1}\">" }

      # Links: [text](url)
      s = s.gsub(/\[([^\]]+)\]\(([^)]+)\)/) { "<a href=\"#{$2}\">#{$1}</a>" }

      # Bold: **text** or __text__
      s = s.gsub(/\*\*(.+?)\*\*/) { "<strong>#{$1}</strong>" }
      s = s.gsub(/__(.+?)__/) { "<strong>#{$1}</strong>" }

      # Italic: *text* or _text_
      s = s.gsub(/\*(.+?)\*/) { "<em>#{$1}</em>" }
      s = s.gsub(/(?<!\w)_(.+?)_(?!\w)/) { "<em>#{$1}</em>" }

      # Line break: two trailing spaces or backslash
      s = s.gsub(/  \n/, "<br>\n")
      s = s.gsub(/\\\n/, "<br>\n")

      s
    end

    def escape(text)
      text.to_s
        .gsub('&', '&amp;')
        .gsub('<', '&lt;')
        .gsub('>', '&gt;')
        .gsub('"', '&quot;')
    end
  end

  # DSL methods
  module_function

  # Markdown → raw HTML string (for quick embedding)
  def markdown(text)
    raw(Markdown.to_html(text))
  end

  # Markdown → Node tree (for pipe/style/render to PDF/DOCX)
  def markdown_node(text)
    Markdown.to_node(text)
  end

  def markdown_file(path)
    markdown(File.read(path))
  end

  def markdown_file_node(path)
    markdown_node(File.read(path))
  end

  # Re-define DSL to pick up new methods
  module DSL
    %i[markdown markdown_node markdown_file markdown_file_node].each do |name|
      unless method_defined?(name)
        define_method(name) { |*a, **kw, &b| Nodex.send(name, *a, **kw, &b) }
      end
    end
  end
end
