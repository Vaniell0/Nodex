# frozen_string_literal: true

# Tests for DOCX/ODT export.
# Run: cd nodex-native && rake compile && ruby test/test_docx.rb

$LOAD_PATH.unshift File.expand_path('../../ruby/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'nodex'
require 'nodex/native'
require 'tempfile'

module DocxTests
  @passed = 0
  @failed = 0

  def self.assert_eq(desc, actual, expected)
    if actual == expected
      @passed += 1
    else
      @failed += 1
      $stderr.puts "  FAIL: #{desc}"
      $stderr.puts "    expected: #{expected.inspect[0..200]}"
      $stderr.puts "    actual:   #{actual.inspect[0..200]}"
    end
  end

  def self.assert(desc)
    if yield
      @passed += 1
    else
      @failed += 1
      $stderr.puts "  FAIL: #{desc}"
    end
  rescue => e
    @failed += 1
    $stderr.puts "  ERROR: #{desc} — #{e.message}"
  end

  def self.summary
    total = @passed + @failed
    if @failed > 0
      puts "\n#{total} tests, #{@failed} FAILED"
      exit 1
    else
      puts "#{total} tests, all passed"
    end
  end

  # Extract a named file from a ZIP binary string (STORE only)
  def self.zip_entry(zip_data, name)
    offset = 0
    while offset < zip_data.bytesize - 4
      sig = zip_data[offset, 4].unpack1('V')
      break if sig != 0x04034B50 # not a local file header

      name_len = zip_data[offset + 26, 2].unpack1('v')
      extra_len = zip_data[offset + 28, 2].unpack1('v')
      comp_size = zip_data[offset + 18, 4].unpack1('V')
      entry_name = zip_data[offset + 30, name_len]
      data_offset = offset + 30 + name_len + extra_len

      if entry_name == name
        return zip_data[data_offset, comp_size]
      end

      offset = data_offset + comp_size
    end
    nil
  end

  # Extract document.xml from DOCX binary (returns UTF-8 string)
  def self.doc_xml(docx)
    data = zip_entry(docx, 'word/document.xml')
    data&.force_encoding('UTF-8')
  end

  def self.run
    puts "=== DOCX/ODT export tests ==="

    test_docx_is_valid_zip
    test_docx_has_required_files
    test_docx_basic_paragraph
    test_docx_heading_levels
    test_docx_text_formatting
    test_docx_color
    test_docx_font_size
    test_docx_font_family
    test_docx_text_align
    test_docx_br
    test_docx_hr
    test_docx_containers
    test_docx_nested_inline
    test_docx_code_pre
    test_docx_margin_padding
    test_docx_xml_escaping
    test_docx_utf8
    test_docx_empty_tree
    test_docx_large_tree
    test_docx_node_method
    test_docx_native_method
    test_docx_writes_openable_file
    test_docx_unordered_list
    test_docx_ordered_list
    test_docx_nested_list
    test_docx_table
    test_docx_table_with_header
    test_docx_hyperlink
    test_docx_image
    test_odt_valid_zip
    test_odt_has_required_files
    test_odt_paragraph
    test_odt_headings
    test_odt_formatting
    test_odt_color
    test_odt_containers
    test_odt_br
    test_odt_lists
    test_odt_table
    test_odt_hyperlink
    test_odt_image
    test_odt_code_pre
    test_odt_utf8
    test_odt_node_method
    test_odt_native_method
    test_docx_border
    test_docx_colspan
    test_docx_page_config
    test_docx_page_a4
    test_odt_colspan
    test_odt_page_config

    # v1.3 — page breaks, headers/footers, doc config, GOST
    test_docx_justify_both
    test_docx_page_break
    test_docx_css_page_break_before
    test_docx_default_font
    test_docx_default_font_size
    test_docx_line_spacing
    test_docx_first_line_indent
    test_docx_header_footer_zip
    test_docx_page_numbers
    test_docx_first_page_footer
    test_docx_gost_preset
    test_docx_page_break_factory
    test_odt_page_break
    test_odt_default_font
    test_odt_footer_page_number

    summary
  end

  def self.test_docx_is_valid_zip
    puts "  valid ZIP..."
    docx = Nodex.p("Hello").to_docx
    assert("binary encoding") { docx.encoding == Encoding::ASCII_8BIT }
    assert("starts with PK") { docx[0, 2] == "PK" }
    assert("has end-of-central-dir") { docx.include?([0x06054B50].pack('V')) }
  end

  def self.test_docx_has_required_files
    puts "  required ZIP entries..."
    docx = Nodex.p("Hello").to_docx
    assert("has [Content_Types].xml") { zip_entry(docx, '[Content_Types].xml') }
    assert("has _rels/.rels") { zip_entry(docx, '_rels/.rels') }
    assert("has word/document.xml") { zip_entry(docx, 'word/document.xml') }
    assert("has word/styles.xml") { zip_entry(docx, 'word/styles.xml') }
    assert("has word/_rels/document.xml.rels") { zip_entry(docx, 'word/_rels/document.xml.rels') }
  end

  def self.test_docx_basic_paragraph
    puts "  basic paragraph..."
    xml = doc_xml(Nodex.p("Hello world").to_docx)
    assert("has w:p") { xml.include?('<w:p>') || xml.include?('<w:p ') }
    assert("has w:r") { xml.include?('<w:r>') }
    assert("has text") { xml.include?('Hello world') }
  end

  def self.test_docx_heading_levels
    puts "  heading levels..."
    (1..6).each do |n|
      node = Nodex.send("h#{n}", "Heading #{n}")
      xml = doc_xml(node.to_docx)
      assert("h#{n} has Heading#{n} style") { xml.include?("Heading#{n}") }
      assert("h#{n} has text") { xml.include?("Heading #{n}") }
    end
  end

  def self.test_docx_text_formatting
    puts "  text formatting..."

    xml = doc_xml(Nodex.node("p", children: [Nodex.strong("bold text")]).to_docx)
    assert("strong → w:b") { xml.include?('<w:b/>') }
    assert("strong has text") { xml.include?('bold text') }

    xml = doc_xml(Nodex.node("p", children: [Nodex.em("italic text")]).to_docx)
    assert("em → w:i") { xml.include?('<w:i/>') }

    xml = doc_xml(Nodex.p("underlined").set_style("text-decoration", "underline").to_docx)
    assert("underline → w:u") { xml.include?('w:u') }

    xml = doc_xml(Nodex.p("struck").set_style("text-decoration", "line-through").to_docx)
    assert("strikethrough → w:strike") { xml.include?('<w:strike/>') }

    # Bold via style
    xml = doc_xml(Nodex.p("style-bold").bold.to_docx)
    assert("bold style → w:b") { xml.include?('<w:b/>') }

    # Italic via style
    xml = doc_xml(Nodex.p("style-italic").italic.to_docx)
    assert("italic style → w:i") { xml.include?('<w:i/>') }
  end

  def self.test_docx_color
    puts "  color..."
    xml = doc_xml(Nodex.p("red text").color("red").to_docx)
    assert("named color → w:color") { xml.include?('w:color') && xml.include?('FF0000') }

    xml = doc_xml(Nodex.p("hex color").color("#336699").to_docx)
    assert("hex color → w:color") { xml.include?('336699') }

    xml = doc_xml(Nodex.p("bg").bg_color("#FFCC00").to_docx)
    assert("bg_color → w:shd") { xml.include?('w:shd') && xml.include?('FFCC00') }
  end

  def self.test_docx_font_size
    puts "  font size..."
    xml = doc_xml(Nodex.p("big").font_size("24pt").to_docx)
    # 24pt = 48 half-points
    assert("font-size → w:sz val=48") { xml.include?('w:sz') && xml.include?('"48"') }
  end

  def self.test_docx_font_family
    puts "  font family..."
    xml = doc_xml(Nodex.p("arial").set_style("font-family", "Arial").to_docx)
    assert("font-family → w:rFonts") { xml.include?('w:rFonts') && xml.include?('Arial') }
  end

  def self.test_docx_text_align
    puts "  text alignment..."
    xml = doc_xml(Nodex.p("centered").set_style("text-align", "center").to_docx)
    assert("text-align center → w:jc") { xml.include?('w:jc') && xml.include?('center') }

    xml = doc_xml(Nodex.p("right").set_style("text-align", "right").to_docx)
    assert("text-align right → w:jc end") { xml.include?('w:jc') && xml.include?('end') }
  end

  def self.test_docx_br
    puts "  line break..."
    xml = doc_xml(Nodex.node("p", children: [Nodex.text("line1"), Nodex.br, Nodex.text("line2")]).to_docx)
    assert("br → w:br") { xml.include?('<w:br/>') }
    assert("has both lines") { xml.include?('line1') && xml.include?('line2') }
  end

  def self.test_docx_hr
    puts "  horizontal rule..."
    xml = doc_xml(Nodex.div([Nodex.p("above"), Nodex.hr, Nodex.p("below")]).to_docx)
    assert("hr → pBdr bottom") { xml.include?('w:pBdr') && xml.include?('w:bottom') }
  end

  def self.test_docx_containers
    puts "  containers..."
    tree = Nodex.div([
      Nodex.section([
        Nodex.article([Nodex.p("Deep content")])
      ])
    ])
    xml = doc_xml(tree.to_docx)
    assert("container children rendered") { xml.include?('Deep content') }
  end

  def self.test_docx_nested_inline
    puts "  nested inline..."
    tree = Nodex.node("p", children: [
      Nodex.node("strong", children: [Nodex.em("bold-italic")])
    ])
    xml = doc_xml(tree.to_docx)
    assert("nested bold+italic") { xml.include?('<w:b/>') && xml.include?('<w:i/>') }
    assert("has text") { xml.include?('bold-italic') }
  end

  def self.test_docx_code_pre
    puts "  code/pre..."
    xml = doc_xml(Nodex.node("p", children: [Nodex.code("monospace")]).to_docx)
    assert("code → Courier New") { xml.include?('Courier New') }

    xml = doc_xml(Nodex.pre("preformatted").to_docx)
    assert("pre → Courier New") { xml.include?('Courier New') }
  end

  def self.test_docx_margin_padding
    puts "  margin/padding..."
    xml = doc_xml(Nodex.p("spaced").margin("20px").padding("10px").to_docx)
    assert("margin → w:spacing") { xml.include?('w:spacing') }
    assert("padding → w:ind") { xml.include?('w:ind') }
  end

  def self.test_docx_xml_escaping
    puts "  XML escaping..."
    xml = doc_xml(Nodex.p("A & B < C > D \"E\"").to_docx)
    assert("& escaped") { xml.include?('A &amp; B') }
    assert("< escaped") { xml.include?('&lt; C') }
    assert("> escaped") { xml.include?('&gt; D') }
  end

  def self.test_docx_utf8
    puts "  UTF-8..."
    xml = doc_xml(Nodex.p("Привет мир 🎉").to_docx)
    assert("cyrillic preserved") { xml.include?('Привет мир') }
    assert("emoji preserved") { xml.include?('🎉') }
  end

  def self.test_docx_empty_tree
    puts "  empty tree..."
    docx = Nodex.div.to_docx
    assert("empty div produces valid ZIP") { docx[0, 2] == "PK" }
    xml = doc_xml(docx)
    assert("has document xml") { xml && xml.include?('w:document') }
  end

  def self.test_docx_large_tree
    puts "  large tree (100 nodes)..."
    tree = Nodex.div((1..100).map { |i|
      Nodex.div([
        Nodex.h1("Item #{i}").bold.color("#333"),
        Nodex.p("Desc #{i}").padding("10px"),
      ])
    })
    docx = tree.to_docx
    assert("large tree valid ZIP") { docx[0, 2] == "PK" }
    xml = doc_xml(docx)
    assert("has first item") { xml.include?('Item 1') }
    assert("has last item") { xml.include?('Item 100') }
  end

  def self.test_docx_node_method
    puts "  Node#to_docx..."
    docx = Nodex.h1("Test").to_docx
    assert("returns binary string") { docx.is_a?(String) && docx.encoding == Encoding::ASCII_8BIT }
    assert("is a DOCX") { docx[0, 2] == "PK" }
  end

  def self.test_docx_native_method
    puts "  Native.to_docx..."
    docx = Nodex::Native.to_docx(Nodex.p("test"))
    assert("returns binary string") { docx.is_a?(String) }
    assert("is a DOCX") { docx[0, 2] == "PK" }
  end

  def self.test_docx_writes_openable_file
    puts "  write to file..."
    tree = Nodex.div([
      Nodex.h1("Nodex DOCX Export Test").bold.color("#333"),
      Nodex.p("This document was generated by nodex-native.").italic,
      Nodex.node("p", children: [
        Nodex.text("Mixed "),
        Nodex.strong("bold"),
        Nodex.text(" and "),
        Nodex.em("italic"),
        Nodex.text(" text."),
      ]),
      Nodex.h2("Code Example"),
      Nodex.pre("def hello\n  puts 'world'\nend"),
      Nodex.hr,
      Nodex.p("Footer text").color("gray"),
    ])

    f = Tempfile.new(['nodex_test', '.docx'])
    f.binmode
    f.write(tree.to_docx)
    f.close

    size = File.size(f.path)
    assert("file written (#{size} bytes)") { size > 100 }

    # Verify it's a valid ZIP by checking we can extract document.xml
    data = File.binread(f.path)
    xml = doc_xml(data)
    assert("file contains valid document.xml") { xml && xml.include?('w:document') }

    f.unlink
  end

  def self.test_docx_unordered_list
    puts "  unordered list..."
    tree = Nodex.ul([Nodex.li("Apple"), Nodex.li("Banana"), Nodex.li("Cherry")])
    docx = tree.to_docx
    xml = doc_xml(docx)
    assert("ul has w:numPr") { xml.include?('w:numPr') }
    assert("ul has all items") { xml.include?('Apple') && xml.include?('Banana') && xml.include?('Cherry') }

    # Check numbering.xml exists
    num_xml = zip_entry(docx, 'word/numbering.xml')&.force_encoding('UTF-8')
    assert("has numbering.xml") { num_xml }
    assert("has bullet format") { num_xml&.include?('bullet') }
  end

  def self.test_docx_ordered_list
    puts "  ordered list..."
    tree = Nodex.ol([Nodex.li("First"), Nodex.li("Second"), Nodex.li("Third")])
    docx = tree.to_docx
    xml = doc_xml(docx)
    assert("ol has w:numPr") { xml.include?('w:numPr') }
    assert("ol has items") { xml.include?('First') && xml.include?('Second') }

    num_xml = zip_entry(docx, 'word/numbering.xml')&.force_encoding('UTF-8')
    assert("has decimal format") { num_xml&.include?('decimal') }
  end

  def self.test_docx_nested_list
    puts "  nested list..."
    tree = Nodex.ul([
      Nodex.li("Parent"),
      Nodex.node("li", children: [
        Nodex.text("With sub"),
        Nodex.ul([Nodex.li("Child 1"), Nodex.li("Child 2")])
      ])
    ])
    docx = tree.to_docx
    xml = doc_xml(docx)
    assert("nested has all items") { xml.include?('Parent') && xml.include?('Child 1') && xml.include?('Child 2') }
    # Nested items should have ilvl=1
    assert("nested has level 1") { xml.include?('"1"') }
  end

  def self.test_docx_table
    puts "  table..."
    tree = Nodex.node("table", children: [
      Nodex.node("tr", children: [
        Nodex.node("td", text: "Cell 1"),
        Nodex.node("td", text: "Cell 2"),
      ]),
      Nodex.node("tr", children: [
        Nodex.node("td", text: "Cell 3"),
        Nodex.node("td", text: "Cell 4"),
      ]),
    ])
    xml = doc_xml(tree.to_docx)
    assert("has w:tbl") { xml.include?('w:tbl') }
    assert("has w:tr") { xml.include?('w:tr') }
    assert("has w:tc") { xml.include?('w:tc') }
    assert("has all cells") {
      xml.include?('Cell 1') && xml.include?('Cell 2') &&
      xml.include?('Cell 3') && xml.include?('Cell 4')
    }
    assert("has table borders") { xml.include?('w:tblBorders') }
  end

  def self.test_docx_table_with_header
    puts "  table with header..."
    tree = Nodex.node("table", children: [
      Nodex.node("tr", children: [
        Nodex.node("th", text: "Name"),
        Nodex.node("th", text: "Value"),
      ]),
      Nodex.node("tr", children: [
        Nodex.node("td", text: "foo"),
        Nodex.node("td", text: "bar"),
      ]),
    ])
    xml = doc_xml(tree.to_docx)
    assert("th has bold (w:b)") { xml.include?('<w:b/>') }
    assert("has header text") { xml.include?('Name') && xml.include?('Value') }
  end

  def self.test_docx_hyperlink
    puts "  hyperlink..."
    tree = Nodex.div([Nodex.a("Click here", href: "https://example.com")])
    docx = tree.to_docx
    xml = doc_xml(docx)
    assert("has w:hyperlink") { xml.include?('w:hyperlink') }
    assert("has link text") { xml.include?('Click here') }
    assert("has blue color") { xml.include?('0563C1') }

    # Check relationship
    rels_xml = zip_entry(docx, 'word/_rels/document.xml.rels')&.force_encoding('UTF-8')
    assert("has hyperlink relationship") { rels_xml&.include?('https://example.com') }
    assert("relationship is External") { rels_xml&.include?('External') }
  end

  def self.test_docx_image
    puts "  image..."
    # Create a minimal 1x1 PNG for testing
    png_data = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, # IDAT chunk
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
      0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, # IEND chunk
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ].pack('C*')

    f = Tempfile.new(['test_img', '.png'])
    f.binmode
    f.write(png_data)
    f.close

    tree = Nodex.img(f.path, alt: "test image")
    docx = tree.to_docx
    xml = doc_xml(docx)
    assert("has w:drawing") { xml.include?('w:drawing') }
    assert("has wp:inline") { xml.include?('wp:inline') }
    assert("has pic:pic") { xml.include?('pic:pic') }

    # Check image is embedded in ZIP
    img_data = zip_entry(docx, 'word/media/image1.png')
    assert("image embedded in ZIP") { img_data && img_data.bytesize == png_data.bytesize }

    f.unlink
  end
  # ── ODT helper ──────────────────────────────────────────────

  def self.odt_content(odt)
    data = zip_entry(odt, 'content.xml')
    data&.force_encoding('UTF-8')
  end

  # ── ODT tests ──────────────────────────────────────────────

  def self.test_odt_valid_zip
    puts "  ODT: valid ZIP..."
    odt = Nodex.p("Hello").to_odt
    assert("binary encoding") { odt.encoding == Encoding::ASCII_8BIT }
    assert("starts with PK") { odt[0, 2] == "PK" }
    assert("has mimetype") { zip_entry(odt, 'mimetype') == 'application/vnd.oasis.opendocument.text' }
  end

  def self.test_odt_has_required_files
    puts "  ODT: required files..."
    odt = Nodex.p("Hello").to_odt
    assert("has content.xml") { zip_entry(odt, 'content.xml') }
    assert("has styles.xml") { zip_entry(odt, 'styles.xml') }
    assert("has manifest.xml") { zip_entry(odt, 'META-INF/manifest.xml') }
  end

  def self.test_odt_paragraph
    puts "  ODT: paragraph..."
    xml = odt_content(Nodex.p("Hello world").to_odt)
    assert("has text:p") { xml.include?('text:p') }
    assert("has text") { xml.include?('Hello world') }
  end

  def self.test_odt_headings
    puts "  ODT: headings..."
    (1..6).each do |n|
      node = Nodex.send("h#{n}", "Heading #{n}")
      xml = odt_content(node.to_odt)
      assert("h#{n} has text:h") { xml.include?('text:h') }
      assert("h#{n} has outline-level=#{n}") { xml.include?("text:outline-level=\"#{n}\"") }
      assert("h#{n} has text") { xml.include?("Heading #{n}") }
    end
  end

  def self.test_odt_formatting
    puts "  ODT: formatting..."
    xml = odt_content(Nodex.p("bold").bold.to_odt)
    assert("bold → fo:font-weight") { xml.include?('fo:font-weight="bold"') }

    xml = odt_content(Nodex.p("italic").italic.to_odt)
    assert("italic → fo:font-style") { xml.include?('fo:font-style="italic"') }

    xml = odt_content(Nodex.p("underline").set_style("text-decoration", "underline").to_odt)
    assert("underline → text-underline-style") { xml.include?('style:text-underline-style') }

    xml = odt_content(Nodex.p("strike").set_style("text-decoration", "line-through").to_odt)
    assert("strike → text-line-through-style") { xml.include?('style:text-line-through-style') }
  end

  def self.test_odt_color
    puts "  ODT: color..."
    xml = odt_content(Nodex.p("red").color("red").to_odt)
    assert("color → fo:color") { xml.include?('fo:color="#FF0000"') }

    xml = odt_content(Nodex.p("bg").bg_color("#FFCC00").to_odt)
    assert("bg_color → fo:background-color") { xml.include?('fo:background-color="#FFCC00"') }
  end

  def self.test_odt_containers
    puts "  ODT: containers..."
    tree = Nodex.div([Nodex.section([Nodex.p("Deep")])])
    xml = odt_content(tree.to_odt)
    assert("container children rendered") { xml.include?('Deep') }
  end

  def self.test_odt_br
    puts "  ODT: line break..."
    tree = Nodex.node("p", children: [Nodex.text("a"), Nodex.br, Nodex.text("b")])
    xml = odt_content(tree.to_odt)
    assert("br → text:line-break") { xml.include?('text:line-break') }
  end

  def self.test_odt_lists
    puts "  ODT: lists..."
    tree = Nodex.ul([Nodex.li("Item 1"), Nodex.li("Item 2")])
    xml = odt_content(tree.to_odt)
    assert("has text:list") { xml.include?('text:list') }
    assert("has text:list-item") { xml.include?('text:list-item') }
    assert("has items") { xml.include?('Item 1') && xml.include?('Item 2') }
  end

  def self.test_odt_table
    puts "  ODT: table..."
    tree = Nodex.node("table", children: [
      Nodex.node("tr", children: [
        Nodex.node("td", text: "A"),
        Nodex.node("td", text: "B"),
      ])
    ])
    xml = odt_content(tree.to_odt)
    assert("has table:table") { xml.include?('table:table') }
    assert("has table:table-row") { xml.include?('table:table-row') }
    assert("has table:table-cell") { xml.include?('table:table-cell') }
    assert("has cell text") { xml.include?('A') && xml.include?('B') }
  end

  def self.test_odt_hyperlink
    puts "  ODT: hyperlink..."
    tree = Nodex.div([Nodex.a("Click", href: "https://example.com")])
    xml = odt_content(tree.to_odt)
    assert("has text:a") { xml.include?('text:a') }
    assert("has xlink:href") { xml.include?('https://example.com') }
    assert("has link text") { xml.include?('Click') }
  end

  def self.test_odt_image
    puts "  ODT: image..."
    png_data = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
      0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ].pack('C*')

    f = Tempfile.new(['test_img', '.png'])
    f.binmode
    f.write(png_data)
    f.close

    tree = Nodex.img(f.path, alt: "test")
    odt = tree.to_odt
    xml = odt_content(odt)
    assert("has draw:frame") { xml.include?('draw:frame') }
    assert("has draw:image") { xml.include?('draw:image') }

    img = zip_entry(odt, 'Pictures/image1.png')
    assert("image in ZIP") { img && img.bytesize == png_data.bytesize }

    f.unlink
  end

  def self.test_odt_code_pre
    puts "  ODT: code/pre..."
    xml = odt_content(Nodex.node("p", children: [Nodex.code("mono")]).to_odt)
    assert("code → Courier New") { xml.include?('Courier New') }
  end

  def self.test_odt_utf8
    puts "  ODT: UTF-8..."
    xml = odt_content(Nodex.p("Привет 🎉").to_odt)
    assert("cyrillic") { xml.include?('Привет') }
    assert("emoji") { xml.include?('🎉') }
  end

  def self.test_odt_node_method
    puts "  ODT: Node#to_odt..."
    odt = Nodex.h1("Test").to_odt
    assert("returns binary") { odt.is_a?(String) && odt.encoding == Encoding::ASCII_8BIT }
    assert("is a ZIP") { odt[0, 2] == "PK" }
  end

  def self.test_odt_native_method
    puts "  ODT: Native.to_odt..."
    odt = Nodex::Native.to_odt(Nodex.p("test"))
    assert("returns binary") { odt.is_a?(String) }
    assert("is a ZIP") { odt[0, 2] == "PK" }
  end
  # ── Commit 4: Polish + edge cases ────────────────────────────

  def self.test_docx_border
    puts "  DOCX: border..."
    xml = doc_xml(Nodex.p("bordered").set_style("border", "2px solid #333").to_docx)
    assert("border → w:pBdr") { xml.include?('w:pBdr') }
    assert("has border sides") { xml.include?('w:top') && xml.include?('w:bottom') }
    assert("has border color") { xml.include?('333') }
  end

  def self.test_docx_colspan
    puts "  DOCX: colspan/rowspan..."
    tree = Nodex.node("table", children: [
      Nodex.node("tr", children: [
        Nodex.node("td", text: "Wide", colspan: "2"),
      ]),
      Nodex.node("tr", children: [
        Nodex.node("td", text: "A"),
        Nodex.node("td", text: "B"),
      ]),
    ])
    xml = doc_xml(tree.to_docx)
    assert("colspan → w:gridSpan") { xml.include?('w:gridSpan') }

    tree2 = Nodex.node("table", children: [
      Nodex.node("tr", children: [
        Nodex.node("td", text: "Tall", rowspan: "2"),
        Nodex.node("td", text: "R1"),
      ]),
      Nodex.node("tr", children: [
        Nodex.node("td", text: "R2"),
      ]),
    ])
    xml2 = doc_xml(tree2.to_docx)
    assert("rowspan → w:vMerge") { xml2.include?('w:vMerge') }
  end

  def self.test_docx_page_config
    puts "  DOCX: page config..."
    tree = Nodex.p("Hello")
    docx = tree.to_docx({"margin_top" => "2in", "margin_bottom" => "2in"})
    xml = doc_xml(docx)
    assert("has w:sectPr") { xml.include?('w:sectPr') }
    assert("has w:pgSz") { xml.include?('w:pgSz') }
    assert("has w:pgMar") { xml.include?('w:pgMar') }
    # 2in = 2880 twips
    assert("custom margin") { xml.include?('"2880"') }
  end

  def self.test_docx_page_a4
    puts "  DOCX: A4 page size..."
    docx = Nodex.p("A4").to_docx({"page_size" => "A4"})
    xml = doc_xml(docx)
    # A4 width = 11906 twips
    assert("A4 width") { xml.include?('"11906"') }
    assert("A4 height") { xml.include?('"16838"') }
  end

  def self.test_odt_colspan
    puts "  ODT: colspan/rowspan..."
    tree = Nodex.node("table", children: [
      Nodex.node("tr", children: [
        Nodex.node("td", text: "Wide", colspan: "3"),
      ]),
    ])
    xml = odt_content(tree.to_odt)
    assert("colspan → number-columns-spanned") { xml.include?('table:number-columns-spanned="3"') }

    tree2 = Nodex.node("table", children: [
      Nodex.node("tr", children: [
        Nodex.node("td", text: "Tall", rowspan: "2"),
      ]),
    ])
    xml2 = odt_content(tree2.to_odt)
    assert("rowspan → number-rows-spanned") { xml2.include?('table:number-rows-spanned="2"') }
  end

  def self.test_odt_page_config
    puts "  ODT: page config..."
    odt = Nodex.p("A4").to_odt({"page_size" => "A4"})
    styles = zip_entry(odt, 'styles.xml')&.force_encoding('UTF-8')
    assert("has page-layout") { styles&.include?('style:page-layout') }
    assert("has page-layout-properties") { styles&.include?('style:page-layout-properties') }
    assert("has fo:page-width") { styles&.include?('fo:page-width') }
  end
  # ── v1.3: Page breaks, headers/footers, doc config, GOST ──────

  def self.test_docx_justify_both
    puts "  DOCX: justify → both..."
    xml = doc_xml(Nodex.p("justified").set_style("text-align", "justify").to_docx)
    assert("justify maps to both") { xml.include?('w:jc') && xml.include?('"both"') }
  end

  def self.test_docx_page_break
    puts "  DOCX: __page_break__..."
    tree = Nodex.div([Nodex.p("Before"), Nodex.node("__page_break__"), Nodex.p("After")])
    xml = doc_xml(tree.to_docx)
    assert("has page break") { xml.include?('w:br w:type="page"') }
    assert("has both paragraphs") { xml.include?("Before") && xml.include?("After") }
  end

  def self.test_docx_css_page_break_before
    puts "  DOCX: CSS page-break-before..."
    tree = Nodex.div([
      Nodex.p("Page 1"),
      Nodex.p("Page 2").set_style("page-break-before", "always")
    ])
    xml = doc_xml(tree.to_docx)
    assert("CSS page-break-before emits break") { xml.include?('w:br w:type="page"') }
  end

  def self.test_docx_default_font
    puts "  DOCX: default_font..."
    docx = Nodex.p("Hello").to_docx({"default_font" => "Times New Roman"})
    xml = doc_xml(docx)
    assert("has Times New Roman in runs") { xml.include?("Times New Roman") }
    # Check styles.xml docDefaults
    styles = zip_entry(docx, 'word/styles.xml')&.force_encoding('UTF-8')
    assert("docDefaults has Times New Roman") { styles&.include?("Times New Roman") }
  end

  def self.test_docx_default_font_size
    puts "  DOCX: default_font_size..."
    docx = Nodex.p("Hello").to_docx({"default_font_size" => "14pt"})
    xml = doc_xml(docx)
    # 14pt = 28 half-points
    assert("run has w:sz 28") { xml.include?('w:sz') && xml.include?('"28"') }
  end

  def self.test_docx_line_spacing
    puts "  DOCX: line_spacing..."
    xml = doc_xml(Nodex.p("Spaced").to_docx({"line_spacing" => "1.5"}))
    # 1.5 × 240 = 360
    assert("has w:spacing w:line 360") { xml.include?('w:spacing') && xml.include?('"360"') }
    assert("has lineRule auto") { xml.include?('w:lineRule="auto"') }
  end

  def self.test_docx_first_line_indent
    puts "  DOCX: first_line_indent..."
    xml = doc_xml(Nodex.p("Indented").to_docx({"first_line_indent" => "1.25cm"}))
    # 1.25cm ≈ 709 twips
    assert("has w:firstLine") { xml.include?('w:firstLine') }
    assert("indent value ~709") {
      xml =~ /w:firstLine="(\d+)"/ && $1.to_i.between?(700, 720)
    }
  end

  def self.test_docx_header_footer_zip
    puts "  DOCX: header/footer in ZIP..."
    docx = Nodex.p("Body").to_docx({
      "header" => "Report Title",
      "footer" => "Confidential"
    })
    hdr = zip_entry(docx, 'word/header1.xml')&.force_encoding('UTF-8')
    ftr = zip_entry(docx, 'word/footer1.xml')&.force_encoding('UTF-8')
    assert("header1.xml exists") { hdr }
    assert("header has text") { hdr&.include?("Report Title") }
    assert("footer1.xml exists") { ftr }
    assert("footer has text") { ftr&.include?("Confidential") }

    xml = doc_xml(docx)
    assert("sectPr has headerReference") { xml.include?('w:headerReference') }
    assert("sectPr has footerReference") { xml.include?('w:footerReference') }
  end

  def self.test_docx_page_numbers
    puts "  DOCX: page_numbers field code..."
    docx = Nodex.p("Body").to_docx({"page_numbers" => true})
    ftr = zip_entry(docx, 'word/footer1.xml')&.force_encoding('UTF-8')
    assert("footer exists") { ftr }
    assert("has PAGE field") { ftr&.include?('PAGE') && ftr&.include?('MERGEFORMAT') }
    assert("has fldChar") { ftr&.include?('w:fldChar') }
  end

  def self.test_docx_first_page_footer
    puts "  DOCX: first_page_footer + titlePg..."
    docx = Nodex.p("Body").to_docx({
      "footer" => "Page footer",
      "first_page_footer" => "Sevastopol, 2026"
    })
    ftr2 = zip_entry(docx, 'word/footer2.xml')&.force_encoding('UTF-8')
    assert("footer2.xml exists") { ftr2 }
    assert("first-page footer has text") { ftr2&.include?("Sevastopol, 2026") }

    xml = doc_xml(docx)
    assert("has titlePg") { xml.include?('w:titlePg') }
    assert("has first footer ref") { xml.include?('w:type="first"') }
  end

  def self.test_docx_gost_preset
    puts "  DOCX: GOST preset via Doc..."
    tree = Nodex.p("GOST text")
    docx = Nodex::Doc.to_docx(tree, preset: :gost)
    xml = doc_xml(docx)
    # A4 width
    assert("A4 page") { xml.include?('"11906"') }
    # Times New Roman in runs
    assert("Times New Roman") { xml.include?("Times New Roman") }
    # 14pt = 28 half-points
    assert("14pt font size") { xml.include?('"28"') }
    # First-line indent
    assert("first-line indent") { xml.include?('w:firstLine') }
    # Line spacing 1.5 = 360
    assert("line spacing 360") { xml.include?('"360"') }
    # Margins: left=30mm≈1701tw, right=15mm≈850tw
    assert("left margin ~1701") {
      xml =~ /w:left="(\d+)"/ && $1.to_i.between?(1695, 1710)
    }
  end

  def self.test_docx_page_break_factory
    puts "  DOCX: page_break() factory..."
    tree = Nodex.div([Nodex.p("A"), Nodex.page_break, Nodex.p("B")])
    xml = doc_xml(tree.to_docx)
    assert("factory produces page break") { xml.include?('w:br w:type="page"') }
  end

  def self.test_odt_page_break
    puts "  ODT: page break..."
    tree = Nodex.div([Nodex.p("Before"), Nodex.node("__page_break__"), Nodex.p("After")])
    xml = odt_content(tree.to_odt)
    assert("has break-before page") { xml.include?('fo:break-before="page"') }
  end

  def self.test_odt_default_font
    puts "  ODT: default font..."
    odt = Nodex.p("Hello").to_odt({"default_font" => "Times New Roman"})
    styles = zip_entry(odt, 'styles.xml')&.force_encoding('UTF-8')
    assert("styles has Times New Roman") { styles&.include?("Times New Roman") }
    xml = odt_content(odt)
    assert("content has Times New Roman") { xml.include?("Times New Roman") }
  end

  def self.test_odt_footer_page_number
    puts "  ODT: footer with page-number..."
    odt = Nodex.p("Body").to_odt({"footer" => "Page ", "page_numbers" => true})
    styles = zip_entry(odt, 'styles.xml')&.force_encoding('UTF-8')
    assert("has style:footer") { styles&.include?("style:footer") }
    assert("has text:page-number") { styles&.include?("text:page-number") }
    assert("has footer text") { styles&.include?("Page ") }
  end
end

DocxTests.run
