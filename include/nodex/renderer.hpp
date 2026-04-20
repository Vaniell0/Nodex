#pragma once

#include "core.hpp"

#include <fmt/format.h>
#include <string>

namespace nodex {

// --- Base renderer interface ---
class Renderer {
public:
    virtual ~Renderer() = default;
    virtual std::string Render(const Element& root) const = 0;
};

// --- HTML renderer ---
class HtmlRenderer : public Renderer {
public:
    struct Options {
        bool pretty      = false;
        int  indent_size = 2;
        bool minify      = false;
        Options() = default;
    };

    HtmlRenderer();
    explicit HtmlRenderer(Options opts);
    std::string Render(const Element& root) const override;

    static std::string RenderToString(const Element& root);

private:
    Options opts_;
    void render_node(const Element& node, fmt::memory_buffer& buf, int depth) const;
    void format_opening_tag(const Element& node, fmt::memory_buffer& buf) const;
};

// --- JSON renderer ---
class JsonRenderer : public Renderer {
public:
    struct Options {
        int indent = -1;  // -1 = compact, 2/4 = pretty
        Options() = default;
    };

    JsonRenderer();
    explicit JsonRenderer(Options opts);
    std::string Render(const Element& root) const override;

private:
    Options opts_;
};

// --- HTMX fragment renderer ---
class HtmxRenderer : public Renderer {
public:
    struct Options {
        bool        oob           = false;
        std::string swap_strategy;
        Options() = default;
    };

    HtmxRenderer();
    explicit HtmxRenderer(Options opts);
    std::string Render(const Element& root) const override;

private:
    Options opts_;
    HtmlRenderer html_renderer_;
};

} // namespace nodex
