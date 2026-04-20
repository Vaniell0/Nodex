# frozen_string_literal: true

# Concurrent benchmark: measures throughput scaling across 1/2/4/8 threads.
#
# Run: ruby test/bench_concurrent.rb

$LOAD_PATH.unshift File.expand_path('../../ruby/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'nodex'
require 'nodex/native'

module BenchConcurrent
  ITERS_PER_THREAD = 500
  THREAD_COUNTS    = [1, 2, 4, 8]

  def self.clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Run block in N threads, each doing ITERS_PER_THREAD iterations.
  # Returns: { threads:, total_ops:, elapsed:, ops_per_sec:, errors: }
  def self.bench_threads(n_threads, label)
    errors = []

    # Warmup (single-threaded)
    10.times { yield }

    GC.start
    GC.disable

    t0 = clock
    threads = n_threads.times.map do
      Thread.new do
        ITERS_PER_THREAD.times { yield }
      rescue => e
        errors << e.message
      end
    end
    threads.each(&:join)
    elapsed = clock - t0

    GC.enable

    total_ops = n_threads * ITERS_PER_THREAD
    {
      label: label,
      threads: n_threads,
      total_ops: total_ops,
      elapsed: elapsed,
      ops_per_sec: total_ops / elapsed,
      errors: errors.size
    }
  end

  def self.run
    puts "=" * 70
    puts "Nodex Concurrent Benchmark (#{ITERS_PER_THREAD} iters/thread)"
    puts "=" * 70

    # --- Prepare templates ---
    Nodex::Native.bake(:conc_card,
      Nodex.div([
        Nodex.h1(Nodex.slot(:title)).bold.color("#333"),
        Nodex.p(Nodex.slot(:desc)).padding("10px"),
      ]).add_class("card")
    )

    benchmarks = {
      "to_html (fresh tree)" => -> {
        Nodex.div([
          Nodex.h1("Hello").bold,
          Nodex.p("World").color("#666"),
        ]).to_html
      },
      "render_baked" => -> {
        Nodex::Native.render_baked(:conc_card,
          title: "Item", desc: "Description")
      },
      "PackedBuilder" => -> {
        Nodex::Native.build {
          div {
            h1("Hello").bold
            p("World").color("#666")
          }
        }
      },
      "render_template" => -> {
        Nodex::Native.render_template(
          "Hello {{ name }}, you have {{ count }} items.",
          { name: "User", count: 42 })
      },
    }

    benchmarks.each do |name, work|
      puts
      puts "── #{name} ──"
      printf "  %-10s %12s %12s %10s %8s\n",
             "Threads", "Total ops", "Elapsed(s)", "ops/sec", "Errors"
      puts "  " + "-" * 56

      baseline_ops = nil

      THREAD_COUNTS.each do |tc|
        r = bench_threads(tc, name, &work)
        baseline_ops ||= r[:ops_per_sec]
        scale = r[:ops_per_sec] / baseline_ops

        printf "  %-10d %12d %12.3f %10.0f %8d  (%.1fx)\n",
               r[:threads], r[:total_ops], r[:elapsed],
               r[:ops_per_sec], r[:errors], scale
      end
    end

    puts
    puts "=" * 70
    puts "Done. Scale = ops/sec relative to 1-thread baseline."
    puts "Linear scaling = Nx for N threads."
  end
end

BenchConcurrent.run
