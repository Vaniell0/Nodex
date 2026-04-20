# frozen_string_literal: true

# Dashboard benchmark: measures the real benefit of subtree caching
# with partial invalidation vs full re-render.
#
# Simulates a dashboard with N widgets. On each "tick", only 1-2 widgets
# change (e.g. live counter update). Measures three strategies:
#
#   1. Full rebuild: build tree from scratch + render (no cache at all)
#   2. Full re-render (old behavior): same tree, but ALL caches cleared
#   3. Partial invalidation (new): mutate widget, bubble-up clears only
#      the ancestor chain, siblings keep their cache
#
# Run: ruby test/bench_dashboard.rb

$LOAD_PATH.unshift File.expand_path('../../ruby/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'nodex'
require 'nodex/native'

module BenchDashboard
  def self.clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Build a dashboard widget: card with header, metric value, sparkline rows
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
                   .set_style("height", "#{rand(20..80)}px")
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

  # Build full dashboard: header + grid of N widgets
  def self.build_dashboard(n_widgets)
    widgets = (1..n_widgets).map { |i| build_widget(i, rand(100..9999)) }

    Nodex.div([
      Nodex.header([
        Nodex.h1("Operations Dashboard").color("#1a1a2e"),
        Nodex.p("Real-time monitoring — #{n_widgets} widgets").color("#666"),
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

  # Collect all widgets (direct children of the grid div)
  def self.get_widgets(dashboard)
    # dashboard > [header, grid_div, footer]
    grid = dashboard.instance_variable_get(:@children)[1]
    grid.instance_variable_get(:@children)
  end

  def self.clear_all_caches(node)
    node.instance_variable_set(:@_html_cache, nil)
    children = node.instance_variable_get(:@children)
    children&.each { |c| clear_all_caches(c) }
  end

  def self.run
    [20, 50, 100].each do |n_widgets|
      run_scenario(n_widgets)
    end
  end

  def self.run_scenario(n_widgets)
    iters = 500
    mutations_per_tick = 2  # 2 widgets change per tick

    puts "=" * 70
    puts "Dashboard: #{n_widgets} widgets, #{mutations_per_tick} mutations/tick, #{iters} ticks"
    puts "=" * 70

    # ── Build the tree once ────────────────────────────────────────
    dashboard = build_dashboard(n_widgets)
    total_nodes = count_nodes(dashboard)
    puts "Total nodes: #{total_nodes}"

    # Initial render to get HTML size
    html = dashboard.to_html
    puts "HTML size: #{html.bytesize} bytes"
    puts

    # ── Strategy 1: Full rebuild (build + render from scratch) ────
    GC.start; GC.disable
    t = clock
    iters.times do
      d = build_dashboard(n_widgets)
      d.to_html
    end
    full_rebuild = clock - t
    GC.enable

    # ── Strategy 2: Full re-render (clear ALL caches, render) ─────
    # This simulates old behavior where mutation clears only self
    dashboard2 = build_dashboard(n_widgets)
    dashboard2.to_html  # populate caches
    widgets2 = get_widgets(dashboard2)

    GC.start; GC.disable
    t = clock
    iters.times do |tick|
      # Mutate 2 random widgets
      mutations_per_tick.times do
        w = widgets2[tick % n_widgets]
        # Update the metric text
        metric_row = w.instance_variable_get(:@children)[1]
        metric_span = metric_row.instance_variable_get(:@children)[0]
        metric_span.set_text("#{rand(100..9999)}")
      end
      # Old behavior: wipe ALL caches
      clear_all_caches(dashboard2)
      dashboard2.to_html
    end
    full_rerender = clock - t
    GC.enable

    # ── Strategy 3: Partial invalidation (new behavior) ───────────
    dashboard3 = build_dashboard(n_widgets)
    dashboard3.to_html  # populate caches
    widgets3 = get_widgets(dashboard3)

    GC.start; GC.disable
    t = clock
    iters.times do |tick|
      # Mutate 2 random widgets — invalidate_cache! bubbles up automatically
      mutations_per_tick.times do
        w = widgets3[tick % n_widgets]
        metric_row = w.instance_variable_get(:@children)[1]
        metric_span = metric_row.instance_variable_get(:@children)[0]
        metric_span.set_text("#{rand(100..9999)}")
      end
      # Just render — subtree caches for untouched widgets are still valid
      dashboard3.to_html
    end
    partial = clock - t
    GC.enable

    # ── Strategy 4: Cached (no mutation, pure cache hit) ──────────
    dashboard4 = build_dashboard(n_widgets)
    dashboard4.to_html  # populate
    GC.start; GC.disable
    t = clock
    iters.times { dashboard4.to_html }
    cached = clock - t
    GC.enable

    # ── Results ───────────────────────────────────────────────────
    puts "-" * 70
    printf "%-35s %10s %10s\n", "Strategy", "ms/tick", "Speedup"
    puts "-" * 70

    base = full_rebuild / iters * 1000
    results = [
      ["Full rebuild (build+render)",    full_rebuild],
      ["Full re-render (all caches cleared)", full_rerender],
      ["Partial invalidation (new)",     partial],
      ["Pure cache hit (no mutation)",   cached],
    ]

    results.each do |label, elapsed|
      ms = elapsed / iters * 1000
      sp = ms > 0.0001 ? base / ms : Float::INFINITY
      sp_str = sp == Float::INFINITY ? "∞" : "#{sp.round(1)}x"
      printf "%-35s %10.4f %10s\n", label, ms, sp_str
    end

    puts "-" * 70
    improvement = full_rerender / partial
    puts
    puts "Partial vs full re-render: #{improvement.round(1)}x faster"
    pct_saved = ((1.0 - partial / full_rerender) * 100).round(1)
    puts "Work saved by subtree caching: #{pct_saved}%"
    puts
  end
end

BenchDashboard.run
