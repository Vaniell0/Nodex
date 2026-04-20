#include "nodex/renderer.hpp"

#include <fmt/format.h>

namespace nodex {

// ============================================================================
// HtmlRenderer
// ============================================================================

HtmlRenderer::HtmlRenderer() : opts_() {}
HtmlRenderer::HtmlRenderer(Options opts) : opts_(std::move(opts)) {}

std::string HtmlRenderer::RenderToString(const Element& root) {
    HtmlRenderer renderer;
    return renderer.Render(root);
}

std::string HtmlRenderer::Render(const Element& root) const {
    if (!root) return {};

    // Fast path: root cache hit
    const auto& cache = root->HtmlCache();
    if (!cache.empty()) return cache;

    fmt::memory_buffer buf;
    render_node(root, buf, 0);
    return fmt::to_string(buf);
}

void HtmlRenderer::format_opening_tag(const Element& node,
                                       fmt::memory_buffer& buf) const {
    auto out = std::back_inserter(buf);
    fmt::format_to(out, "<{}", node->Tag());

    // ID
    if (auto id = node->GetID(); !id.empty()) {
        fmt::format_to(out, " id=\"{}\"", Node::EscapeHTML(id));
    }

    // Classes
    if (auto cls = node->ClassString(); !cls.empty()) {
        fmt::format_to(out, " class=\"{}\"", Node::EscapeHTML(cls));
    }

    // Styles
    if (auto style = node->StyleString(); !style.empty()) {
        fmt::format_to(out, " style=\"{}\"", Node::EscapeHTML(style));
    }

    // Other attributes (skip id — already handled)
    for (const auto& [key, value] : node->Attributes()) {
        if (key == "id") continue;
        if (value.empty()) {
            fmt::format_to(out, " {}", key);
        } else {
            fmt::format_to(out, " {}=\"{}\"", key, Node::EscapeHTML(value));
        }
    }

    if (node->IsSelfClosing()) {
        fmt::format_to(out, " />");
    } else {
        buf.push_back('>');
    }
}

void HtmlRenderer::render_node(const Element& node, fmt::memory_buffer& buf,
                                int depth) const {
    if (!node) return;

    // Subtree cache check — emit cached HTML directly
    const auto& cache = node->HtmlCache();
    if (!cache.empty()) {
        buf.append(cache.data(), cache.data() + cache.size());
        return;
    }

    size_t html_start = buf.size();  // record for caching later

    auto out = std::back_inserter(buf);

    auto indent = [&]() {
        if (opts_.pretty && !opts_.minify) {
            auto n = static_cast<size_t>(depth * opts_.indent_size);
            for (size_t i = 0; i < n; ++i) buf.push_back(' ');
        }
    };
    auto newline = [&]() {
        if (opts_.pretty && !opts_.minify) {
            buf.push_back('\n');
        }
    };

    const auto& tag      = node->Tag();
    const auto& text     = node->TextContent();
    const auto& children = node->Children();

    bool has_styles  = !node->Styles().empty();
    bool has_classes = !node->Classes().empty();
    bool has_attrs   = !node->Attributes().empty();
    bool has_decoration = has_styles || has_classes || has_attrs;

    // DOCTYPE for root <html> element
    if (tag == "html" && depth == 0) {
        fmt::format_to(out, "<!DOCTYPE html>\n");
    }

    // Text node (empty tag) — trivially cheap, skip caching
    if (tag.empty()) {
        if (node->IsRaw()) {
            indent();
            fmt::format_to(out, "{}", text);
            newline();
            return;
        }

        if (!has_decoration) {
            indent();
            fmt::format_to(out, "{}", Node::EscapeHTML(text));
            newline();
            return;
        }

        // Styled text node -> wrap in <span>
        indent();
        auto span_node = std::make_shared<Node>("span", text);
        for (const auto& [k, v] : node->Styles())
            span_node->SetStyle(k, v);
        for (const auto& c : node->Classes())
            span_node->AddClass(c);
        for (const auto& [k, v] : node->Attributes())
            span_node->SetAttribute(k, v);

        format_opening_tag(span_node, buf);
        // Re-acquire out after potential buffer reallocation
        out = std::back_inserter(buf);
        fmt::format_to(out, "{}", Node::EscapeHTML(text));
        fmt::format_to(out, "</span>");
        newline();
        return;
    }

    // Self-closing elements
    if (node->IsSelfClosing()) {
        indent();
        format_opening_tag(node, buf);
        newline();
        // Cache this void element
        node->SetHtmlCache(std::string(buf.data() + html_start, buf.size() - html_start));
        return;
    }

    // Normal element with tag
    indent();
    format_opening_tag(node, buf);

    bool has_children = !children.empty();
    bool has_text     = !text.empty();

    if (!has_children && !has_text) {
        out = std::back_inserter(buf);
        fmt::format_to(out, "</{}>", tag);
        newline();
        node->SetHtmlCache(std::string(buf.data() + html_start, buf.size() - html_start));
        return;
    }

    if (has_text && !has_children) {
        out = std::back_inserter(buf);
        fmt::format_to(out, "{}</{}>", Node::EscapeHTML(text), tag);
        newline();
        node->SetHtmlCache(std::string(buf.data() + html_start, buf.size() - html_start));
        return;
    }

    // Has children
    newline();
    for (const auto& child : children) {
        render_node(child, buf, depth + 1);
    }
    indent();
    out = std::back_inserter(buf);
    fmt::format_to(out, "</{}>", tag);
    newline();
    // Cache this subtree
    node->SetHtmlCache(std::string(buf.data() + html_start, buf.size() - html_start));
}

// ============================================================================
// JsonRenderer
// ============================================================================

JsonRenderer::JsonRenderer() : opts_() {}
JsonRenderer::JsonRenderer(Options opts) : opts_(std::move(opts)) {}

std::string JsonRenderer::Render(const Element& root) const {
    if (!root) return "null";
    nlohmann::json j = root->ToJSON();
    if (opts_.indent >= 0) {
        return j.dump(opts_.indent);
    }
    return j.dump();
}

// ============================================================================
// HtmxRenderer
// ============================================================================

HtmxRenderer::HtmxRenderer() : opts_() {}
HtmxRenderer::HtmxRenderer(Options opts) : opts_(std::move(opts)) {}

std::string HtmxRenderer::Render(const Element& root) const {
    if (!root) return "";

    // Apply HTMX-specific attributes if configured
    if (opts_.oob) {
        root->SetAttribute("hx-swap-oob", "true");
    }
    if (!opts_.swap_strategy.empty() && !root->HasAttribute("hx-swap")) {
        root->SetAttribute("hx-swap", opts_.swap_strategy);
    }

    return html_renderer_.Render(root);
}

} // namespace nodex
