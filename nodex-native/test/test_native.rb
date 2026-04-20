# frozen_string_literal: true

# Tests for nodex-native C extension.
# Verifies byte-for-byte identical output with pure Ruby + benchmark.
#
# Run: ruby test/test_native.rb

$LOAD_PATH.unshift File.expand_path('../../ruby/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'nodex'
require 'nodex/native'

module NativeTests
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

  # Compare Ruby to_html vs C to_html_native
  def self.match(desc, node)
    ruby_html = node.to_html_ruby
    c_html    = node.to_html_native
    assert_eq(desc, c_html, ruby_html)
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

  def self.run
    puts "=== nodex-native C extension tests ==="

    test_basic_elements
    test_escaping
    test_children
    test_special_nodes
    test_void_elements
    test_styles_and_attrs
    test_utf8
    test_document
    test_decorator_chains
    test_large_tree
    test_render_cache
    test_subtree_cache
    test_invalidation_short_circuit
    test_baked
    test_packed_builder
    test_inja
    test_concurrent_to_html
    test_concurrent_render_opcodes
    test_component_api
    test_benchmark

    summary
  end

  def self.test_basic_elements
    puts "  basic elements..."
    match("empty div", Nodex.div)
    match("div with text", Nodex.div.set_text("Hello"))
    match("div with id", Nodex.div.set_id("main"))
    match("div with one class", Nodex.div.add_class("active"))
    match("div with two classes", Nodex.div.add_class("a").add_class("b"))
    match("p with text", Nodex.p("Hello world"))
    match("h1", Nodex.h1("Title"))
    match("span", Nodex.span_elem("inline"))
  end

  def self.test_escaping
    puts "  HTML escaping..."
    match("escape &", Nodex.p("A & B"))
    match("escape <", Nodex.p("A < B"))
    match("escape >", Nodex.p("A > B"))
    match("escape \"", Nodex.div.set_id('say "hi"'))
    match("escape '", Nodex.p("it's"))
    match("escape mixed", Nodex.p('<script>alert("xss")</script>'))
    match("escape in attr value", Nodex.a("link", href: "/search?q=a&b=c"))
    match("escape in class", Nodex.div.add_class("a&b"))
  end

  def self.test_children
    puts "  children..."
    match("two children",
      Nodex.div([Nodex.h1("Title"), Nodex.p("Body")]))
    match("nested 3 levels",
      Nodex.div([Nodex.section([Nodex.article([Nodex.p("Deep")])])]))
    match("mixed text + children",
      Nodex.div([Nodex.text("Before"), Nodex.p("Mid"), Nodex.text("After")]))
    match("many children",
      Nodex.ul((1..10).map { |i| Nodex.li("Item #{i}") }))
  end

  def self.test_special_nodes
    puts "  special nodes..."
    match("text node", Nodex.text("Hello <world>"))
    match("raw node", Nodex.raw("<b>Bold</b>"))
    match("raw in tree", Nodex.div([Nodex.raw("<hr class='sep'>")]))
    match("empty text node", Nodex.text(""))
  end

  def self.test_void_elements
    puts "  void elements..."
    match("br", Nodex.br)
    match("hr", Nodex.hr)
    match("img", Nodex.img("photo.jpg", alt: "A photo"))
    match("input", Nodex.input_elem("text", name: "q", value: "search"))
    match("meta", Nodex.meta_elem(charset: "UTF-8"))
    match("link", Nodex.link_elem(rel: "stylesheet", href: "/style.css"))
  end

  def self.test_styles_and_attrs
    puts "  styles and attributes..."
    match("one style",
      Nodex.div.set_style("color", "red"))
    match("multiple styles",
      Nodex.div.set_style("color", "red").set_style("margin", "10px").set_style("padding", "5px"))
    match("one attr",
      Nodex.div.set_attr("data-page", "home"))
    match("multiple attrs",
      Nodex.div.set_attr("data-a", "1").set_attr("data-b", "2").set_attr("role", "main"))
    match("id + class + style + attr",
      Nodex.div.set_id("x").add_class("y").set_style("color", "red").set_attr("data-z", "1"))
  end

  def self.test_utf8
    puts "  UTF-8..."
    match("cyrillic", Nodex.p("Привет мир"))
    match("japanese", Nodex.p("日本語テスト"))
    match("emoji", Nodex.p("Hello 🎉🚀"))
    match("mixed utf8", Nodex.p("Привет 日本語 🎉"))
    match("utf8 in attr", Nodex.div.set_attr("data-name", "Иван"))
    match("utf8 in id", Nodex.div.set_id("блок"))
  end

  def self.test_document
    puts "  document..."
    match("full document",
      Nodex.document("Test Page", body: [Nodex.h1("Hello"), Nodex.p("World")]))
    match("document with head",
      Nodex.document("Page", head: [Nodex.style_elem("body{margin:0}")], body: [Nodex.p("Hi")]))
  end

  def self.test_decorator_chains
    puts "  decorator chains..."
    match("bold + color",
      Nodex.h1("Title").bold.color("#333"))
    match("full chain",
      Nodex.p("Text").bold.italic.color("red").bg_color("yellow").padding("10px").margin("5px"))
    match("pipe operator",
      Nodex.p("Hello") | Nodex.Bold() | Nodex.Color("blue"))
  end

  def self.test_large_tree
    puts "  large tree (500 nodes) byte-for-byte..."
    tree = Nodex.div((1..500).map { |i|
      Nodex.div([
        Nodex.h1("Item #{i}").bold.color("#333"),
        Nodex.p("Desc #{i}").padding("10px").margin("5px"),
        Nodex.a("Link", href: "/#{i}"),
      ]).add_class("card")
    })
    match("500-node tree", tree)
  end

  def self.build_tree
    Nodex.div((1..500).map { |i|
      Nodex.div([
        Nodex.h1("Item #{i}").bold.color("#333"),
        Nodex.p("Desc #{i}").padding("10px").margin("5px"),
        Nodex.a("Link", href: "/#{i}"),
      ]).add_class("card")
    })
  end

  def self.test_render_cache
    puts "  render cache..."
    node = Nodex.div([Nodex.h1("Hello").bold, Nodex.p("World")])

    # First render populates cache
    html1 = node.to_html_native
    html2 = node.to_html_native
    assert_eq("cache hit returns same HTML", html2, html1)
    assert("cache hit returns same object") { html1.equal?(html2) }

    # Mutation invalidates cache
    node.add_class("updated")
    html3 = node.to_html_native
    assert("mutation invalidates cache") { html3 != html1 }
    assert("new HTML includes class") { html3.include?('class="updated"') }

    # Second render after mutation is cached again
    html4 = node.to_html_native
    assert("re-cached after mutation") { html4.equal?(html3) }
  end

  def self.test_subtree_cache
    puts "  subtree cache..."

    # Build: root > [child_a, child_b]
    child_a = Nodex.h1("Title").bold
    child_b = Nodex.p("Body").color("red")
    root = Nodex.div([child_a, child_b]).add_class("box")

    # First render populates all caches
    html1 = root.to_html
    assert("root cached") { root.instance_variable_get(:@_html_cache) }
    assert("child_a cached") { child_a.instance_variable_get(:@_html_cache) }
    assert("child_b cached") { child_b.instance_variable_get(:@_html_cache) }

    # Mutate child_a — should invalidate child_a + root, NOT child_b
    child_b_cache_before = child_b.instance_variable_get(:@_html_cache)
    child_a.color("#333")
    assert("child_a cache nil after mutation") { child_a.instance_variable_get(:@_html_cache).nil? }
    assert("root cache nil (bubble-up)") { root.instance_variable_get(:@_html_cache).nil? }
    assert("child_b cache survives") { child_b.instance_variable_get(:@_html_cache).equal?(child_b_cache_before) }

    # Re-render — child_b should use cached HTML
    html2 = root.to_html
    assert("re-rendered HTML differs") { html2 != html1 }
    assert("re-rendered includes new color") { html2.include?("color: #333") }
    assert("child_b still has same cache object") {
      child_b.instance_variable_get(:@_html_cache).equal?(child_b_cache_before)
    }
  end

  def self.test_invalidation_short_circuit
    puts "  invalidation short-circuit..."

    a = Nodex.div
    b = Nodex.div([a])
    c = Nodex.div([b])

    c.to_html  # populate caches

    # Manually clear b's cache to simulate prior invalidation
    b.instance_variable_set(:@_html_cache, nil)

    # Now mutate a — should stop at b (already nil), NOT touch c
    c_cache = c.instance_variable_get(:@_html_cache)
    a.set_id("x")
    assert("c cache untouched (short-circuit)") {
      c.instance_variable_get(:@_html_cache).equal?(c_cache)
    }
  end

  def self.test_baked
    puts "  baked templates..."

    Nodex::Native.bake(:greeting,
      Nodex.div([
        Nodex.h1(Nodex.slot(:title)).bold,
        Nodex.p(Nodex.slot(:body)),
      ]).add_class("card")
    )

    # Byte-for-byte match with manual tree
    baked_html = Nodex::Native.render_baked(:greeting, title: "Hello", body: "World")
    manual_html = Nodex.div([
      Nodex.h1("Hello").bold,
      Nodex.p("World"),
    ]).add_class("card").to_html_native
    assert_eq("baked matches manual", baked_html, manual_html)

    # HTML escaping in slots
    escaped = Nodex::Native.render_baked(:greeting, title: "<script>", body: "A & B")
    assert("baked escapes title") { escaped.include?("&lt;script&gt;") }
    assert("baked escapes body") { escaped.include?("A &amp; B") }

    # Attribute slots
    Nodex::Native.bake(:link,
      Nodex.a(Nodex.slot(:text), href: Nodex.slot_attr(:url))
    )
    link_html = Nodex::Native.render_baked(:link, text: "Click", url: "/page?a=1&b=2")
    assert("baked link has text") { link_html.include?(">Click<") }
    assert("baked link escapes url") { link_html.include?("&amp;") }

    # baked_node wraps in raw Node for tree embedding
    node = Nodex::Native.baked_node(:greeting, title: "Hi", body: "There")
    html = node.to_html
    assert("baked_node renders") { html.include?("Hi") && html.include?("There") }

    # Multi-slot template
    Nodex::Native.bake(:card,
      Nodex.div([
        Nodex.h1(Nodex.slot(:title)).bold.color("#333"),
        Nodex.p(Nodex.slot(:desc)),
        Nodex.a("Link", href: Nodex.slot_attr(:link)),
      ]).add_class("card")
    )
    card_html = Nodex::Native.render_baked(:card, title: "Project", desc: "Cool stuff", link: "/p/1")
    assert("card has title") { card_html.include?("Project") }
    assert("card has desc") { card_html.include?("Cool stuff") }
    assert("card has link") { card_html.include?("/p/1") }
  end

  def self.test_packed_builder
    puts "  packed builder..."

    # Basic elements
    assert_eq("packed: empty div",
      Nodex::Native.build { div },
      "<div></div>")

    assert_eq("packed: div with text",
      Nodex::Native.build { div("Hello") },
      "<div>Hello</div>")

    assert_eq("packed: h1 with text",
      Nodex::Native.build { h1("Title") },
      "<h1>Title</h1>")

    assert_eq("packed: p with text",
      Nodex::Native.build { p("Body") },
      "<p>Body</p>")

    # Attributes
    assert_eq("packed: div with id",
      Nodex::Native.build { div.set_id("main") },
      '<div id="main"></div>')

    assert_eq("packed: div with class",
      Nodex::Native.build { div.add_class("active") },
      '<div class="active"></div>')

    assert_eq("packed: div with two classes",
      Nodex::Native.build { div.add_class("a").add_class("b") },
      '<div class="a b"></div>')

    assert_eq("packed: div with attr",
      Nodex::Native.build { div.set_attr("data-page", "home") },
      '<div data-page="home"></div>')

    # Styles
    assert_eq("packed: bold style",
      Nodex::Native.build { h1("Title").bold },
      '<h1 style="font-weight: bold">Title</h1>')

    assert_eq("packed: multiple styles",
      Nodex::Native.build { div.set_style("color", "red").set_style("margin", "10px") },
      '<div style="color: red; margin: 10px"></div>')

    # Children via blocks
    assert_eq("packed: nested children",
      Nodex::Native.build {
        div {
          h1("Title")
          p("Body")
        }
      },
      "<div><h1>Title</h1><p>Body</p></div>")

    assert_eq("packed: deep nesting",
      Nodex::Native.build {
        div {
          section {
            article {
              p("Deep")
            }
          }
        }
      },
      "<div><section><article><p>Deep</p></article></section></div>")

    # Siblings with chained styles
    assert_eq("packed: siblings with styles",
      Nodex::Native.build {
        div {
          h1("Title").bold.color("#333")
          p("Body").padding("10px")
        }.add_class("card")
      },
      '<div class="card"><h1 style="font-weight: bold; color: #333">Title</h1><p style="padding: 10px">Body</p></div>')

    # HTML escaping
    assert_eq("packed: text escaping",
      Nodex::Native.build { p("A & B < C > D") },
      "<p>A &amp; B &lt; C &gt; D</p>")

    assert_eq("packed: attr escaping",
      Nodex::Native.build { a("link", href: "/search?q=a&b=c") },
      '<a href="/search?q=a&amp;b=c" target="_self">link</a>')

    # Text and raw nodes
    assert_eq("packed: text node",
      Nodex::Native.build { text("Hello <world>") },
      "Hello &lt;world&gt;")

    assert_eq("packed: raw node",
      Nodex::Native.build { raw("<b>Bold</b>") },
      "<b>Bold</b>")

    assert_eq("packed: mixed text and elements",
      Nodex::Native.build {
        div {
          text("Before")
          p("Mid")
          text("After")
        }
      },
      "<div>Before<p>Mid</p>After</div>")

    # Void elements
    assert_eq("packed: br",
      Nodex::Native.build { br },
      "<br>")

    assert_eq("packed: hr",
      Nodex::Native.build { hr },
      "<hr>")

    assert_eq("packed: img with attrs",
      Nodex::Native.build { img(src: "photo.jpg", alt: "A photo") },
      '<img src="photo.jpg" alt="A photo">')

    assert_eq("packed: input",
      Nodex::Native.build { input(type: "text", name: "q") },
      '<input type="text" name="q">')

    assert_eq("packed: meta",
      Nodex::Native.build { meta(charset: "UTF-8") },
      '<meta charset="UTF-8">')

    # id + class + style + attr combined
    assert_eq("packed: all decorators",
      Nodex::Native.build {
        div.set_id("x").add_class("y").set_style("color", "red").set_attr("data-z", "1")
      },
      '<div id="x" class="y" style="color: red" data-z="1"></div>')

    # HTMX shortcuts
    assert_eq("packed: htmx attrs",
      Nodex::Native.build {
        button("Load").hx_get("/api").hx_target("#content").hx_swap("innerHTML")
      },
      '<button hx-get="/api" hx-target="#content" hx-swap="innerHTML">Load</button>')

    # UTF-8
    assert_eq("packed: utf8 text",
      Nodex::Native.build { p("Привет 🎉") },
      "<p>Привет 🎉</p>")

    # Document helper
    doc_html = Nodex::Native.build {
      document("Test Page") {
        h1("Hello")
        p("World")
      }
    }
    assert("packed: document has doctype") { doc_html.start_with?("<!DOCTYPE html>\n") }
    assert("packed: document has html tag") { doc_html.include?('<html lang="en">') }
    assert("packed: document has title") { doc_html.include?("<title>Test Page</title>") }
    assert("packed: document has body content") { doc_html.include?("<h1>Hello</h1>") }
    assert("packed: document has meta charset") { doc_html.include?('<meta charset="UTF-8">') }

    # Large tree — same structure as Node-based test
    packed_html = Nodex::Native.build {
      div {
        500.times { |i|
          n = i + 1
          div {
            h1("Item #{n}").bold.color("#333")
            p("Desc #{n}").padding("10px").margin("5px")
            a("Link", href: "/#{n}")
          }.add_class("card")
        }
      }
    }
    node_html = Nodex.div((1..500).map { |i|
      Nodex.div([
        Nodex.h1("Item #{i}").bold.color("#333"),
        Nodex.p("Desc #{i}").padding("10px").margin("5px"),
        Nodex.a("Link", href: "/#{i}"),
      ]).add_class("card")
    }).to_html_native
    assert_eq("packed: 500-card tree matches Node-based", packed_html, node_html)
  end

  def self.test_inja
    puts "  inja templates..."

    # Basic variable substitution
    assert_eq("inja: basic render",
      Nodex::Native.render_template("Hello {{ name }}!", { name: "World" }),
      "Hello World!")

    # Loops
    assert_eq("inja: for loop",
      Nodex::Native.render_template("{% for x in items %}{{ x }} {% endfor %}", { items: ["a", "b", "c"] }),
      "a b c ")

    # Conditionals
    assert_eq("inja: if true",
      Nodex::Native.render_template("{% if show %}yes{% else %}no{% endif %}", { show: true }),
      "yes")
    assert_eq("inja: if false",
      Nodex::Native.render_template("{% if show %}yes{% else %}no{% endif %}", { show: false }),
      "no")

    # Nested data
    assert_eq("inja: nested hash",
      Nodex::Native.render_template("{{ user.name }} ({{ user.age }})", { user: { name: "Ivan", age: 25 } }),
      "Ivan (25)")

    # Numeric types
    assert_eq("inja: int and float",
      Nodex::Native.render_template("{{ n }}, {{ f }}", { n: 42, f: 3.14 }),
      "42, 3.14")

    # Empty data
    assert_eq("inja: static text",
      Nodex::Native.render_template("static", {}),
      "static")

    # HTML pass-through (Inja does not escape by default)
    assert_eq("inja: html passthrough",
      Nodex::Native.render_template("{{ c }}", { c: "<b>bold</b>" }),
      "<b>bold</b>")

    # Inja built-in functions
    assert_eq("inja: length()",
      Nodex::Native.render_template("{{ length(items) }}", { items: [1, 2, 3] }),
      "3")

    # inja_available? always true
    assert("inja: available?") { Nodex::Native.inja_available? }

    # Template file
    require 'tempfile'
    f = Tempfile.new(['test', '.html'])
    f.write("<h1>{{ title }}</h1>")
    f.close
    assert_eq("inja: render_template_file",
      Nodex::Native.render_template_file(f.path, { title: "Hello" }),
      "<h1>Hello</h1>")
    f.unlink

    # Template directory
    require 'tmpdir'
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "page.html"), "<p>{{ body }}</p>")
      Nodex::Native.set_template_directory(dir + "/")
      assert_eq("inja: template directory",
        Nodex::Native.render_template_file("page.html", { body: "content" }),
        "<p>content</p>")
    end
  end

  def self.test_concurrent_to_html
    puts "  concurrent to_html (10 threads x 100 renders)..."
    node = Nodex.div([Nodex.h1("Test")])
    expected = node.to_html
    errors = []

    threads = 10.times.map do
      Thread.new do
        100.times do
          fresh = Nodex.div([Nodex.h1("Test")])
          html = fresh.to_html
          errors << "mismatch: #{html.inspect}" if html != expected
        end
      rescue => e
        errors << e.message
      end
    end
    threads.each(&:join)

    assert("concurrent to_html no errors (got #{errors.size})") { errors.empty? }
  end

  def self.test_concurrent_render_opcodes
    puts "  concurrent render_opcodes (10 threads x 100 builds)..."
    expected = Nodex::Native.build { div { p("Thread test") } }
    errors = []

    threads = 10.times.map do
      Thread.new do
        100.times do
          html = Nodex::Native.build { div { p("Thread test") } }
          errors << "mismatch: #{html.inspect}" if html != expected
        end
      rescue => e
        errors << e.message
      end
    end
    threads.each(&:join)

    assert("concurrent render_opcodes no errors (got #{errors.size})") { errors.empty? }
  end

  def self.test_component_api
    puts "  UI::Component API..."

    # Bake via block
    Nodex::UI::Component.bake(:test_comp) do
      [Nodex.h1(Nodex.slot(:title)), Nodex.p(Nodex.slot(:body))]
    end

    html = Nodex::UI::Component.render(:test_comp, title: "Hi", body: "There")
    assert("component render has title") { html.include?("Hi") }
    assert("component render has body") { html.include?("There") }

    node = Nodex::UI::Component.node(:test_comp, title: "A", body: "B")
    assert("component node renders") { node.to_html.include?("A") }
  end

  def self.test_benchmark
    n = 500

    # Cold render: pre-build N trees, then render each once (no cache hits)
    puts "  benchmark: cold render (render only, 500 nodes)..."
    trees = Array.new(n) { build_tree }
    warmup = build_tree
    20.times { warmup.to_html_ruby; warmup.to_html_native }

    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    trees.each { |t| t.to_html_ruby }
    ruby_cold = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t1

    # Fresh trees for C (no @_html_cache set)
    trees = Array.new(n) { build_tree }
    t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    trees.each { |t| t.to_html_native }
    c_cold = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t2

    cold_speedup = ruby_cold / c_cold
    puts "    Ruby cold:  #{(ruby_cold / n * 1000).round(3)}ms/render"
    puts "    C cold:     #{(c_cold / n * 1000).round(3)}ms/render"
    puts "    Speedup:    #{cold_speedup.round(1)}x"

    assert("C cold faster than Ruby (#{cold_speedup.round(1)}x)") { cold_speedup > 1.2 }

    # Cached render: same tree, C returns @_html_cache
    puts "  benchmark: cached render (same tree)..."
    tree = build_tree
    tree.to_html_native  # populate cache

    t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { tree.to_html_ruby }
    ruby_warm = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t3

    t4 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { tree.to_html_native }
    c_cached = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t4

    cached_speedup = ruby_warm / c_cached
    puts "    Ruby:       #{(ruby_warm / n * 1000).round(3)}ms/render"
    puts "    C cached:   #{(c_cached / n * 1000).round(3)}ms/render"
    puts "    Speedup:    #{cached_speedup.round(1)}x"

    assert("C cached >> Ruby (#{cached_speedup.round(1)}x)") { cached_speedup > 50 }
  end
end

NativeTests.run
