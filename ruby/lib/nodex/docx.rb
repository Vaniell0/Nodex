# frozen_string_literal: true

# Pure Ruby DOCX writer — zero dependencies, stdlib only (Zlib).
# Generates valid .docx (OOXML) from Nodex Node tree.
#
# Handles: text, headings (h1-h6), paragraphs, bold/italic/underline,
# strikethrough, color, font-size, alignment, lists (ul/ol nested),
# tables with borders, links, page setup (margins, font, size, spacing).
#
# Usage:
#   docx = Nodex::DocxWriter.render(node, preset: :gost)
#   File.binwrite("output.docx", docx)
#
# For the full-featured renderer (images, colspan, headers/footers),
# use the nodex-native C extension instead.

require 'zlib'
require 'stringio'

module Nodex
  # ── Minimal ZIP writer ───────────────────────────────────────────

  class ZipWriter
    Entry = Struct.new(:name, :data, :crc32, :compressed, :method, :offset)

    def initialize
      @entries = []
    end

    def add(name, data, compress: true)
      crc = Zlib.crc32(data)
      if compress
        # Raw deflate (no zlib header/trailer) — required by ZIP spec
        deflater = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
        deflated = deflater.deflate(data, Zlib::FINISH)
        deflater.close
        @entries << Entry.new(name, data, crc, deflated, 8, 0)
      else
        @entries << Entry.new(name, data, crc, data, 0, 0)
      end
    end

    def to_bytes
      buf = StringIO.new
      buf.binmode

      @entries.each do |e|
        e.offset = buf.pos
        name_b = e.name.encode('UTF-8')
        buf.write([0x04034b50, 20, 0, e.method, 0, 0,
                   e.crc32, e.compressed.bytesize, e.data.bytesize,
                   name_b.bytesize, 0].pack('VvvvvvVVVvv'))
        buf.write(name_b)
        buf.write(e.compressed)
      end

      cd_offset = buf.pos
      @entries.each do |e|
        name_b = e.name.encode('UTF-8')
        buf.write([0x02014b50, 20, 20, 0, e.method, 0, 0,
                   e.crc32, e.compressed.bytesize, e.data.bytesize,
                   name_b.bytesize, 0, 0, 0, 0, 0x20,
                   e.offset].pack('VvvvvvvVVVvvvvvVV'))
        buf.write(name_b)
      end
      cd_size = buf.pos - cd_offset

      buf.write([0x06054b50, 0, 0, @entries.size, @entries.size,
                 cd_size, cd_offset, 0].pack('VvvvvVVv'))

      buf.string
    end
  end

  # ── DOCX Presets ─────────────────────────────────────────────────

  DOCX_PRESETS = {
    gost: {
      font: 'Times New Roman', size: 28, # half-points (14pt)
      line_spacing: 360, # twips (1.5 × 240)
      indent: 709, # twips (1.25cm)
      margin_top: 1134, margin_bottom: 1134, # 20mm
      margin_left: 1701, margin_right: 851, # 30mm / 15mm
    },
    academic: {
      font: 'Times New Roman', size: 24, # 12pt
      line_spacing: 480, # double
      indent: 720, # 1.27cm
      margin_top: 1418, margin_bottom: 1418, # 25mm
      margin_left: 1418, margin_right: 1418,
    },
    report: {
      font: 'Calibri', size: 22, # 11pt
      line_spacing: 276, # 1.15
      indent: 0,
      margin_top: 1418, margin_bottom: 1418,
      margin_left: 1134, margin_right: 1134,
    },
    letter: {
      font: 'Calibri', size: 22, # 11pt
      line_spacing: 240, # single
      indent: 0,
      margin_top: 1134, margin_bottom: 1134,
      margin_left: 1418, margin_right: 1418,
    },
  }.freeze

  # ── DOCX Writer ──────────────────────────────────────────────────

  class DocxWriter
    HEADING_SIZES = { 'h1' => 48, 'h2' => 40, 'h3' => 34, 'h4' => 28, 'h5' => 24, 'h6' => 22 }.freeze

    def self.render(node, preset: nil, **opts)
      new(node, preset: preset, **opts).render
    end

    # Options:
    #   preset:             :gost, :academic, :report, :letter
    #   page_numbers:       true/false — right-aligned page number in footer
    #   first_page_footer:  string — text centered on first page footer (e.g. "Севастополь, 2026")
    #   footer:             string — text for default footer (all pages except first if titlePg)
    def initialize(node, preset: nil, **opts)
      @node = node
      @cfg = DOCX_PRESETS[preset&.to_sym] || DOCX_PRESETS[:report]
      @cfg = @cfg.merge(opts)
      @body = +""
      @list_depth = 0
      @list_type = []
      @rels = []
      @images = [] # [rid, zip_path, binary_data]
      @rel_id = 1
      @img_id = 0
      @has_footer = @cfg[:page_numbers] || @cfg[:first_page_footer]
    end

    def render
      walk(@node)
      zip = ZipWriter.new
      zip.add('[Content_Types].xml', content_types_xml)
      zip.add('_rels/.rels', rels_xml)
      zip.add('word/_rels/document.xml.rels', document_rels_xml)
      zip.add('word/document.xml', document_xml)
      zip.add('word/styles.xml', styles_xml)
      zip.add('word/numbering.xml', numbering_xml)
      if @has_footer
        zip.add('word/footer1.xml', default_footer_xml)
        zip.add('word/footer2.xml', first_page_footer_xml) if @cfg[:first_page_footer]
      end
      @images.each { |_, zp, data| zip.add(zp, data) }
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
      when ':text_node'
        # handled inline by parent
      when ':raw_node'
        # skip raw HTML in DOCX
      when 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'
        rpr = run_props(styles, heading: tag)
        ppr = "<w:pPr><w:pStyle w:val=\"Heading#{tag[1]}\"/></w:pPr>"
        @body << "<w:p>#{ppr}"
        emit_runs(node, rpr)
        @body << "</w:p>"

      when 'p'
        ppr = para_props(styles)
        @body << "<w:p>#{ppr}"
        emit_runs(node, run_props(styles))
        @body << "</w:p>"

      when 'ul', 'ol'
        @list_depth += 1
        @list_type.push(tag == 'ol' ? 1 : 0)
        children.each { |c| walk(c) }
        @list_type.pop
        @list_depth -= 1

      when 'li'
        num_id = @list_type.last == 1 ? 2 : 1
        lvl = @list_depth - 1
        ppr = "<w:pPr><w:numPr><w:ilvl w:val=\"#{lvl}\"/><w:numId w:val=\"#{num_id}\"/></w:numPr></w:pPr>"
        @body << "<w:p>#{ppr}"
        emit_runs(node, run_props(styles))
        @body << "</w:p>"

      when 'table'
        walk_table(node)

      when 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th'
        # handled by walk_table

      when 'br'
        @body << '<w:p/>'

      when 'hr'
        @body << '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="auto"/></w:pBdr></w:pPr></w:p>'

      when '__page_break__'
        @body << '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'

      when 'a'
        href = attrs['href'] || ''
        rid = next_rid
        @rels << [rid, href]
        rpr = run_props(styles).sub('</w:rPr>', '<w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr>')
        @body << "<w:hyperlink r:id=\"#{rid}\">"
        emit_runs(node, rpr)
        @body << '</w:hyperlink>'

      when 'blockquote'
        children.each do |c|
          # Render children as indented paragraphs
          if c.is_a?(Nodex::Node) && c.tag.to_s == 'p'
            ppr = '<w:pPr><w:ind w:left="720"/><w:rPr><w:i/><w:color w:val="666666"/></w:rPr></w:pPr>'
            @body << "<w:p>#{ppr}"
            emit_runs(c, '<w:rPr><w:i/><w:color w:val="666666"/></w:rPr>')
            @body << '</w:p>'
          else
            walk(c)
          end
        end

      when 'pre', 'code'
        if tag == 'pre'
          # Code block: monospace, grey background
          code_text = extract_text(node)
          code_text.split("\n").each do |line|
            @body << '<w:p><w:pPr><w:shd w:val="clear" w:fill="F5F5F5"/></w:pPr>'
            @body << '<w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="20"/></w:rPr>'
            @body << "<w:t xml:space=\"preserve\">#{esc(line)}</w:t></w:r></w:p>"
          end
        else
          # Inline code — handled by emit_runs via styling
          # If standalone, emit as paragraph
          if text
            @body << '<w:p><w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/></w:rPr>'
            @body << "<w:t xml:space=\"preserve\">#{esc(text)}</w:t></w:r></w:p>"
          end
        end

      when 'strong', 'b', 'em', 'i', 'u', 's', 'del', 'span', 'mark', 'small', 'sub', 'sup'
        # Inline elements — handled by emit_runs
        # If at block level, wrap in paragraph
        @body << '<w:p>'
        emit_runs(node, run_props(styles, inline_tag: tag))
        @body << '</w:p>'

      when 'math'
        formula = text || ''
        omml = Nodex::OMML.to_omml(formula)
        if attrs['display'] == 'block'
          @body << "<m:oMathPara><m:oMath>#{omml}</m:oMath></m:oMathPara>"
        else
          # Inline math inside a paragraph
          @body << "<w:p><m:oMath>#{omml}</m:oMath></w:p>"
        end

      when 'div', 'section', 'article', 'nav', 'header', 'footer', 'main', 'aside',
           'figure', 'figcaption', 'details', 'summary', 'form', 'fieldset'
        # Transparent containers
        if text && !text.empty?
          @body << "<w:p>#{para_props(styles)}"
          @body << "<w:r>#{run_props(styles)}<w:t xml:space=\"preserve\">#{esc(text)}</w:t></w:r>"
          @body << '</w:p>'
        end
        children.each { |c| walk(c) }

      when 'img'
        src = attrs['src'] || ''
        emit_image(src, attrs, styles) unless src.empty?

      when 'video', 'audio', 'canvas', 'iframe', 'svg',
           'script', 'style', 'link', 'meta', 'input', 'select', 'textarea', 'button'
        # Skip non-document elements

      else
        # Unknown tag: render text + children
        if text && !text.empty?
          @body << "<w:p><w:r>#{run_props(styles)}<w:t xml:space=\"preserve\">#{esc(text)}</w:t></w:r></w:p>"
        end
        children.each { |c| walk(c) }
      end
    end

    # Emit inline runs for a node's text and children
    def emit_runs(node, rpr)
      text = node.text
      children = node.children || []

      if text && !text.empty?
        @body << "<w:r>#{rpr}<w:t xml:space=\"preserve\">#{esc(text)}</w:t></w:r>"
      end

      children.each do |child|
        next unless child.is_a?(Nodex::Node)
        ctag = child.tag.to_s

        case ctag
        when ':text_node'
          t = child.text || ''
          @body << "<w:r>#{rpr}<w:t xml:space=\"preserve\">#{esc(t)}</w:t></w:r>" unless t.empty?
        when 'strong', 'b'
          child_rpr = rpr.sub('</w:rPr>', '<w:b/></w:rPr>')
          emit_runs(child, child_rpr)
        when 'em', 'i'
          child_rpr = rpr.sub('</w:rPr>', '<w:i/></w:rPr>')
          emit_runs(child, child_rpr)
        when 'u'
          child_rpr = rpr.sub('</w:rPr>', '<w:u w:val="single"/></w:rPr>')
          emit_runs(child, child_rpr)
        when 's', 'del'
          child_rpr = rpr.sub('</w:rPr>', '<w:strike/></w:rPr>')
          emit_runs(child, child_rpr)
        when 'code'
          child_rpr = rpr.sub('</w:rPr>', '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/></w:rPr>')
          emit_runs(child, child_rpr)
        when 'a'
          href = (child.instance_variable_get(:@attrs) || {})['href'] || ''
          rid = next_rid
          @rels << [rid, href]
          link_rpr = rpr.sub('</w:rPr>', '<w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr>')
          @body << "<w:hyperlink r:id=\"#{rid}\">"
          emit_runs(child, link_rpr)
          @body << '</w:hyperlink>'
        when 'math'
          t = child.text || ''
          omml = Nodex::OMML.to_omml(t)
          @body << "<m:oMath>#{omml}</m:oMath>"
        when 'br'
          @body << '<w:r><w:br/></w:r>'
        else
          # Recurse for unknown inline
          emit_runs(child, rpr)
        end
      end
    end

    # ── Table with rowspan/colspan support ────────────────────

    def walk_table(table_node)
      rows = collect_table_rows(table_node)
      return if rows.empty?

      # Build merge map: [row][col] = :covered for cells hidden by rowspan above
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

      # Emit table — 100% width, autofit columns to content
      @body << '<w:tbl><w:tblPr>'
      @body << '<w:tblBorders>'
      %w[w:top w:left w:bottom w:right w:insideH w:insideV].each do |bt|
        @body << "<#{bt} w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
      end
      @body << '<w:tblW w:w="5000" w:type="pct"/>'
      @body << '</w:tblPr>'

      rows.each_with_index do |cells, r|
        @body << '<w:tr>'
        col = 0
        ci = 0
        while col < max_cols
          if merge_map[r][col] == :covered
            @body << '<w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p/></w:tc>'
            col += 1
          elsif ci < cells.length
            cell = cells[ci]
            emit_table_cell(cell)
            col += cell_colspan(cell)
            ci += 1
          else
            col += 1
          end
        end
        @body << '</w:tr>'
      end
      @body << '</w:tbl>'
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

    def emit_table_cell(cell)
      tag = cell.tag.to_s
      attrs = cell.instance_variable_get(:@attrs) || {}
      styles = cell.instance_variable_get(:@styles) || {}
      cs = cell_colspan(cell)
      rs = cell_rowspan(cell)

      @body << '<w:tc><w:tcPr>'
      @body << "<w:gridSpan w:val=\"#{cs}\"/>" if cs > 1
      @body << '<w:vMerge w:val="restart"/>' if rs > 1
      # Vertical alignment: center
      @body << '<w:vAlign w:val="center"/>'
      @body << '</w:tcPr>'

      # Paragraph properties: center alignment for th
      align = styles['text-align']
      align = 'center' if tag == 'th' && !align

      rpr = run_props(styles)
      rpr = rpr.sub('</w:rPr>', '<w:b/></w:rPr>') if tag == 'th'

      ppr = ''
      if align
        jc = case align
             when 'center' then 'center'
             when 'right'  then 'right'
             when 'left'   then 'left'
             else 'left'
             end
        ppr = "<w:pPr><w:jc w:val=\"#{jc}\"/></w:pPr>"
      end

      @body << "<w:p>#{ppr}"

      # Render children (including inline math)
      emit_runs(cell, rpr)
      @body << '</w:p></w:tc>'
    end

    def emit_image(src, attrs, styles)
      data = File.binread(src) rescue return
      return if data.empty?

      ext = File.extname(src).downcase.delete('.')
      ext = 'png' if ext.empty?
      ext = 'jpeg' if ext == 'jpg'

      @img_id += 1
      rid = next_rid
      zip_path = "word/media/image#{@img_id}.#{ext}"
      @images << [rid, zip_path, data]

      # Dimensions in EMU (1px = 9525 EMU, 1in = 914400 EMU)
      cx = 914400 * 4 # default 4 inches
      cy = 914400 * 3 # default 3 inches

      # HTML attrs
      w_str = attrs['width']
      h_str = attrs['height']
      cx = (w_str.to_f * 9525).to_i if w_str && !w_str.empty?
      cy = (h_str.to_f * 9525).to_i if h_str && !h_str.empty?

      # CSS styles override
      sw = styles['width']
      sh = styles['height']
      cx = css_to_emu(sw) if sw && !sw.empty?
      cy = css_to_emu(sh) if sh && !sh.empty?

      @body << '<w:p><w:r><w:drawing>'
      @body << "<wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
      @body << "<wp:extent cx=\"#{cx}\" cy=\"#{cy}\"/>"
      @body << '<wp:docPr/>'
      @body << '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
      @body << '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      @body << '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      @body << '<pic:nvPicPr><pic:cNvPr/><pic:cNvPicPr/></pic:nvPicPr>'
      @body << "<pic:blipFill><a:blip r:embed=\"#{rid}\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
      @body << "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"#{cx}\" cy=\"#{cy}\"/></a:xfrm>"
      @body << '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      @body << '</pic:pic></a:graphicData></a:graphic></wp:inline>'
      @body << '</w:drawing></w:r></w:p>'
    end

    def css_to_emu(val)
      num = val.to_f
      return 0 if num <= 0
      if val.include?('cm') then (num * 360000).to_i
      elsif val.include?('mm') then (num * 36000).to_i
      elsif val.include?('in') then (num * 914400).to_i
      elsif val.include?('pt') then (num * 12700).to_i
      else (num * 9525).to_i # px
      end
    end

    def extract_text(node)
      parts = []
      parts << node.text if node.text
      (node.children || []).each do |c|
        parts << extract_text(c) if c.is_a?(Nodex::Node)
      end
      parts.join
    end

    def run_props(styles, heading: nil, inline_tag: nil)
      rpr = +'<w:rPr>'
      rpr << '<w:b/>' if styles['font-weight'] == 'bold' || inline_tag == 'strong' || inline_tag == 'b'
      rpr << '<w:i/>' if styles['font-style'] == 'italic' || inline_tag == 'em' || inline_tag == 'i'
      rpr << '<w:u w:val="single"/>' if styles['text-decoration']&.include?('underline') || inline_tag == 'u'
      rpr << '<w:strike/>' if styles['text-decoration']&.include?('line-through') || inline_tag == 's' || inline_tag == 'del'
      if (c = parse_color(styles['color']))
        rpr << "<w:color w:val=\"#{c}\"/>"
      end
      if (fs = styles['font-size'])
        hp = css_to_half_pt(fs)
        rpr << "<w:sz w:val=\"#{hp}\"/>" if hp > 0
      elsif heading
        rpr << "<w:sz w:val=\"#{HEADING_SIZES[heading]}\"/>"
      end
      if (ff = styles['font-family'])
        ff = ff.gsub(/['"]/, '')
        rpr << "<w:rFonts w:ascii=\"#{esc(ff)}\" w:hAnsi=\"#{esc(ff)}\"/>"
      end
      rpr << '</w:rPr>'
      rpr
    end

    def para_props(styles)
      ppr = +'<w:pPr>'
      if (ta = styles['text-align'])
        jc = { 'left' => 'start', 'center' => 'center', 'right' => 'end', 'justify' => 'both' }[ta]
        ppr << "<w:jc w:val=\"#{jc}\"/>" if jc
      end
      ppr << '</w:pPr>'
      ppr
    end

    def css_to_half_pt(val)
      num = val.to_f
      return 0 if num <= 0
      if val.include?('px') then (num * 0.75 * 2).round
      elsif val.include?('pt') then (num * 2).round
      elsif val.include?('em') then (num * 12 * 2).round
      elsif val.include?('rem') then (num * 12 * 2).round
      else (num * 2).round # assume pt
      end
    end

    def parse_color(c)
      return nil unless c
      c = c.strip
      return c[1..] if c.start_with?('#') && c.size == 7
      if c.start_with?('#') && c.size == 4
        return c[1..].chars.map { |ch| ch * 2 }.join
      end
      nil
    end

    def next_rid
      @rel_id += 1
      "rId#{@rel_id}"
    end

    def esc(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    # ── OOXML boilerplate ────────────────────────────────────────

    def document_xml
      font = @cfg[:font] || 'Calibri'
      size = @cfg[:size] || 22
      spacing = @cfg[:line_spacing] || 276
      indent = @cfg[:indent] || 0
      mt = @cfg[:margin_top] || 1418
      mb = @cfg[:margin_bottom] || 1418
      ml = @cfg[:margin_left] || 1134
      mr = @cfg[:margin_right] || 1134

      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
          <w:body>
            #{@body}
            <w:sectPr>
              #{footer_refs}
              <w:pgSz w:w="11906" w:h="16838"/>
              <w:pgMar w:top="#{mt}" w:right="#{mr}" w:bottom="#{mb}" w:left="#{ml}" w:header="708" w:footer="708" w:gutter="0"/>
              #{@cfg[:first_page_footer] ? '<w:titlePg/>' : ''}
            </w:sectPr>
          </w:body>
        </w:document>
      XML
    end

    def footer_refs
      return '' unless @has_footer
      refs = +'<w:footerReference w:type="default" r:id="rIdFooter1"/>'
      refs << '<w:footerReference w:type="first" r:id="rIdFooter2"/>' if @cfg[:first_page_footer]
      refs
    end

    def default_footer_xml
      font = @cfg[:font] || 'Calibri'
      size = @cfg[:size] || 22
      if @cfg[:page_numbers]
        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:p>
              <w:pPr><w:jc w:val="end"/></w:pPr>
              <w:r><w:rPr><w:rFonts w:ascii="#{esc(font)}" w:hAnsi="#{esc(font)}"/><w:sz w:val="#{size}"/></w:rPr>
                <w:fldChar w:fldCharType="begin"/>
              </w:r>
              <w:r><w:rPr><w:rFonts w:ascii="#{esc(font)}" w:hAnsi="#{esc(font)}"/><w:sz w:val="#{size}"/></w:rPr>
                <w:instrText xml:space="preserve"> PAGE </w:instrText>
              </w:r>
              <w:r><w:fldChar w:fldCharType="separate"/></w:r>
              <w:r><w:rPr><w:rFonts w:ascii="#{esc(font)}" w:hAnsi="#{esc(font)}"/><w:sz w:val="#{size}"/></w:rPr>
                <w:t>2</w:t>
              </w:r>
              <w:r><w:fldChar w:fldCharType="end"/></w:r>
            </w:p>
          </w:ftr>
        XML
      else
        footer_text = @cfg[:footer] || ''
        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:p><w:r><w:rPr><w:rFonts w:ascii="#{esc(font)}" w:hAnsi="#{esc(font)}"/><w:sz w:val="#{size}"/></w:rPr>
              <w:t>#{esc(footer_text)}</w:t></w:r></w:p>
          </w:ftr>
        XML
      end
    end

    def first_page_footer_xml
      font = @cfg[:font] || 'Calibri'
      size = @cfg[:size] || 22
      text = @cfg[:first_page_footer] || ''
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:p>
            <w:pPr><w:jc w:val="center"/></w:pPr>
            <w:r><w:rPr><w:rFonts w:ascii="#{esc(font)}" w:hAnsi="#{esc(font)}"/><w:sz w:val="#{size}"/></w:rPr>
              <w:t>#{esc(text)}</w:t>
            </w:r>
          </w:p>
        </w:ftr>
      XML
    end

    def styles_xml
      font = @cfg[:font] || 'Calibri'
      size = @cfg[:size] || 22
      spacing = @cfg[:line_spacing] || 276
      indent = @cfg[:indent] || 0

      heading_styles = (1..6).map do |i|
        sz = HEADING_SIZES["h#{i}"]
        <<~S
          <w:style w:type="paragraph" w:styleId="Heading#{i}">
            <w:name w:val="heading #{i}"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="#{sz}"/></w:rPr>
          </w:style>
        S
      end.join

      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault><w:rPr>
              <w:rFonts w:ascii="#{esc(font)}" w:hAnsi="#{esc(font)}"/>
              <w:sz w:val="#{size}"/>
            </w:rPr></w:rPrDefault>
            <w:pPrDefault><w:pPr>
              <w:spacing w:line="#{spacing}" w:lineRule="auto"/>
              #{indent > 0 ? "<w:ind w:firstLine=\"#{indent}\"/>" : ''}
            </w:pPr></w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
          </w:style>
          #{heading_styles}
        </w:styles>
      XML
    end

    def numbering_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="0">
            #{(0..8).map { |i| "<w:lvl w:ilvl=\"#{i}\"><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\u2022\"/><w:pPr><w:ind w:left=\"#{720 * (i + 1)}\" w:hanging=\"360\"/></w:pPr></w:lvl>" }.join}
          </w:abstractNum>
          <w:abstractNum w:abstractNumId="1">
            #{(0..8).map { |i| "<w:lvl w:ilvl=\"#{i}\"><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%#{i + 1}.\"/><w:pPr><w:ind w:left=\"#{720 * (i + 1)}\" w:hanging=\"360\"/></w:pPr></w:lvl>" }.join}
          </w:abstractNum>
          <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
          <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
        </w:numbering>
      XML
    end

    def content_types_xml
      img_types = +""
      has_ext = {}
      @images.each do |_, zp, _|
        ext = File.extname(zp).delete('.')
        next if has_ext[ext]
        has_ext[ext] = true
        ct = { 'png' => 'image/png', 'jpeg' => 'image/jpeg', 'gif' => 'image/gif', 'bmp' => 'image/bmp' }[ext] || 'application/octet-stream'
        img_types << "  <Default Extension=\"#{ext}\" ContentType=\"#{ct}\"/>\n"
      end

      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
        #{img_types}  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
          #{@has_footer ? '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' : ''}
          #{@cfg[:first_page_footer] ? '<Override PartName="/word/footer2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' : ''}
        </Types>
      XML
    end

    def rels_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
      XML
    end

    def document_rels_xml
      links = @rels.map do |rid, href|
        "<Relationship Id=\"#{rid}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"#{esc(href)}\" TargetMode=\"External\"/>"
      end
      imgs = @images.map do |rid, zp, _|
        "<Relationship Id=\"#{rid}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"#{zp.sub('word/', '')}\"/>"
      end
      extra = (links + imgs).join("\n  ")

      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
          <Relationship Id="rId1n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
          #{@has_footer ? '<Relationship Id="rIdFooter1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>' : ''}
          #{@cfg[:first_page_footer] ? '<Relationship Id="rIdFooter2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer2.xml"/>' : ''}
          #{extra}
        </Relationships>
      XML
    end
  end
end
