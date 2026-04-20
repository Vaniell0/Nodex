# frozen_string_literal: true

# Simulates Puma-style worker processes via separate ruby subprocesses.
# Measures real parallel throughput scaling.
#
# Run: ruby test/bench_workers.rb

ITERS = 2000

# Worker script executed in subprocess
WORKER_SCRIPT = <<~'RUBY'
  $LOAD_PATH.unshift File.expand_path('../../ruby/lib', __dir__)
  $LOAD_PATH.unshift File.expand_path('../lib', __dir__)
  require 'nodex'
  require 'nodex/native'

  mode = ARGV[0]
  n    = ARGV[1].to_i

  # Prepare
  Nodex::Native.bake(:w_card,
    Nodex.div([
      Nodex.h1(Nodex.slot(:title)).bold.color("#333"),
      Nodex.p(Nodex.slot(:desc)).padding("10px"),
      Nodex.a("Link", href: Nodex.slot(:link)),
    ]).add_class("card")
  )

  work = case mode
  when "to_html"
    -> {
      Nodex.div([
        Nodex.h1("Hello").bold,
        Nodex.p("World").color("#666"),
        Nodex.a("Link", href: "/"),
      ]).to_html
    }
  when "render_baked"
    -> {
      Nodex::Native.render_baked(:w_card,
        title: "Item", desc: "Description", link: "/item")
    }
  when "packed_builder"
    -> {
      Nodex::Native.build {
        div {
          h1("Hello").bold
          p("World").color("#666")
          a("Link", href: "/")
        }
      }
    }
  when "page_50"
    -> {
      Nodex.div((1..50).map { |i|
        Nodex.div([
          Nodex.h1("Item #{i}").bold.color("#333"),
          Nodex.p("Desc #{i}").padding("10px"),
        ]).add_class("card")
      }).to_html
    }
  end

  # Warmup
  10.times { work.call }
  GC.start; GC.disable

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  n.times { work.call }
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  GC.enable
  $stdout.write("%.6f" % (t1 - t0))
RUBY

SCRIPT_PATH = File.join(__dir__, '_bench_worker_child.rb')
File.write(SCRIPT_PATH, WORKER_SCRIPT)

def clock
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def bench_workers(mode, n_workers, iters)
  t0 = clock

  threads = n_workers.times.map do
    Thread.new do
      out = IO.popen(["ruby", SCRIPT_PATH, mode, iters.to_s], "r") { |io| io.read }
      out.to_f
    end
  end

  worker_times = threads.map(&:value)
  wall = clock - t0

  total_ops = n_workers * iters
  { workers: n_workers, total_ops: total_ops, wall: wall,
    ops_per_sec: total_ops / wall }
end

MODES = {
  "to_html (5-node)" => "to_html",
  "render_baked (3 slots)" => "render_baked",
  "PackedBuilder (5-node)" => "packed_builder",
  "to_html (50-card page)" => "page_50",
}

WORKER_COUNTS = [1, 2, 4, 8]

puts "=" * 70
puts "Nodex Worker Benchmark (subprocesses, #{ITERS} iters/worker)"
puts "CPU cores: #{`nproc`.strip}"
puts "=" * 70

MODES.each do |label, mode|
  puts
  puts "── #{label} ──"
  printf "  %-10s %10s %10s %12s %10s\n",
         "Workers", "Total ops", "Wall(s)", "ops/sec", "Scale"
  puts "  " + "-" * 58

  baseline = nil

  WORKER_COUNTS.each do |wc|
    r = bench_workers(mode, wc, ITERS)
    baseline ||= r[:ops_per_sec]
    scale = r[:ops_per_sec] / baseline

    printf "  %-10d %10d %10.3f %12.0f %10.1fx\n",
           r[:workers], r[:total_ops], r[:wall],
           r[:ops_per_sec], scale
  end
end

File.delete(SCRIPT_PATH) if File.exist?(SCRIPT_PATH)

puts
puts "=" * 70
puts "Scale = ops/sec relative to 1-worker. Linear = Nx for N workers."
