// nodex-demo — Minimal demonstration of the Nodex C++ API.

#include <nodex/nodex.hpp>

#include <fmt/core.h>

using namespace nodex;

int main() {
    Registry reg;

    // -- Components --

    reg.RegisterComponent("navbar", [](const nlohmann::json&) {
        return nav({
            a("Home",    "/",       "_self") | AddClass("nav-link"),
            a("About",   "#about",  "_self") | AddClass("nav-link"),
            a("Contact", "#contact","_self") | AddClass("nav-link"),
        }) | SetClass("navbar") | Padding(10);
    });

    reg.RegisterComponent("footer", [](const nlohmann::json&) {
        return footer({
            paragraph("Built with Nodex") | Center() | Color("#999"),
        }) | SetClass("footer") | Padding(10);
    });

    // -- Page --

    auto page = div({
        reg.CreateComponent("navbar"),
        div({
            h1("Hello from Nodex") | Center() | Bold() | Color("#1a1a2e"),
            paragraph("Declarative HTML generation in C++20") | Center() | Color("#666"),
            hr() | Margin(24),
            section({
                h2("Features"),
                ul({
                    li("Pipe-operator DSL: h1(\"...\") | Bold() | Color(\"red\")"),
                    li("Component registry with JSON data"),
                    li("Inja template engine"),
                    li("HTMX integration"),
                }),
            }) | SetID("about") | Padding(20),
        }) | SetClass("container") | MaxWidth("800px") | SetStyle("margin: 0 auto"),
        reg.CreateComponent("footer"),
    });

    // -- Render --

    HtmlRenderer::Options opts;
    opts.pretty = true;
    HtmlRenderer renderer(opts);

    fmt::print("=== HTML ===\n{}\n", renderer.Render(page));

    return 0;
}