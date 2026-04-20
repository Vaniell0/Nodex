// Nodex C++ Example — Minimal HTML generation with pipe-operator DSL.
//
// Build:
//   cmake -B build && cmake --build build
//   ./build/example

#include <nodex/nodex.hpp>
#include <fmt/core.h>
#include <iostream>

using namespace nodex;

int main() {
    // ── 1. Basic elements with pipe decorators ──────────────

    auto title = h1("Hello from Nodex") | Bold() | Color("#1a1a2e") | Center();
    auto subtitle = paragraph("Declarative HTML in C++") | Color("#666") | Center();

    fmt::print("=== Basic elements ===\n");
    fmt::print("{}\n\n", HtmlRenderer::RenderToString(title));

    // ── 2. Composing a page with components ─────────────────

    auto card = [](const std::string& name, const std::string& desc) {
        return vbox({
            strong(name) | Bold() | FontSize("1.2em"),
            paragraph(desc) | Color("#555"),
        }) | SetClass("card") | Padding(16) | BorderRadius(8)
          | Border(1, "#ddd");
    };

    auto page = document("My Page",
        {stylesheet("/style.css")},   // head
        {                              // body
            nav({
                a("Home", "/")     | AddClass("nav-link"),
                a("About", "/about") | AddClass("nav-link"),
            }) | SetClass("navbar"),

            div({
                title,
                subtitle,
                hr() | Margin(24),
                h2("Projects") | Bold(),
                div({
                    card("Nodex", "C++20 HTML DSL with pipe-operator"),
                    card("GoodNet", "P2P framework with Ed25519 encryption"),
                }) | Display("grid") | Gap(16),
            }) | SetClass("container") | MaxWidth("800px") | SetStyle("margin: 0 auto"),
        }
    );

    fmt::print("=== Full page ===\n");
    fmt::print("{}\n\n", HtmlRenderer::RenderToString(page));

    // ── 3. Registry for modular components ──────────────────

    Registry reg;

    reg.RegisterComponent("footer", [](const nlohmann::json&) {
        return footer({
            paragraph("Built with Nodex") | Center() | Color("#999"),
        }) | Padding(24);
    });

    auto footer_node = reg.CreateComponent("footer");
    fmt::print("=== Component from registry ===\n");
    fmt::print("{}\n\n", HtmlRenderer::RenderToString(footer_node));

    // ── 4. HTMX integration ────────────────────────────────

    auto search_form = div({
        input("text") | SetAttr("name", "q") | SetAttr("placeholder", "Search..."),
        button("Search") | HxGet("/api/search") | HxTarget("#results") | HxSwap("innerHTML"),
    });

    auto results = div({}) | SetID("results");

    fmt::print("=== HTMX fragment ===\n");
    fmt::print("{}\n", HtmlRenderer::RenderToString(search_form));
    fmt::print("{}\n", HtmlRenderer::RenderToString(results));

    return 0;
}
