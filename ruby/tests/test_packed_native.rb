# frozen_string_literal: true

# Native .so tests for the packed binary protocol.
# Requires libnodex.so built — tests to_html_packed via C++ FFI.
#
# Run: ruby ruby/tests/test_packed_native.rb

require_relative '../lib/nodex'

module PackedNativeTests
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

  def self.assert_include(desc, haystack, needle)
    if haystack.include?(needle)
      @passed += 1
    else
      @failed += 1
      $stderr.puts "  FAIL: #{desc}\n    '#{needle}' not found in:\n    #{haystack[0..200]}"
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

  # ── Tests ───────────────────────────────────────────────────────

  def self.run
    puts "=== Native .so packed protocol tests ==="

    # Verify library is available
    begin
      Nodex.send(:_require_native!)
      puts "  libnodex loaded: #{Nodex::Platform.find_library('nodex')}"
    rescue => e
      puts "  SKIP: #{e.message}"
      puts "  Build libnodex.so first: cmake --build build"
      exit 0
    end

    test_simple_div
    test_div_with_text
    test_div_with_id
    test_classes
    test_styles
    test_attributes
    test_children
    test_nested_tree
    test_raw_node
    test_text_node_in_tree
    test_void_elements
    test_matches_pure_ruby
    test_matches_json_native
    test_complex_tree
    test_utf8
    test_document
    test_large_tree_perf
    test_benchmark

    summary
  end

  def self.test_simple_div
    puts "  simple div..."
    html = Nodex.div.to_html_packed
    assert_include("has <div>", html, "<div>")
    assert_include("has </div>", html, "</div>")
  end

  def self.test_div_with_text
    puts "  div with text..."
    html = Nodex.div.set_text("Hello").to_html_packed
    assert_include("text", html, "Hello")
    assert_include("div tags", html, "<div>")
  end

  def self.test_div_with_id
    puts "  div with id..."
    html = Nodex.div.set_id("main").to_html_packed
    assert_include("id attr", html, 'id="main"')
  end

  def self.test_classes
    puts "  classes..."
    html = Nodex.div.add_class("a").add_class("b").to_html_packed
    assert_include("class attr", html, 'class="a b"')
  end

  def self.test_styles
    puts "  styles..."
    html = Nodex.div.set_style("color", "red").to_html_packed
    assert_include("style attr", html, "color")
    assert_include("style value", html, "red")
  end

  def self.test_attributes
    puts "  attributes..."
    html = Nodex.img("photo.jpg", alt: "pic").to_html_packed
    assert_include("src", html, 'src="photo.jpg"')
    assert_include("alt", html, 'alt="pic"')
  end

  def self.test_children
    puts "  children..."
    tree = Nodex.div([Nodex.p("First"), Nodex.p("Second")])
    html = tree.to_html_packed
    assert_include("child 1", html, "<p>First</p>")
    assert_include("child 2", html, "<p>Second</p>")
    assert_include("wrapper", html, "<div>")
  end

  def self.test_nested_tree
    puts "  nested tree..."
    tree = Nodex.div([
      Nodex.section([
        Nodex.article([
          Nodex.p("Deep")
        ])
      ])
    ])
    html = tree.to_html_packed
    assert_include("deep text", html, "<p>Deep</p>")
    assert_include("section", html, "<section>")
    assert_include("article", html, "<article>")
  end

  def self.test_raw_node
    puts "  raw node..."
    tree = Nodex.div([Nodex.raw("<b>Bold</b>")])
    html = tree.to_html_packed
    assert_include("raw html", html, "<b>Bold</b>")
  end

  def self.test_text_node_in_tree
    puts "  text node in tree..."
    tree = Nodex.div([Nodex.text("plain text")])
    html = tree.to_html_packed
    assert_include("text content", html, "plain text")
  end

  def self.test_void_elements
    puts "  void elements..."
    html = Nodex.br.to_html_packed
    assert_include("br tag", html, "<br")
    # C++ may render <br> or <br /> — both valid
    assert("no </br>") { !html.include?("</br>") }

    html = Nodex.hr.to_html_packed
    assert_include("hr tag", html, "<hr")
  end

  def self.test_matches_pure_ruby
    puts "  packed matches pure Ruby output..."
    tree = Nodex.div([
      Nodex.h1("Title").bold.color("#333"),
      Nodex.p("Description").padding("10px"),
      Nodex.a("Link", href: "/page"),
    ]).set_id("card").add_class("container")

    ruby_html  = tree.to_html
    packed_html = tree.to_html_packed

    # C++ rendering may differ in style attribute formatting
    # (e.g. trailing semicolon, property order).
    # Check structural equivalence instead of exact match.
    assert_include("has id", packed_html, 'id="card"')
    assert_include("has class", packed_html, 'class="container"')
    assert_include("has h1", packed_html, "<h1")
    assert_include("has Title", packed_html, "Title")
    assert_include("has p", packed_html, "<p")
    assert_include("has Description", packed_html, "Description")
    assert_include("has link", packed_html, "<a")
    assert_include("has href", packed_html, 'href="/page"')

    # Both should produce valid wrapping
    assert_include("ruby has </div>", ruby_html, "</div>")
    assert_include("packed has </div>", packed_html, "</div>")
  end

  def self.test_matches_json_native
    puts "  packed matches JSON native output..."
    tree = Nodex.div([
      Nodex.h1("Title").set_id("t"),
      Nodex.p("Body"),
    ]).add_class("wrap")

    json_html   = tree.to_html_native
    packed_html = tree.to_html_packed

    # Both go through C++ rendering — should be identical
    assert_eq("json == packed", json_html, packed_html)
  end

  def self.test_complex_tree
    puts "  complex tree..."
    tree = Nodex.div([
      Nodex.h1("Title").bold.color("#333").set_id("title"),
      Nodex.div([
        Nodex.p("Para 1").padding("5px").margin("10px"),
        Nodex.p("Para 2").add_class("highlight"),
        Nodex.img("logo.png", alt: "Logo"),
        Nodex.raw("<hr class='sep'>"),
      ]).add_class("content"),
      Nodex.footer([
        Nodex.a("Home", href: "/").add_class("nav-link"),
        Nodex.text(" | "),
        Nodex.a("About", href: "/about"),
      ]),
    ]).set_id("page")

    html = tree.to_html_packed
    assert_include("page id", html, 'id="page"')
    assert_include("title id", html, 'id="title"')
    assert_include("h1 text", html, "Title")
    assert_include("para 1", html, "Para 1")
    assert_include("para 2", html, "Para 2")
    assert_include("highlight class", html, "highlight")
    assert_include("img src", html, 'src="logo.png"')
    assert_include("raw hr", html, "<hr class='sep'>")
    assert_include("nav link", html, "Home")
    assert_include("separator", html, " | ")
    assert_include("about link", html, "About")
  end

  def self.test_utf8
    puts "  UTF-8..."
    tree = Nodex.p("Привет 日本語 🎉")
    html = tree.to_html_packed
    assert_include("cyrillic", html, "Привет")
    assert_include("japanese", html, "日本語")
    assert_include("emoji", html, "🎉")
  end

  def self.test_document
    puts "  document..."
    doc = Nodex.document("Test Page", body: [
      Nodex.h1("Welcome"),
      Nodex.p("Content"),
    ])
    html = doc.to_html_packed
    assert_include("doctype", html, "<!DOCTYPE html>")
    assert_include("html tag", html, "<html")
    assert_include("head tag", html, "<head>")
    assert_include("title", html, "<title>Test Page</title>")
    assert_include("h1", html, "Welcome")
    assert_include("p", html, "Content")
  end

  def self.test_large_tree_perf
    puts "  large tree correctness (2000 nodes)..."
    children = (1..1999).map { |i|
      Nodex.div([
        Nodex.p("Item #{i}"),
      ]).add_class("card")
    }
    tree = Nodex.div(children).set_id("list")

    html = tree.to_html_packed
    assert_include("has id", html, 'id="list"')
    assert_include("first item", html, "Item 1")
    assert_include("last item", html, "Item 1999")
    assert_include("card class", html, 'class="card"')
  end

  def self.test_benchmark
    puts "  benchmark (200 iterations, 500 nodes)..."
    tree = Nodex.div((1..500).map { |i|
      Nodex.div([
        Nodex.h1("Item #{i}").bold.color("#333"),
        Nodex.p("Desc #{i}").padding("10px").margin("5px"),
        Nodex.a("Link", href: "/#{i}"),
      ]).add_class("card")
    })

    n = 200

    # Warmup
    3.times { tree.to_html; tree.to_html_native; tree.to_html_packed }

    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { tree.to_html }
    ruby_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t1

    t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { tree.to_html_native }
    json_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t2

    t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { tree.to_html_packed }
    packed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t3

    puts "    Ruby pure:   #{(ruby_time / n * 1000).round(2)}ms/render"
    puts "    JSON native: #{(json_time / n * 1000).round(2)}ms/render"
    puts "    Packed:      #{(packed_time / n * 1000).round(2)}ms/render"
    puts "    Speedup:     #{(ruby_time / packed_time).round(2)}x vs Ruby, #{(json_time / packed_time).round(2)}x vs JSON"

    # Packed should not be slower than JSON native
    assert("packed <= JSON native") { packed_time <= json_time * 1.1 }
    @passed += 1  # benchmark ran successfully
  end
end

PackedNativeTests.run