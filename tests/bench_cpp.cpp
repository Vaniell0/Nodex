// C++ benchmark — same 500-card tree as Ruby bench_levels.rb
// Build: cmake --build build --target nodex-bench
// Run:   ./build/nodex-bench

#include <nodex/nodex.hpp>
#include <fmt/core.h>
#include <chrono>
#include <string>

using namespace nodex;
using clk = std::chrono::high_resolution_clock;

static Element build_tree() {
    Elements cards;
    cards.reserve(500);
    for (int i = 1; i <= 500; ++i) {
        auto s = std::to_string(i);
        cards.push_back(
            div({
                h1("Item " + s) | Bold() | Color("#333"),
                paragraph("Desc " + s) | Padding(10) | Margin(5),
                a("Link", "/" + s),
            }) | AddClass("card")
        );
    }
    return div(std::move(cards));
}

int main() {
    constexpr int N = 300;

    fmt::print("============================================================\n");
    fmt::print("Nodex C++ Benchmark ({} iterations, 500-node tree)\n", N);
    fmt::print("============================================================\n\n");

    // Warmup
    for (int i = 0; i < 5; ++i) {
        auto tree = build_tree();
        HtmlRenderer::RenderToString(tree);
    }

    // ── Build + Render (what server does) ──────────────────────
    {
        auto t0 = clk::now();
        for (int i = 0; i < N; ++i) {
            auto tree = build_tree();
            HtmlRenderer::RenderToString(tree);
        }
        auto t1 = clk::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / N;
        fmt::print("C++ build+render:      {:.4f} ms/iter\n", ms);
    }

    // ── Build only ─────────────────────────────────────────────
    {
        auto t0 = clk::now();
        for (int i = 0; i < N; ++i) {
            auto tree = build_tree();
            (void)tree;
        }
        auto t1 = clk::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / N;
        fmt::print("C++ build only:        {:.4f} ms/iter\n", ms);
    }

    // ── Render only (pre-built tree) ───────────────────────────
    {
        auto tree = build_tree();
        auto t0 = clk::now();
        for (int i = 0; i < N; ++i) {
            HtmlRenderer::RenderToString(tree);
        }
        auto t1 = clk::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / N;
        fmt::print("C++ render only:       {:.4f} ms/iter\n", ms);
    }

    // ── Render minified ────────────────────────────────────────
    {
        HtmlRenderer::Options opts;
        opts.minify = true;
        HtmlRenderer renderer(opts);
        auto tree = build_tree();
        auto t0 = clk::now();
        for (int i = 0; i < N; ++i) {
            renderer.Render(tree);
        }
        auto t1 = clk::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / N;
        fmt::print("C++ render minified:   {:.4f} ms/iter\n", ms);
    }

    fmt::print("\n");

    // Print HTML size for reference
    auto tree = build_tree();
    auto html = HtmlRenderer::RenderToString(tree);
    fmt::print("HTML output size: {} bytes\n", html.size());

    return 0;
}
