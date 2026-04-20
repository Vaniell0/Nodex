# frozen_string_literal: true

# Pure Ruby ODT writer — zero dependencies.
# Generates valid .odt (ODF) from Nodex Node tree.
#
# Usage:
#   odt = Nodex::OdtWriter.render(node, preset: :gost)
#   File.binwrite("output.odt", odt)
#
#   node.to_odt("output.odt", preset: :academic)

require 'zlib'

module Nodex
  ODT_PRESETS = {
    gost: {
      font: 'Times New Roman', size: '14pt',
      line_height: '150%', indent: '1.25cm',
      margin_top: '2cm', margin_bottom: '2cm',
      margin_left: '3cm', margin_right: '1.5cm',
    },
    academic: {
      font: 'Times New Roman', size: '12pt',
      line_height: '200%', indent: '1.27cm',
      margin_top: '2.5cm', margin_bottom: '2.5cm',
      margin_left: '2.5cm', margin_right: '2.5cm',
    },
    report: {
      font: 'Calibri', size: '11pt',
      line_height: '115%', indent: nil,
      margin_top: '2.5cm', margin_bottom: '2.5cm',
      margin_left: '2cm', margin_right: '2cm',
    },
    letter: {
      font: 'Calibri', size: '11pt',
      line_height: '100%', indent: nil,
      margin_top: '2cm', margin_bottom: '2cm',
      margin_left: '2.5cm', margin_right: '2.5cm',
    },
  }.freeze

  HEADING_SIZES_ODT = {
    'h1' => '24pt', 'h2' => '20pt', 'h3' => '17pt',
    'h4' => '14pt', 'h5' => '12pt', 'h6' => '11pt',
  }.freeze

  class OdtWriter
    def self.render(node, preset: nil, **opts)
      new(node, preset: preset, **opts).render
    end

    def initialize(node, preset: nil, **opts)
      @node = node
      @cfg = ODT_PRESETS[preset&.to_sym] || ODT_PRESETS[:report]
      @cfg = @cfg.merge(opts.transform_keys(&:to_sym))
      @body = +""
      @styles = +""
      @style_id = 0
      @list_depth = 0
      @list_type = []
      @images = [] # [zip_path, binary_data]
      @img_id = 0
    end

    def render
      walk(@node)
      zip = ZipWriter.new
      zip.add('mimetype', 'application/vnd.oasis.opendocument.text', compress: false)
      zip.add('META-INF/manifest.xml', manifest_xml)
      zip.add('content.xml', content_xml)
      zip.add('styles.xml', styles_xml)
      @images.each { |zp, data| zip.add(zp, data) }
      zip.to_bytes
    end

    private

    def walk(node)
      return unless node.is_a?(Nodex::Node)
      tag = node.tag.to_s
      text = node.text
      children = node.children || []
      styles = node.instance_variable_get(:@styles) || {}
      attrs = node.instance_variable_get(:@attrs) || {}

      case tag
      when ':text_node', ':raw_node'
        # handled inline
      when 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'
        level = tag[1].to_i
        sid = auto_style('paragraph', heading_para_props(level))
        @body << "<text:h text:style-name=\"#{sid}\" text:outline-level=\"#{level}\">"
        emit_inline(node, styles)
        @body << '</text:h>'

      when 'p'
        sid = auto_style('paragraph', para_style_props(styles))
        @body << "<text:p text:style-name=\"#{sid}\">"
        emit_inline(node, styles)
        @body << '</text:p>'

      when 'ul', 'ol'
        @list_depth += 1
        @list_type.push(tag)
        @body << '<text:list>'
        children.each { |c| walk(c) }
        @body << '</text:list>'
        @list_type.pop
        @list_depth -= 1

      when 'li'
        @body << '<text:list-item>'
        sid = auto_style('paragraph', '')
        @body << "<text:p text:style-name=\"#{sid}\">"
        emit_inline(node, styles)
        @body << '</text:p>'
        # Nested lists
        children.each do |c|
          next unless c.is_a?(Nodex::Node)
          ct = c.tag.to_s
          walk(c) if ct == 'ul' || ct == 'ol'
        end
        @body << '</text:list-item>'

      when 'table'
        walk_table(node)

      when 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th'
        # handled by walk_table

      when 'br'
        @body << '<text:p/>'

      when 'hr'
        sid = auto_style('paragraph',
          '<style:paragraph-properties fo:border-bottom="0.5pt solid #000000" fo:padding-bottom="0.1cm"/>')
        @body << "<text:p text:style-name=\"#{sid}\"/>"

      when '__page_break__'
        sid = auto_style('paragraph', '<style:paragraph-properties fo:break-before="page"/>')
        @body << "<text:p text:style-name=\"#{sid}\"/>"

      when 'a'
        href = attrs['href'] || ''
        @body << "<text:a xlink:type=\"simple\" xlink:href=\"#{esc(href)}\">"
        emit_text_content(node)
        @body << '</text:a>'

      when 'blockquote'
        sid = auto_style('paragraph',
          '<style:paragraph-properties fo:margin-left="1.5cm"/>' \
          '<style:text-properties fo:font-style="italic" fo:color="#666666"/>')
        children.each do |c|
          if c.is_a?(Nodex::Node) && c.tag.to_s == 'p'
            @body << "<text:p text:style-name=\"#{sid}\">"
            emit_inline(c, {})
            @body << '</text:p>'
          else
            walk(c)
          end
        end

      when 'pre'
        code_text = extract_text(node)
        msid = auto_style('paragraph',
          '<style:paragraph-properties fo:background-color="#f5f5f5" fo:padding="0.2cm"/>')
        tsid = auto_style('text',
          '<style:text-properties style:font-name="Courier New" fo:font-size="10pt"/>')
        code_text.split("\n").each do |line|
          @body << "<text:p text:style-name=\"#{msid}\">"
          @body << "<text:span text:style-name=\"#{tsid}\">#{esc(line)}</text:span>"
          @body << '</text:p>'
        end

      when 'img'
        src = attrs['src'] || ''
        emit_image(src, attrs, styles) unless src.empty?

      when 'math'
        formula = text || ''
        if attrs['display'] == 'block'
          sid = auto_style('paragraph', '<style:paragraph-properties fo:text-align="center"/>')
          @body << "<text:p text:style-name=\"#{sid}\">"
        else
          @body << '<text:p>' unless @body.end_with?('>')
        end
        tsid = auto_style('text',
          '<style:text-properties style:font-name="Cambria Math" fo:font-style="italic"/>')
        @body << "<text:span text:style-name=\"#{tsid}\">#{esc(formula)}</text:span>"
        @body << '</text:p>'

      when 'div', 'section', 'article', 'nav', 'header', 'footer', 'main', 'aside',
           'figure', 'figcaption', 'details', 'summary', 'form', 'fieldset'
        if text && !text.empty?
          sid = auto_style('paragraph', para_style_props(styles))
          @body << "<text:p text:style-name=\"#{sid}\">#{esc(text)}</text:p>"
        end
        children.each { |c| walk(c) }

      when 'strong', 'b', 'em', 'i', 'u', 's', 'del', 'span', 'code'
        sid = auto_style('paragraph', '')
        @body << "<text:p text:style-name=\"#{sid}\">"
        emit_inline(node, styles)
        @body << '</text:p>'

      else
        if text && !text.empty?
          @body << "<text:p>#{esc(text)}</text:p>"
        end
        children.each { |c| walk(c) }
      end
    end

    def emit_inline(node, styles)
      text = node.text
      children = node.children || []

      if text && !text.empty?
        props = text_style_props(styles)
        if props.empty?
          @body << esc(text)
        else
          sid = auto_style('text', props)
          @body << "<text:span text:style-name=\"#{sid}\">#{esc(text)}</text:span>"
        end
      end

      children.each do |child|
        next unless child.is_a?(Nodex::Node)
        ct = child.tag.to_s
        case ct
        when ':text_node'
          t = child.text || ''
          @body << esc(t) unless t.empty?
        when 'strong', 'b'
          sid = auto_style('text', '<style:text-properties fo:font-weight="bold"/>')
          @body << "<text:span text:style-name=\"#{sid}\">"
          emit_inline(child, {})
          @body << '</text:span>'
        when 'em', 'i'
          sid = auto_style('text', '<style:text-properties fo:font-style="italic"/>')
          @body << "<text:span text:style-name=\"#{sid}\">"
          emit_inline(child, {})
          @body << '</text:span>'
        when 'u'
          sid = auto_style('text', '<style:text-properties style:text-underline-style="solid"/>')
          @body << "<text:span text:style-name=\"#{sid}\">"
          emit_inline(child, {})
          @body << '</text:span>'
        when 'code'
          sid = auto_style('text', '<style:text-properties style:font-name="Courier New"/>')
          @body << "<text:span text:style-name=\"#{sid}\">"
          emit_text_content(child)
          @body << '</text:span>'
        when 'a'
          href = (child.instance_variable_get(:@attrs) || {})['href'] || ''
          @body << "<text:a xlink:type=\"simple\" xlink:href=\"#{esc(href)}\">"
          emit_text_content(child)
          @body << '</text:a>'
        when 'math'
          t = child.text || ''
          sid = auto_style('text', '<style:text-properties style:font-name="Cambria Math" fo:font-style="italic"/>')
          @body << "<text:span text:style-name=\"#{sid}\">#{esc(t)}</text:span>"
        when 'br'
          @body << '<text:line-break/>'
        else
          emit_inline(child, child.instance_variable_get(:@styles) || {})
        end
      end
    end

    def emit_text_content(node)
      @body << esc(node.text) if node.text && !node.text.empty?
      (node.children || []).each do |c|
        next unless c.is_a?(Nodex::Node)
        if c.tag.to_s == ':text_node'
          @body << esc(c.text || '')
        else
          emit_inline(c, {})
        end
      end
    end

    # ── Table with rowspan/colspan ───────────────────────────

    def walk_table(table_node)
      rows = collect_table_rows(table_node)
      return if rows.empty?

      max_cols = rows.map { |cells| cells.sum { |c| cell_colspan(c) } }.max || 0
      merge_map = Array.new(rows.length) { Array.new(max_cols, nil) }

      rows.each_with_index do |cells, r|
        col = 0
        cells.each do |cell|
          col += 1 while col < max_cols && merge_map[r][col]
          cs = cell_colspan(cell)
          rs = cell_rowspan(cell)
          if rs > 1
            (1...rs).each do |dr|
              next if r + dr >= rows.length
              cs.times { |dc| merge_map[r + dr][col + dc] = :covered if col + dc < max_cols }
            end
          end
          col += cs
        end
      end

      @body << '<table:table>'
      rows.each_with_index do |cells, r|
        @body << '<table:table-row>'
        col = 0
        ci = 0
        while col < max_cols
          if merge_map[r][col] == :covered
            @body << '<table:covered-table-cell/>'
            col += 1
          elsif ci < cells.length
            emit_odt_cell(cells[ci])
            col += cell_colspan(cells[ci])
            ci += 1
          else
            col += 1
          end
        end
        @body << '</table:table-row>'
      end
      @body << '</table:table>'
    end

    def collect_table_rows(table_node)
      rows = []
      (table_node.children || []).each do |child|
        next unless child.is_a?(Nodex::Node)
        ct = child.tag.to_s
        if ct == 'tr'
          rows << collect_row_cells(child)
        elsif ct == 'thead' || ct == 'tbody' || ct == 'tfoot'
          (child.children || []).each do |row|
            next unless row.is_a?(Nodex::Node) && row.tag.to_s == 'tr'
            rows << collect_row_cells(row)
          end
        end
      end
      rows
    end

    def collect_row_cells(row_node)
      (row_node.children || []).select { |c| c.is_a?(Nodex::Node) && (c.tag.to_s == 'td' || c.tag.to_s == 'th') }
    end

    def cell_colspan(cell)
      ((cell.instance_variable_get(:@attrs) || {})['colspan'] || '1').to_i
    end

    def cell_rowspan(cell)
      ((cell.instance_variable_get(:@attrs) || {})['rowspan'] || '1').to_i
    end

    def emit_odt_cell(cell)
      tag = cell.tag.to_s
      styles = cell.instance_variable_get(:@styles) || {}
      cs = cell_colspan(cell)
      rs = cell_rowspan(cell)

      cell_sid = auto_style('table-cell',
        '<style:table-cell-properties fo:border="0.5pt solid #000000" fo:padding="0.05cm"/>')
      @body << "<table:table-cell table:style-name=\"#{cell_sid}\""
      @body << " table:number-columns-spanned=\"#{cs}\"" if cs > 1
      @body << " table:number-rows-spanned=\"#{rs}\"" if rs > 1
      @body << '>'

      tsid = auto_style('paragraph', '<style:paragraph-properties fo:text-align="center"/>')
      @body << "<text:p text:style-name=\"#{tsid}\">"
      if tag == 'th'
        ssid = auto_style('text', '<style:text-properties fo:font-weight="bold"/>')
        @body << "<text:span text:style-name=\"#{ssid}\">"
        emit_text_content(cell)
        @body << '</text:span>'
      else
        emit_inline(cell, styles)
      end
      @body << '</text:p></table:table-cell>'
    end

    def emit_image(src, attrs, styles)
      data = File.binread(src) rescue return
      return if data.empty?
      ext = File.extname(src).downcase.delete('.')
      ext = 'png' if ext.empty?
      @img_id += 1
      zip_path = "Pictures/image#{@img_id}.#{ext}"
      @images << [zip_path, data]

      w = styles['width'] || attrs['width']
      h = styles['height'] || attrs['height']
      width = w ? css_to_cm(w) : '10cm'
      height = h ? css_to_cm(h) : '7.5cm'

      @body << '<text:p>'
      @body << "<draw:frame svg:width=\"#{width}\" svg:height=\"#{height}\">"
      @body << "<draw:image xlink:href=\"#{zip_path}\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>"
      @body << '</draw:frame>'
      @body << '</text:p>'
    end

    def extract_text(node)
      parts = []
      parts << node.text if node.text
      (node.children || []).each { |c| parts << extract_text(c) if c.is_a?(Nodex::Node) }
      parts.join
    end

    def css_to_cm(val)
      num = val.to_f
      return '0cm' if num <= 0
      if val.include?('cm') then "#{num}cm"
      elsif val.include?('mm') then "#{num / 10.0}cm"
      elsif val.include?('in') then "#{num * 2.54}cm"
      elsif val.include?('pt') then "#{num / 72.0 * 2.54}cm"
      else "#{num / 96.0 * 2.54}cm" # px
      end
    end

    # ── Auto styles ───────────────────────────────────────────

    def auto_style(family, props_xml)
      @style_id += 1
      name = "S#{@style_id}"
      @styles << "<style:style style:name=\"#{name}\" style:family=\"#{family}\">#{props_xml}</style:style>\n"
      name
    end

    def heading_para_props(level)
      size = HEADING_SIZES_ODT["h#{level}"]
      '<style:paragraph-properties fo:margin-top="0.4cm" fo:margin-bottom="0.2cm"/>' \
      "<style:text-properties fo:font-weight=\"bold\" fo:font-size=\"#{size}\"/>"
    end

    def para_style_props(styles)
      props = +''
      if (ta = styles['text-align'])
        props << "<style:paragraph-properties fo:text-align=\"#{ta}\"/>"
      end
      props
    end

    def text_style_props(styles)
      parts = []
      parts << 'fo:font-weight="bold"' if styles['font-weight'] == 'bold'
      parts << 'fo:font-style="italic"' if styles['font-style'] == 'italic'
      parts << 'style:text-underline-style="solid"' if styles['text-decoration']&.include?('underline')
      parts << 'style:text-line-through-style="solid"' if styles['text-decoration']&.include?('line-through')
      if (c = styles['color']) && c.start_with?('#')
        parts << "fo:color=\"#{c}\""
      end
      if (fs = styles['font-size'])
        parts << "fo:font-size=\"#{fs}\""
      end
      return '' if parts.empty?
      "<style:text-properties #{parts.join(' ')}/>"
    end

    def esc(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    # ── ODF XML boilerplate ───────────────────────────────────

    def content_xml
      font = @cfg[:font] || 'Calibri'
      size = @cfg[:size] || '11pt'
      line_height = @cfg[:line_height] || '115%'
      indent = @cfg[:indent]

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content
          xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
          xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
          xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
          xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
          xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
          xmlns:xlink="http://www.w3.org/1999/xlink"
          xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
          xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
          office:version="1.3">
          <office:font-face-decls>
            <style:font-face style:name="#{esc(font)}" svg:font-family="#{esc(font)}"/>
            <style:font-face style:name="Courier New" svg:font-family="Courier New" style:font-pitch="fixed"/>
            <style:font-face style:name="Cambria Math" svg:font-family="Cambria Math"/>
          </office:font-face-decls>
          <office:automatic-styles>
            <style:style style:name="DefaultPara" style:family="paragraph">
              <style:paragraph-properties fo:line-height="#{line_height}"#{indent ? " fo:text-indent=\"#{indent}\"" : ""}/>
              <style:text-properties style:font-name="#{esc(font)}" fo:font-size="#{size}"/>
            </style:style>
            #{@styles}
          </office:automatic-styles>
          <office:body>
            <office:text>
              #{@body}
            </office:text>
          </office:body>
        </office:document-content>
      XML
    end

    def styles_xml
      mt = @cfg[:margin_top] || '2.5cm'
      mb = @cfg[:margin_bottom] || '2.5cm'
      ml = @cfg[:margin_left] || '2cm'
      mr = @cfg[:margin_right] || '2cm'

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-styles
          xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
          xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
          xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
          xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
          office:version="1.3">
          <office:automatic-styles>
            <style:page-layout style:name="pm1">
              <style:page-layout-properties
                fo:page-width="21cm" fo:page-height="29.7cm" style:print-orientation="portrait"
                fo:margin-top="#{mt}" fo:margin-bottom="#{mb}"
                fo:margin-left="#{ml}" fo:margin-right="#{mr}"/>
            </style:page-layout>
          </office:automatic-styles>
          <office:master-styles>
            <style:master-page style:name="Standard" style:page-layout-name="pm1"/>
          </office:master-styles>
        </office:document-styles>
      XML
    end

    def manifest_xml
      img_entries = @images.map do |zp, _|
        ext = File.extname(zp).delete('.')
        ct = { 'png' => 'image/png', 'jpeg' => 'image/jpeg', 'jpg' => 'image/jpeg', 'gif' => 'image/gif' }[ext] || 'application/octet-stream'
        " <manifest:file-entry manifest:full-path=\"#{zp}\" manifest:media-type=\"#{ct}\"/>"
      end.join("\n")

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">
          <manifest:file-entry manifest:full-path="/" manifest:version="1.3" manifest:media-type="application/vnd.oasis.opendocument.text"/>
          <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
          <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
        #{img_entries}
        </manifest:manifest>
      XML
    end
  end
end
