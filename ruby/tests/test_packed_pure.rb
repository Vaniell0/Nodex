# frozen_string_literal: true

# Pure Ruby tests for the packed binary protocol.
# No .so required — tests to_packed format correctness only.
#
# Run: ruby ruby/tests/test_packed_pure.rb

require_relative '../lib/nodex'

module PackedTests
  @passed = 0
  @failed = 0

  def self.assert(desc, &block)
    result = block.call
    if result
      @passed += 1
    else
      @failed += 1
      $stderr.puts "  FAIL: #{desc}"
    end
  rescue => e
    @failed += 1
    $stderr.puts "  ERROR: #{desc} — #{e.message}"
  end

  def self.assert_eq(desc, actual, expected)
    if actual == expected
      @passed += 1
    else
      @failed += 1
      $stderr.puts "  FAIL: #{desc}\n    expected: #{expected.inspect}\n    actual:   #{actual.inspect}"
    end
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

  # --- Helpers: unpack a packed buffer back to Ruby hashes ---

  def self.unpack_str(buf, pos)
    len = buf[pos, 2].unpack1('v')
    s = buf[pos + 2, len].force_encoding('UTF-8')
    [s, pos + 2 + len]
  end

  def self.unpack_node(buf, pos)
    parent_idx = buf[pos, 4].unpack1('l<'); pos += 4
    flags      = buf[pos, 4].unpack1('V');  pos += 4

    tag, pos  = unpack_str(buf, pos)
    text, pos = unpack_str(buf, pos)
    id, pos   = unpack_str(buf, pos)

    cls_count = buf[pos, 2].unpack1('v'); pos += 2
    classes = []
    cls_count.times do
      c, pos = unpack_str(buf, pos)
      classes << c
    end

    sty_count = buf[pos, 2].unpack1('v'); pos += 2
    styles = {}
    sty_count.times do
      k, pos = unpack_str(buf, pos)
      v, pos = unpack_str(buf, pos)
      styles[k] = v
    end

    attr_count = buf[pos, 2].unpack1('v'); pos += 2
    attrs = {}
    attr_count.times do
      k, pos = unpack_str(buf, pos)
      v, pos = unpack_str(buf, pos)
      attrs[k] = v
    end

    node = {
      parent_idx: parent_idx, flags: flags,
      tag: tag, text: text, id: id,
      classes: classes, styles: styles, attrs: attrs
    }
    [node, pos]
  end

  def self.unpack_all(buf)
    count = buf[0, 4].unpack1('V')
    pos = 4
    nodes = []
    count.times do
      node, pos = unpack_node(buf, pos)
      nodes << node
    end
    nodes
  end

  # ── Tests ───────────────────────────────────────────────────────

  def self.run
    puts "=== Pure Ruby packed protocol tests ==="

    test_encoding
    test_single_div
    test_text_node
    test_raw_node
    test_node_with_all_fields
    test_tree_with_children
    test_deep_tree
    test_parent_indices
    test_dfs_order
    test_empty_node
    test_void_element
    test_node_count
    test_utf8_content
    test_large_tree
    test_styles_and_attrs_order
    test_document_tree

    summary
  end

  def self.test_encoding
    puts "  encoding..."
    buf = Nodex.div.to_packed
    assert_eq("binary encoding", buf.encoding, Encoding::BINARY)
    assert("starts with uint32 count") { buf.bytesize >= 4 }
  end

  def self.test_single_div
    puts "  single div..."
    buf = Nodex.div.to_packed
    nodes = unpack_all(buf)
    assert_eq("1 node", nodes.size, 1)
    assert_eq("tag=div", nodes[0][:tag], "div")
    assert_eq("parent=-1", nodes[0][:parent_idx], -1)
    assert_eq("flags=0", nodes[0][:flags], 0)
    assert_eq("no text", nodes[0][:text], "")
    assert_eq("no id", nodes[0][:id], "")
    assert_eq("no classes", nodes[0][:classes], [])
    assert_eq("no styles", nodes[0][:styles], {})
    assert_eq("no attrs", nodes[0][:attrs], {})
  end

  def self.test_text_node
    puts "  text node..."
    node = Nodex.text("Hello world")
    buf = node.to_packed
    nodes = unpack_all(buf)
    assert_eq("1 node", nodes.size, 1)
    assert_eq("tag empty", nodes[0][:tag], "")
    assert_eq("text content", nodes[0][:text], "Hello world")
    assert_eq("flags=0", nodes[0][:flags], 0)
  end

  def self.test_raw_node
    puts "  raw node..."
    node = Nodex.raw("<b>Bold</b>")
    buf = node.to_packed
    nodes = unpack_all(buf)
    assert_eq("1 node", nodes.size, 1)
    assert_eq("tag empty", nodes[0][:tag], "")
    assert_eq("raw content", nodes[0][:text], "<b>Bold</b>")
    assert_eq("flags=1 (raw)", nodes[0][:flags], 1)
  end

  def self.test_node_with_all_fields
    puts "  node with all fields..."
    node = Nodex.div
      .set_id("main")
      .add_class("container")
      .add_class("active")
      .set_style("color", "red")
      .set_style("padding", "10px")
      .set_attr("data-page", "home")
      .set_text("Hello")

    buf = node.to_packed
    nodes = unpack_all(buf)
    n = nodes[0]

    assert_eq("tag", n[:tag], "div")
    assert_eq("id", n[:id], "main")
    assert_eq("text", n[:text], "Hello")
    assert_eq("classes", n[:classes], ["container", "active"])
    assert_eq("style color", n[:styles]["color"], "red")
    assert_eq("style padding", n[:styles]["padding"], "10px")
    assert_eq("attr data-page", n[:attrs]["data-page"], "home")
  end

  def self.test_tree_with_children
    puts "  tree with children..."
    tree = Nodex.div([
      Nodex.h1("Title"),
      Nodex.p("Body"),
    ])

    buf = tree.to_packed
    nodes = unpack_all(buf)

    assert_eq("3 nodes", nodes.size, 3)
    assert_eq("root tag", nodes[0][:tag], "div")
    assert_eq("child1 tag", nodes[1][:tag], "h1")
    assert_eq("child1 text", nodes[1][:text], "Title")
    assert_eq("child2 tag", nodes[2][:tag], "p")
    assert_eq("child2 text", nodes[2][:text], "Body")
  end

  def self.test_deep_tree
    puts "  deep nesting..."
    # div > section > article > p("Deep")
    tree = Nodex.div([
      Nodex.section([
        Nodex.article([
          Nodex.p("Deep")
        ])
      ])
    ])

    buf = tree.to_packed
    nodes = unpack_all(buf)

    assert_eq("4 nodes", nodes.size, 4)
    assert_eq("div parent=-1", nodes[0][:parent_idx], -1)
    assert_eq("section parent=0", nodes[1][:parent_idx], 0)
    assert_eq("article parent=1", nodes[2][:parent_idx], 1)
    assert_eq("p parent=2", nodes[3][:parent_idx], 2)
    assert_eq("p text", nodes[3][:text], "Deep")
  end

  def self.test_parent_indices
    puts "  parent indices..."
    # div with 3 direct children
    tree = Nodex.div([
      Nodex.h1("A"),
      Nodex.h2("B"),
      Nodex.h3("C"),
    ])

    buf = tree.to_packed
    nodes = unpack_all(buf)

    assert_eq("4 nodes", nodes.size, 4)
    assert_eq("h1 parent=0", nodes[1][:parent_idx], 0)
    assert_eq("h2 parent=0", nodes[2][:parent_idx], 0)
    assert_eq("h3 parent=0", nodes[3][:parent_idx], 0)
  end

  def self.test_dfs_order
    puts "  DFS order..."
    # div > [section > [p("A")], article > [p("B")]]
    tree = Nodex.div([
      Nodex.section([Nodex.p("A")]),
      Nodex.article([Nodex.p("B")]),
    ])

    buf = tree.to_packed
    nodes = unpack_all(buf)

    assert_eq("5 nodes", nodes.size, 5)
    # DFS: div(0), section(1), p-A(2), article(3), p-B(4)
    assert_eq("node0=div", nodes[0][:tag], "div")
    assert_eq("node1=section", nodes[1][:tag], "section")
    assert_eq("node2=p(A)", nodes[2][:text], "A")
    assert_eq("node3=article", nodes[3][:tag], "article")
    assert_eq("node4=p(B)", nodes[4][:text], "B")
    assert_eq("p-A parent=section", nodes[2][:parent_idx], 1)
    assert_eq("p-B parent=article", nodes[4][:parent_idx], 3)
  end

  def self.test_empty_node
    puts "  empty node..."
    node = Nodex.div
    buf = node.to_packed
    nodes = unpack_all(buf)
    assert_eq("1 node", nodes.size, 1)
    assert_eq("tag=div", nodes[0][:tag], "div")
  end

  def self.test_void_element
    puts "  void element..."
    node = Nodex.img("photo.jpg", alt: "pic")
    buf = node.to_packed
    nodes = unpack_all(buf)
    assert_eq("1 node", nodes.size, 1)
    assert_eq("tag=img", nodes[0][:tag], "img")
    assert_eq("src attr", nodes[0][:attrs]["src"], "photo.jpg")
    assert_eq("alt attr", nodes[0][:attrs]["alt"], "pic")
  end

  def self.test_node_count
    puts "  node count header..."
    tree = Nodex.div([Nodex.p("A"), Nodex.p("B")])
    buf = tree.to_packed
    count = buf[0, 4].unpack1('V')
    assert_eq("header count=3", count, 3)
  end

  def self.test_utf8_content
    puts "  UTF-8 content..."
    node = Nodex.p("Привет мир! 日本語 🎉")
    buf = node.to_packed
    nodes = unpack_all(buf)
    assert_eq("utf8 text", nodes[0][:text], "Привет мир! 日本語 🎉")
  end

  def self.test_large_tree
    puts "  large tree (500 nodes)..."
    children = (1..499).map { |i| Nodex.p("Item #{i}") }
    tree = Nodex.div(children)
    buf = tree.to_packed
    nodes = unpack_all(buf)
    assert_eq("500 nodes", nodes.size, 500)
    assert_eq("last text", nodes[499][:text], "Item 499")
    # All children parent to root
    (1..499).each do |i|
      unless nodes[i][:parent_idx] == 0
        assert_eq("node #{i} parent", nodes[i][:parent_idx], 0)
        break
      end
    end
    @passed += 1  # all parents correct
  end

  def self.test_styles_and_attrs_order
    puts "  styles and attrs preserved..."
    node = Nodex.div
      .set_style("color", "red")
      .set_style("margin", "10px")
      .set_style("padding", "5px")
      .set_attr("data-a", "1")
      .set_attr("data-b", "2")

    buf = node.to_packed
    nodes = unpack_all(buf)
    n = nodes[0]

    assert_eq("3 styles", n[:styles].size, 3)
    assert_eq("color", n[:styles]["color"], "red")
    assert_eq("margin", n[:styles]["margin"], "10px")
    assert_eq("padding", n[:styles]["padding"], "5px")
    assert_eq("2 attrs", n[:attrs].size, 2)
    assert_eq("data-a", n[:attrs]["data-a"], "1")
    assert_eq("data-b", n[:attrs]["data-b"], "2")
  end

  def self.test_document_tree
    puts "  document tree..."
    doc = Nodex.document("Test", body: [Nodex.h1("Hello")])
    buf = doc.to_packed
    nodes = unpack_all(buf)

    # html > head > [meta, meta, title], body > h1
    assert("node count >= 6") { nodes.size >= 6 }
    assert_eq("root=html", nodes[0][:tag], "html")
    # Find body node
    body = nodes.find { |n| n[:tag] == "body" }
    assert("body found") { !body.nil? }
    # Find h1 node
    h1 = nodes.find { |n| n[:tag] == "h1" }
    assert("h1 found") { !h1.nil? }
    assert_eq("h1 text", h1[:text], "Hello")
  end
end

PackedTests.run
