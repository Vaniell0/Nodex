# frozen_string_literal: true

# Memory benchmark for Nodex Ruby + Native rendering.
#
# Measures: RSS, GC object allocation, per-node overhead,
# and memory behavior under dashboard mutation workload.
#
# Run: ruby test/bench_memory.rb

$LOAD_PATH.unshift File.expand_path('../../ruby/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'nodex'
require 'nodex/native'

module BenchMemory
  def self.rss_kb
    File.readlines('/proc/self/status').each do |line|
      return line.split[1].to_i if line.start_with?('VmRSS:')
    end
    -1
  end

  def self.clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.build_widget(id, value)
    Nodex.div([
      Nodex.h3("Widget #{id}").bold.color("#1a1a2e"),
      Nodex.div([
        Nodex.span_elem("#{value}").font_size("32px").bold.color("#0f3460"),
        Nodex.span_elem("units").font_size("14px").color("#888"),
      ]).set_style("display", "flex").set_style("align-items", "baseline").set_style("gap", "8px"),
      Nodex.div(
        (1..8).map { |j|
          Nodex.div.set_style("width", "12%")
                   .set_style("height", "#{20 + rand(60)}px")
                   .set_style("background", "#e94560")
                   .set_style("border-radius", "2px")
        }
      ).set_style("display", "flex").set_style("gap", "4px").set_style("align-items", "flex-end")
       .set_style("height", "80px"),
      Nodex.p("Last updated: tick 0").color("#999").font_size("12px"),
    ]).add_class("widget")
     .set_style("padding", "16px")
     .set_style("border", "1px solid #eee")
     .set_style("border-radius", "8px")
     .set_style("min-width", "240px")
  end

  def self.build_dashboard(n)
    widgets = (1..n).map { |i| build_widget(i, 1000 + i * 7) }

    Nodex.div([
      Nodex.header([
        Nodex.h1("Operations Dashboard").color("#1a1a2e"),
        Nodex.p("Real-time monitoring — #{n} widgets").color("#666"),
      ]).set_style("padding", "20px").set_style("border-bottom", "2px solid #0f3460"),

      Nodex.div(widgets)
        .set_style("display", "grid")
        .set_style("grid-template-columns", "repeat(auto-fill, minmax(280px, 1fr))")
        .set_style("gap", "16px")
        .set_style("padding", "20px"),

      Nodex.footer([
        Nodex.p("Nodex Dashboard v1.0").color("#999").font_size("12px"),
      ]).set_style("padding", "20px").set_style("text-align", "center"),
    ]).set_id("dashboard")
  end

  def self.count_nodes(node)
    count = 1
    children = node.instance_variable_get(:@children)
    children&.each { |c| count += count_nodes(c) }
    count
  end

  def self.get_widgets(dashboard)
    dashboard.instance_variable_get(:@children)[1].instance_variable_get(:@children)
  end

  def self.clear_all_caches(node)
    node.instance_variable_set(:@_html_cache, nil)
    children = node.instance_variable_get(:@children)
    children&.each { |c| clear_all_caches(c) }
  end

  def self.count_cached(node)
    c = node.instance_variable_get(:@_html_cache) ? 1 : 0
    children = node.instance_variable_get(:@children)
    children&.each { |ch| c += count_cached(ch) }
    c
  end

  def self.separator
    puts "-" * 72
  end

  def self.gc_settle
    3.times { GC.start(full_mark: true, immediate_sweep: true) }
    GC.compact rescue nil
  end

  def self.run
    puts "=" * 72
    puts "Nodex Memory Benchmark — Ruby Native (subtree cache)"
    puts "Ruby #{RUBY_VERSION}, #{RUBY_PLATFORM}"
    puts "=" * 72
    puts

    gc_settle
    rss_start = rss_kb
    puts "Baseline RSS: #{rss_start} KB"
    puts

    # ──────────────────────────────────────────────────────────────────
    # Part 1: Tree + cache memory scaling
    # ──────────────────────────────────────────────────────────────────
    puts "== Part 1: Tree + Cache Memory Scaling =="
    puts
    separator
    printf "%-10s %7s %9s %13s %9s %11s %13s\n",
           "Widgets", "Nodes", "HTML KB", "Tree objs", "Tree KB",
           "Cache objs", "Cache KB"
    separator

    [10, 25, 50, 100, 200, 500].each do |n|
      gc_settle
      objs_before = GC.stat[:total_allocated_objects]
      rss_before = rss_kb

      dashboard = build_dashboard(n)
      nodes = count_nodes(dashboard)

      gc_settle
      objs_tree = GC.stat[:total_allocated_objects]
      rss_tree = rss_kb

      html = dashboard.to_html  # populates subtree caches
      html_kb = html.bytesize / 1024.0

      gc_settle
      objs_cached = GC.stat[:total_allocated_objects]
      rss_cached = rss_kb

      tree_objs = objs_tree - objs_before
      tree_kb = rss_tree - rss_before
      cache_objs = objs_cached - objs_tree
      cache_kb = rss_cached - rss_tree

      printf "%-10d %7d %9.1f %13d %9d %11d %13d\n",
             n, nodes, html_kb, tree_objs, tree_kb, cache_objs, cache_kb

      dashboard = nil; html = nil
      gc_settle
    end
    separator
    puts

    # ──────────────────────────────────────────────────────────────────
    # Part 2: Cache analysis — 100 widgets
    # ──────────────────────────────────────────────────────────────────
    puts "== Part 2: Subtree Cache Analysis (100 widgets) =="
    puts

    gc_settle
    dashboard = build_dashboard(100)
    nodes = count_nodes(dashboard)

    gc_settle
    slots_before = GC.stat[:heap_live_slots]

    html = dashboard.to_html

    gc_settle
    slots_after = GC.stat[:heap_live_slots]
    cached = count_cached(dashboard)

    puts "  Nodes:             #{nodes}"
    puts "  Cached nodes:      #{cached} / #{nodes} (#{(cached.to_f/nodes*100).round(1)}%)"
    puts "  Heap slots used:   +#{slots_after - slots_before} (for cache strings)"
    puts "  HTML output:       #{html.bytesize} bytes"
    cache_overhead = (slots_after - slots_before) * 40  # ~40 bytes per slot
    puts "  Est cache overhead: #{(cache_overhead / 1024.0).round(1)} KB (#{cached} strings × ~40B slot)"
    puts "  Cache/HTML ratio:  #{(cache_overhead.to_f / html.bytesize).round(2)}x"
    puts

    dashboard = nil; html = nil
    gc_settle

    # ──────────────────────────────────────────────────────────────────
    # Part 3: Mutation workload — object allocation comparison
    # ──────────────────────────────────────────────────────────────────
    puts "== Part 3: Mutation Workload (50 widgets, 500 ticks, 2 mut/tick) =="
    puts
    puts "  Measures: total objects allocated (= GC pressure)"
    puts

    ticks = 500

    # Strategy A: Full rebuild
    gc_settle
    alloc_before = GC.stat[:total_allocated_objects]
    t = clock
    ticks.times { build_dashboard(50).to_html_ruby }
    elapsed_a = clock - t
    alloc_a = GC.stat[:total_allocated_objects] - alloc_before
    gc_settle

    # Strategy B: Mutate + full cache wipe (old behavior)
    db = build_dashboard(50)
    db.to_html
    widgets_b = get_widgets(db)
    gc_settle
    alloc_before = GC.stat[:total_allocated_objects]
    t = clock
    ticks.times do |tick|
      2.times { |m|
        w = widgets_b[(tick + m) % 50]
        w.instance_variable_get(:@children)[1]
         .instance_variable_get(:@children)[0]
         .set_text("#{rand(100..9999)}")
      }
      clear_all_caches(db)
      db.to_html
    end
    elapsed_b = clock - t
    alloc_b = GC.stat[:total_allocated_objects] - alloc_before
    db = nil; gc_settle

    # Strategy C: Partial invalidation (new)
    dc = build_dashboard(50)
    dc.to_html
    widgets_c = get_widgets(dc)
    gc_settle
    alloc_before = GC.stat[:total_allocated_objects]
    t = clock
    ticks.times do |tick|
      2.times { |m|
        w = widgets_c[(tick + m) % 50]
        w.instance_variable_get(:@children)[1]
         .instance_variable_get(:@children)[0]
         .set_text("#{rand(100..9999)}")
      }
      dc.to_html
    end
    elapsed_c = clock - t
    alloc_c = GC.stat[:total_allocated_objects] - alloc_before
    dc = nil; gc_settle

    separator
    printf "%-40s %10s %14s %12s\n", "Strategy", "ms/tick", "Objs alloc", "Alloc ratio"
    separator
    printf "%-40s %10.3f %14d %12s\n",
           "A: Full rebuild (build+render)", elapsed_a / ticks * 1000, alloc_a, "1.0x"
    printf "%-40s %10.3f %14d %12.1fx\n",
           "B: Mutate + full cache wipe (old)", elapsed_b / ticks * 1000, alloc_b,
           alloc_a.to_f / alloc_b
    printf "%-40s %10.3f %14d %12.1fx\n",
           "C: Partial invalidation (NEW)", elapsed_c / ticks * 1000, alloc_c,
           alloc_a.to_f / alloc_c
    separator
    puts
    puts "  Object reduction: C allocates #{(alloc_c.to_f / alloc_b * 100).round(1)}% " \
         "of B's objects (#{((1 - alloc_c.to_f/alloc_b) * 100).round(1)}% less GC pressure)"
    puts "  Speed: C is #{(elapsed_b / elapsed_c).round(1)}x faster than B"
    puts

    # ──────────────────────────────────────────────────────────────────
    # Part 4: GC pressure — detailed
    # ──────────────────────────────────────────────────────────────────
    puts "== Part 4: GC Events (100 ticks, partial invalidation) =="
    puts

    dd = build_dashboard(50)
    dd.to_html
    widgets_d = get_widgets(dd)

    gc_settle
    gc_before = GC.stat.dup

    100.times do |tick|
      2.times { |m|
        w = widgets_d[(tick + m) % 50]
        w.instance_variable_get(:@children)[1]
         .instance_variable_get(:@children)[0]
         .set_text("#{rand(100..9999)}")
      }
      dd.to_html
    end

    gc_after = GC.stat

    puts "  GC runs:          +#{gc_after[:count] - gc_before[:count]}"
    puts "  Major GC:         +#{gc_after[:major_gc_count] - gc_before[:major_gc_count]}"
    puts "  Objects allocated: +#{gc_after[:total_allocated_objects] - gc_before[:total_allocated_objects]}"
    puts "  Objects freed:     +#{gc_after[:total_freed_objects] - gc_before[:total_freed_objects]}"
    puts "  Heap live slots:  #{gc_after[:heap_live_slots]}"
    puts

    dd = nil; gc_settle

    # ──────────────────────────────────────────────────────────────────
    # Part 5: RSS stability under sustained load
    # ──────────────────────────────────────────────────────────────────
    puts "== Part 5: RSS Stability (sustained partial-invalidation load) =="
    puts

    de = build_dashboard(50)
    de.to_html
    widgets_e = get_widgets(de)

    gc_settle
    rss_before = rss_kb

    2000.times do |tick|
      2.times { |m|
        w = widgets_e[(tick + m) % 50]
        w.instance_variable_get(:@children)[1]
         .instance_variable_get(:@children)[0]
         .set_text("#{rand(100..9999)}")
      }
      de.to_html
    end

    gc_settle
    rss_after = rss_kb

    puts "  2000 ticks with partial invalidation"
    puts "  RSS before: #{rss_before} KB"
    puts "  RSS after:  #{rss_after} KB"
    puts "  RSS delta:  #{rss_after - rss_before >= 0 ? '+' : ''}#{rss_after - rss_before} KB"
    puts

    de = nil; gc_settle

    # ──────────────────────────────────────────────────────────────────
    # Summary
    # ──────────────────────────────────────────────────────────────────
    rss_final = rss_kb
    puts "=" * 72
    puts "Final RSS: #{rss_final} KB (#{rss_final - rss_start >= 0 ? '+' : ''}#{rss_final - rss_start} KB from start)"
    puts
    puts "Key takeaways:"
    puts "  - Partial invalidation allocates #{(alloc_c.to_f / alloc_a * 100).round(2)}% objects vs full rebuild"
    puts "  - #{(alloc_c.to_f / alloc_b * 100).round(1)}% objects vs full cache wipe"
    puts "  - #{(elapsed_b / elapsed_c).round(1)}x faster than full re-render"
    puts "  - #{(elapsed_a / elapsed_c).round(0)}x faster than full rebuild"
    puts "  - GC pressure is minimal: ~#{(alloc_c.to_f / ticks).round(0)} objects/tick"
    puts "    (vs ~#{(alloc_a.to_f / ticks).round(0)}/tick for rebuild,"
    puts "     vs ~#{(alloc_b.to_f / ticks).round(0)}/tick for full wipe)"
  end
end

BenchMemory.run
