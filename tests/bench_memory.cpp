// Memory benchmark — measures RSS/heap for C++ Nodex tree operations.
//
// Build: cmake --build build --target nodex-bench-mem
// Run:   ./build/nodex-bench-mem

#include <nodex/nodex.hpp>
#include <fmt/core.h>
#include <chrono>
#include <string>
#include <fstream>
#include <vector>

using namespace nodex;
using clk = std::chrono::high_resolution_clock;

static long read_rss_kb() {
    std::ifstream f("/proc/self/status");
    std::string line;
    while (std::getline(f, line)) {
        if (line.rfind("VmRSS:", 0) == 0)
            return std::stol(line.substr(6));
    }
    return -1;
}

static Element build_widget(int id, int value) {
    Elements sparkline;
    sparkline.reserve(8);
    for (int j = 1; j <= 8; ++j) {
        auto bar = div({});
        bar->SetStyle("width", "12%");
        bar->SetStyle("height", std::to_string(20 + (id * j * 37) % 60) + "px");
        bar->SetStyle("background", "#e94560");
        bar->SetStyle("border-radius", "2px");
        sparkline.push_back(bar);
    }

    auto metric_val = span(std::to_string(value)) | FontSize(32) | Bold() | Color("#0f3460");
    auto metric_unit = span("units") | FontSize(14) | Color("#888");
    auto metric_row = div({metric_val, metric_unit});
    metric_row->SetStyle("display", "flex");
    metric_row->SetStyle("align-items", "baseline");
    metric_row->SetStyle("gap", "8px");

    auto sparkline_div = div(std::move(sparkline));
    sparkline_div->SetStyle("display", "flex");
    sparkline_div->SetStyle("gap", "4px");
    sparkline_div->SetStyle("align-items", "flex-end");
    sparkline_div->SetStyle("height", "80px");

    auto widget = div({
        h3("Widget " + std::to_string(id)) | Bold() | Color("#1a1a2e"),
        metric_row,
        sparkline_div,
        paragraph("Last updated: tick 0") | Color("#999") | FontSize(12),
    }) | AddClass("widget") | Padding(16) | Border(1, "#eee") | BorderRadius(8);
    widget->SetStyle("min-width", "240px");
    return widget;
}

static Element build_dashboard(int n_widgets) {
    Elements widgets;
    widgets.reserve(n_widgets);
    for (int i = 1; i <= n_widgets; ++i)
        widgets.push_back(build_widget(i, 1000 + i * 7));

    auto hdr = header({
        h1("Operations Dashboard") | Color("#1a1a2e"),
        paragraph("Real-time monitoring — " + std::to_string(n_widgets) + " widgets") | Color("#666"),
    }) | Padding(20);
    hdr->SetStyle("border-bottom", "2px solid #0f3460");

    auto grid_div = div(std::move(widgets));
    grid_div->SetStyle("display", "grid");
    grid_div->SetStyle("grid-template-columns", "repeat(auto-fill, minmax(280px, 1fr))");
    grid_div->SetStyle("gap", "16px");
    grid_div->SetStyle("padding", "20px");

    auto foot = footer({
        paragraph("Nodex Dashboard v1.0") | Color("#999") | FontSize(12),
    }) | Padding(20);
    foot->SetStyle("text-align", "center");

    return div({hdr, grid_div, foot}) | SetID("dashboard");
}

static size_t count_nodes(const Element& node) {
    size_t c = 1;
    for (const auto& ch : node->Children())
        c += count_nodes(ch);
    return c;
}

int main() {
    fmt::print("================================================================\n");
    fmt::print("Nodex C++ Memory Benchmark\n");
    fmt::print("================================================================\n\n");

    long rss_baseline = read_rss_kb();
    fmt::print("Baseline RSS: {} KB\n\n", rss_baseline);

    // ── Part 1: Tree construction memory ────────────────────────────
    fmt::print("== Part 1: Tree Construction Memory ==\n\n");
    fmt::print("{:<12} {:>8} {:>10} {:>14} {:>10}\n",
               "Widgets", "Nodes", "RSS+KB", "bytes/node", "HTML KB");
    fmt::print("{:-<60}\n", "");

    for (int n : {20, 50, 100, 200}) {
        long rss_before = read_rss_kb();

        auto dashboard = build_dashboard(n);
        size_t nodes = count_nodes(dashboard);

        long rss_tree = read_rss_kb();
        auto html = HtmlRenderer::RenderToString(dashboard);
        long rss_html = read_rss_kb();

        long tree_delta = rss_tree - rss_before;
        double bytes_per_node = tree_delta > 0
            ? (double)(tree_delta * 1024) / (double)nodes : 0;
        double html_kb = (double)html.size() / 1024.0;

        fmt::print("{:<12} {:>8} {:>10} {:>14.0f} {:>10.1f}\n",
                   n, nodes, tree_delta, bytes_per_node, html_kb);

        dashboard.reset();
        html.clear();
        html.shrink_to_fit();
    }
    fmt::print("\n");

    // ── Part 2: Build+render memory throughput ──────────────────────
    fmt::print("== Part 2: Build+Render (100 × 50 widgets) ==\n\n");
    {
        long rss_before = read_rss_kb();
        std::vector<std::string> results;
        results.reserve(100);

        auto t0 = clk::now();
        for (int i = 0; i < 100; ++i) {
            auto d = build_dashboard(50);
            results.push_back(HtmlRenderer::RenderToString(d));
        }
        auto t1 = clk::now();
        long rss_after = read_rss_kb();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

        fmt::print("  Time:       {:.1f} ms ({:.2f} ms/iter)\n", ms, ms / 100);
        fmt::print("  RSS delta:  +{} KB\n", rss_after - rss_before);
        fmt::print("  HTML size:  {} bytes each\n", results[0].size());
        fmt::print("\n");
        results.clear();
        results.shrink_to_fit();
    }

    // ── Part 3: Dashboard mutation (C++ has no cache, always full render) ──
    fmt::print("== Part 3: Dashboard Mutation (50 widgets, 500 ticks) ==\n\n");
    {
        auto dashboard = build_dashboard(50);
        auto html_init = HtmlRenderer::RenderToString(dashboard);

        long rss_before = read_rss_kb();
        auto t0 = clk::now();

        for (int tick = 0; tick < 500; ++tick) {
            // Mutate 2 widgets
            auto& grid = dashboard->Children()[1];
            auto& widgets = grid->Children();
            for (int m = 0; m < 2; ++m) {
                int idx = (tick + m) % (int)widgets.size();
                auto& widget = widgets[idx];
                auto& metric_row = widget->Children()[1];
                auto& metric_span = metric_row->Children()[0];
                metric_span->SetTextContent(std::to_string(1000 + tick));
            }
            auto html = HtmlRenderer::RenderToString(dashboard);
            (void)html;
        }

        auto t1 = clk::now();
        long rss_after = read_rss_kb();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

        fmt::print("  Time:       {:.1f} ms ({:.3f} ms/tick)\n", ms, ms / 500);
        fmt::print("  RSS delta:  +{} KB\n", rss_after - rss_before);
        fmt::print("  HTML size:  {} bytes\n", html_init.size());
        fmt::print("\n");
    }

    // ── Part 4: Sustained load — 1000 builds, measure steady-state ──
    fmt::print("== Part 4: Sustained Load (1000 × 50-widget build+render) ==\n\n");
    {
        long rss_before = read_rss_kb();

        auto t0 = clk::now();
        for (int i = 0; i < 1000; ++i) {
            auto d = build_dashboard(50);
            auto html = HtmlRenderer::RenderToString(d);
            (void)html;
        }
        auto t1 = clk::now();
        long rss_after = read_rss_kb();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

        fmt::print("  Time:       {:.0f} ms ({:.2f} ms/iter)\n", ms, ms / 1000);
        fmt::print("  RSS delta:  +{} KB (should be ~0 at steady state)\n",
                   rss_after - rss_before);
        fmt::print("\n");
    }

    long rss_final = read_rss_kb();
    fmt::print("== Summary ==\n");
    fmt::print("  Final RSS:    {} KB\n", rss_final);
    fmt::print("  Total growth: +{} KB from baseline\n", rss_final - rss_baseline);

    return 0;
}
