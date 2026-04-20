# frozen_string_literal: true

# Multi-level benchmark: compares all optimization levels.
#
# Run: ruby test/bench_levels.rb

$LOAD_PATH.unshift File.expand_path('../../ruby/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'nodex'
require 'nodex/native'

module BenchLevels
  N = 300

  def self.build_tree
    Nodex.div((1..500).map { |i|
      Nodex.div([
        Nodex.h1("Item #{i}").bold.color("#333"),
        Nodex.p("Desc #{i}").padding("10px").margin("5px"),
        Nodex.a("Link", href: "/#{i}"),
      ]).add_class("card")
    })
  end

  def self.clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.bench(label, n = N)
    GC.start
    GC.disable

    # Warmup
    5.times { yield }

    t = clock
    n.times { yield }
    elapsed = clock - t

    GC.enable

    ms = (elapsed / n * 1000)
    { label: label, ms: ms, total: elapsed }
  end

  def self.run
    puts "=" * 60
    puts "Nodex Multi-Level Benchmark (#{N} iterations, 500-node tree)"
    puts "=" * 60
    puts

    results = []

    # ── Level 0: Pure Ruby ──────────────────────────────────────
    # Build + render (what server does today)
    r = bench("Ruby build+render") { build_tree.to_html_ruby }
    results << r
    ruby_baseline = r[:ms]

    # ── Level 0b: C ext cold ────────────────────────────────────
    # Build + render via C extension (fresh tree each time = no cache)
    r = bench("C ext build+render") { build_tree.to_html_native }
    results << r

    # ── Level 1: Registry Cache ─────────────────────────────────
    # Simulate: cached HTML returned as frozen String
    cached_html = build_tree.to_html_native.freeze
    r = bench("Registry cache (raw)") { Nodex.raw(cached_html).to_html }
    results << r

    # ── Level 2: Node Render Cache ──────────────────────────────
    # Same tree, to_html_native returns @_html_cache
    tree = build_tree
    tree.to_html_native  # populate cache
    r = bench("C ext cached (same tree)") { tree.to_html_native }
    results << r

    # ── Level 3a: Baked Template (single card) ──────────────────
    Nodex::Native.bake(:bench_card,
      Nodex.div([
        Nodex.h1(Nodex.slot(:title)).bold.color("#333"),
        Nodex.p(Nodex.slot(:desc)).padding("10px").margin("5px"),
        Nodex.a("Link", href: Nodex.slot(:link)),
      ]).add_class("card")
    )

    r = bench("Baked card (1 card)") {
      Nodex::Native.render_baked(:bench_card,
        title: "Item 1", desc: "Desc 1", link: "/1")
    }
    results << r

    # ── Level 3b: Baked Template (500 cards assembled) ──────────
    # Render 500 baked cards + wrap in div
    r = bench("Baked 500 cards") {
      cards = (1..500).map { |i|
        Nodex::Native.render_baked(:bench_card,
          title: "Item #{i}", desc: "Desc #{i}", link: "/#{i}")
      }
      Nodex.div(cards.map { |c| Nodex.raw(c) }).to_html_native
    }
    results << r

    # ── Level 4: PackedBuilder (opcode stream) ──────────────────
    # Build + render via opcode stream — no Node objects at all
    r = bench("PackedBuilder (500 cards)") {
      Nodex::Native.build {
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
    }
    results << r

    # ── Baseline: raw String return ─────────────────────────────
    raw_str = cached_html
    r = bench("Baseline (return String)") { raw_str }
    results << r

    # ── Print results ───────────────────────────────────────────
    puts
    puts "-" * 60
    printf "%-30s %10s %10s\n", "Level", "ms/render", "Speedup"
    puts "-" * 60

    results.each do |r|
      speedup = if r[:ms] > 0.0001
                  ruby_baseline / r[:ms]
                else
                  Float::INFINITY
                end
      sp_str = speedup == Float::INFINITY ? "∞" : "#{speedup.round(1)}x"
      printf "%-30s %10.4f %10s\n", r[:label], r[:ms], sp_str
    end

    puts "-" * 60
    puts
    puts "Ruby baseline: #{ruby_baseline.round(3)}ms/render"
    puts "Best cache:    #{results[3][:ms] < 0.001 ? '<0.001' : results[3][:ms].round(4)}ms (Node cache)"
    puts "Best baked:    #{results[4][:ms].round(4)}ms (single card)"
  end
end

BenchLevels.run
