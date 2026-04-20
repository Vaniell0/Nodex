#include "nodex/elements.hpp"

#include <algorithm>
#include <fstream>

namespace nodex {

// --- Helpers ---

static Element make_node(const std::string& tag, Elements children = {}) {
    return std::make_shared<Node>(tag, std::move(children));
}

static Element make_text_node(const std::string& tag, const std::string& content) {
    return std::make_shared<Node>(tag, content);
}

static Element apply_attrs(Element node, const Attrs& attrs) {
    for (const auto& [k, v] : attrs) {
        node->SetAttribute(k, v);
    }
    return node;
}

// --- Text elements ---

Element text(const std::string& content) {
    return std::make_shared<Node>("", content);
}

Element text(const std::string& content, const Attrs& attrs) {
    return apply_attrs(text(content), attrs);
}

Element paragraph(const std::string& content) {
    return make_text_node("p", content);
}

Element paragraph(const std::string& content, const Attrs& attrs) {
    return apply_attrs(paragraph(content), attrs);
}

Element paragraph(Elements children) {
    return make_node("p", std::move(children));
}

Element heading(int level, const std::string& content) {
    level = std::clamp(level, 1, 6);
    return make_text_node(fmt::format("h{}", level), content);
}

Element heading(int level, const std::string& content, const Attrs& attrs) {
    return apply_attrs(heading(level, content), attrs);
}

Element h1(const std::string& content) { return heading(1, content); }
Element h2(const std::string& content) { return heading(2, content); }
Element h3(const std::string& content) { return heading(3, content); }
Element h4(const std::string& content) { return heading(4, content); }
Element h5(const std::string& content) { return heading(5, content); }
Element h6(const std::string& content) { return heading(6, content); }

Element code(const std::string& content) {
    return make_text_node("code", content);
}

Element pre(const std::string& content) {
    return make_text_node("pre", content);
}

Element blockquote(const std::string& content) {
    return make_text_node("blockquote", content);
}

Element blockquote(Elements children) {
    return make_node("blockquote", std::move(children));
}

// --- Containers ---

Element div(Elements children) {
    return make_node("div", std::move(children));
}

Element div(Elements children, const Attrs& attrs) {
    return apply_attrs(div(std::move(children)), attrs);
}

Element section(Elements children) {
    return make_node("section", std::move(children));
}

Element section(Elements children, const Attrs& attrs) {
    return apply_attrs(section(std::move(children)), attrs);
}

Element article(Elements children) {
    return make_node("article", std::move(children));
}

Element article(Elements children, const Attrs& attrs) {
    return apply_attrs(article(std::move(children)), attrs);
}

Element nav(Elements children) {
    return make_node("nav", std::move(children));
}

Element nav(Elements children, const Attrs& attrs) {
    return apply_attrs(nav(std::move(children)), attrs);
}

Element header(Elements children) {
    return make_node("header", std::move(children));
}

Element header(Elements children, const Attrs& attrs) {
    return apply_attrs(header(std::move(children)), attrs);
}

Element footer(Elements children) {
    return make_node("footer", std::move(children));
}

Element footer(Elements children, const Attrs& attrs) {
    return apply_attrs(footer(std::move(children)), attrs);
}

Element main_elem(Elements children) {
    return make_node("main", std::move(children));
}

Element main_elem(Elements children, const Attrs& attrs) {
    return apply_attrs(main_elem(std::move(children)), attrs);
}

Element aside(Elements children) {
    return make_node("aside", std::move(children));
}

Element aside(Elements children, const Attrs& attrs) {
    return apply_attrs(aside(std::move(children)), attrs);
}

Element span(Elements children) {
    return make_node("span", std::move(children));
}

Element span(const std::string& content) {
    return make_text_node("span", content);
}

Element span(const std::string& content, const Attrs& attrs) {
    return apply_attrs(span(content), attrs);
}

// --- Layout ---

Element hbox(Elements children) {
    auto node = make_node("div", std::move(children));
    node->SetStyle("display", "flex");
    node->SetStyle("flex-direction", "row");
    return node;
}

Element hbox(Elements children, const Attrs& attrs) {
    return apply_attrs(hbox(std::move(children)), attrs);
}

Element vbox(Elements children) {
    auto node = make_node("div", std::move(children));
    node->SetStyle("display", "flex");
    node->SetStyle("flex-direction", "column");
    return node;
}

Element vbox(Elements children, const Attrs& attrs) {
    return apply_attrs(vbox(std::move(children)), attrs);
}

Element grid(Elements children, int columns) {
    auto node = make_node("div", std::move(children));
    node->SetStyle("display", "grid");
    node->SetStyle("grid-template-columns", fmt::format("repeat({}, 1fr)", columns));
    return node;
}

Element grid(Elements children, int columns, const Attrs& attrs) {
    return apply_attrs(grid(std::move(children), columns), attrs);
}

// --- Lists ---

Element ul(Elements items) {
    return make_node("ul", std::move(items));
}

Element ul(Elements items, const Attrs& attrs) {
    return apply_attrs(ul(std::move(items)), attrs);
}

Element ol(Elements items) {
    return make_node("ol", std::move(items));
}

Element ol(Elements items, const Attrs& attrs) {
    return apply_attrs(ol(std::move(items)), attrs);
}

Element li(const std::string& content) {
    return make_text_node("li", content);
}

Element li(Elements children) {
    return make_node("li", std::move(children));
}

// --- Tables ---

Element table(Elements rows) {
    return make_node("table", std::move(rows));
}

Element table(Elements rows, const Attrs& attrs) {
    return apply_attrs(table(std::move(rows)), attrs);
}

Element thead(Elements rows) {
    return make_node("thead", std::move(rows));
}

Element tbody(Elements rows) {
    return make_node("tbody", std::move(rows));
}

Element tr(Elements cells) {
    return make_node("tr", std::move(cells));
}

Element th(const std::string& content) {
    return make_text_node("th", content);
}

Element th(Elements children) {
    return make_node("th", std::move(children));
}

Element td(const std::string& content) {
    return make_text_node("td", content);
}

Element td(Elements children) {
    return make_node("td", std::move(children));
}

// --- Forms ---

Element form(Elements children) {
    return make_node("form", std::move(children));
}

Element form(Elements children, const Attrs& attrs) {
    return apply_attrs(form(std::move(children)), attrs);
}

Element input(const std::string& type, const Attrs& attrs) {
    auto node = std::make_shared<Node>("input");
    node->SetAttribute("type", type);
    return apply_attrs(node, attrs);
}

Element textarea(const std::string& content, const Attrs& attrs) {
    auto node = make_text_node("textarea", content);
    return apply_attrs(node, attrs);
}

Element select(Elements options, const Attrs& attrs) {
    return apply_attrs(make_node("select", std::move(options)), attrs);
}

Element option(const std::string& label, const std::string& value) {
    auto node = make_text_node("option", label);
    node->SetAttribute("value", value);
    return node;
}

Element button(const std::string& label, const Attrs& attrs) {
    return apply_attrs(make_text_node("button", label), attrs);
}

Element label(const std::string& content, const Attrs& attrs) {
    return apply_attrs(make_text_node("label", content), attrs);
}

// --- Media ---

Element img(const std::string& src, const std::string& alt) {
    auto node = std::make_shared<Node>("img");
    node->SetAttribute("src", src);
    node->SetAttribute("alt", alt);
    return node;
}

Element img(const std::string& src, const Attrs& attrs) {
    auto node = std::make_shared<Node>("img");
    node->SetAttribute("src", src);
    return apply_attrs(node, attrs);
}

Element video(const std::string& src, const Attrs& attrs) {
    auto node = std::make_shared<Node>("video");
    node->SetAttribute("src", src);
    return apply_attrs(node, attrs);
}

Element audio(const std::string& src, const Attrs& attrs) {
    auto node = std::make_shared<Node>("audio");
    node->SetAttribute("src", src);
    return apply_attrs(node, attrs);
}

Element canvas(const Attrs& attrs) {
    return apply_attrs(std::make_shared<Node>("canvas"), attrs);
}

Element video(Elements sources, const Attrs& attrs) {
    return apply_attrs(make_node("video", std::move(sources)), attrs);
}

Element audio(Elements sources, const Attrs& attrs) {
    return apply_attrs(make_node("audio", std::move(sources)), attrs);
}

Element source(const std::string& src, const std::string& type) {
    auto node = std::make_shared<Node>("source");
    node->SetAttribute("src", src);
    node->SetAttribute("type", type);
    return node;
}

Element picture(Elements sources, Element fallback_img) {
    sources.push_back(std::move(fallback_img));
    return make_node("picture", std::move(sources));
}

Element figure(Element content, const std::string& caption) {
    auto cap = make_text_node("figcaption", caption);
    return make_node("figure", {std::move(content), std::move(cap)});
}

Element figure(Elements children, const std::string& caption) {
    auto cap = make_text_node("figcaption", caption);
    children.push_back(std::move(cap));
    return make_node("figure", std::move(children));
}

Element iframe(const std::string& src, const Attrs& attrs) {
    auto node = std::make_shared<Node>("iframe");
    node->SetAttribute("src", src);
    return apply_attrs(node, attrs);
}

Element svg(const std::string& content, const Attrs& attrs) {
    auto node = std::make_shared<Node>("svg", content);
    node->SetRaw(true);
    return apply_attrs(node, attrs);
}

// --- Links ---

Element a(const std::string& content, const std::string& href,
          const std::string& target) {
    auto node = make_text_node("a", content);
    node->SetAttribute("href", href);
    node->SetAttribute("target", target);
    return node;
}

Element a(Element child, const std::string& href, const std::string& target) {
    auto node = std::make_shared<Node>("a", Elements{std::move(child)});
    node->SetAttribute("href", href);
    node->SetAttribute("target", target);
    return node;
}

// --- Semantic inline ---

Element strong(const std::string& content) {
    return make_text_node("strong", content);
}

Element em(const std::string& content) {
    return make_text_node("em", content);
}

Element mark(const std::string& content) {
    return make_text_node("mark", content);
}

Element small(const std::string& content) {
    return make_text_node("small", content);
}

Element sub(const std::string& content) {
    return make_text_node("sub", content);
}

Element sup(const std::string& content) {
    return make_text_node("sup", content);
}

Element br() {
    return std::make_shared<Node>("br");
}

Element hr() {
    return std::make_shared<Node>("hr");
}

// --- Raw HTML ---

Element raw(const std::string& html) {
    auto node = std::make_shared<Node>("", html);
    node->SetRaw(true);
    return node;
}

// --- Document structure ---

Element html_elem(Elements children, const Attrs& attrs) {
    auto node = make_node("html", std::move(children));
    node->SetAttribute("lang", "en");
    return apply_attrs(node, attrs);
}

Element head_elem(Elements children) {
    return make_node("head", std::move(children));
}

Element body_elem(Elements children, const Attrs& attrs) {
    return apply_attrs(make_node("body", std::move(children)), attrs);
}

Element title_elem(const std::string& text) {
    return make_text_node("title", text);
}

Element meta(const Attrs& attrs) {
    return apply_attrs(std::make_shared<Node>("meta"), attrs);
}

Element link_elem(const Attrs& attrs) {
    return apply_attrs(std::make_shared<Node>("link"), attrs);
}

Element script(const std::string& src) {
    auto node = std::make_shared<Node>("script");
    node->SetAttribute("src", src);
    return node;
}

Element script_inline(const std::string& code) {
    auto node = std::make_shared<Node>("script", code);
    node->SetRaw(true);
    return node;
}

Element style_elem(const std::string& css) {
    auto node = std::make_shared<Node>("style", css);
    node->SetRaw(true);
    return node;
}

Element document(const std::string& title,
                 Elements head_extra,
                 Elements body_children,
                 const Attrs& body_attrs) {
    // Build <head> children: charset meta + viewport meta + title + extras
    Elements head_children;
    head_children.push_back(meta({{"charset", "UTF-8"}}));
    head_children.push_back(meta({{"name", "viewport"},
                                   {"content", "width=device-width, initial-scale=1.0"}}));
    head_children.push_back(title_elem(title));
    for (auto& extra : head_extra) {
        head_children.push_back(std::move(extra));
    }

    return html_elem({
        head_elem(std::move(head_children)),
        body_elem(std::move(body_children), body_attrs),
    });
}

// --- File-based helpers ---

static std::string read_file_contents(const std::filesystem::path& path) {
    std::ifstream f(path);
    if (!f) return "";
    return {std::istreambuf_iterator<char>(f), {}};
}

Element stylesheet(const std::string& href) {
    return link_elem({{"rel", "stylesheet"}, {"href", href}});
}

Element stylesheet(const std::string& href, const Attrs& attrs) {
    auto node = stylesheet(href);
    for (const auto& [k, v] : attrs) {
        node->SetAttribute(k, v);
    }
    return node;
}

Element style_file(const std::filesystem::path& path) {
    return style_elem(read_file_contents(path));
}

Element script_file(const std::filesystem::path& path) {
    return script_inline(read_file_contents(path));
}

Element html_file(const std::filesystem::path& path) {
    return raw(read_file_contents(path));
}

Element google_font(const std::string& family) {
    // URL-encode spaces as +
    std::string encoded = family;
    for (auto& c : encoded) {
        if (c == ' ') c = '+';
    }
    auto url = fmt::format(
        "https://fonts.googleapis.com/css2?family={}&display=swap", encoded);
    return link_elem({{"rel", "stylesheet"}, {"href", url}});
}

// --- Interactive elements ---

Element details(Elements children, const std::string& summary_text) {
    Elements all;
    all.push_back(make_text_node("summary", summary_text));
    all.insert(all.end(), std::make_move_iterator(children.begin()),
               std::make_move_iterator(children.end()));
    return make_node("details", std::move(all));
}

Element details(Elements children, Element summary_elem) {
    Elements all;
    all.push_back(std::move(summary_elem));
    all.insert(all.end(), std::make_move_iterator(children.begin()),
               std::make_move_iterator(children.end()));
    return make_node("details", std::move(all));
}

Element summary(const std::string& content) {
    return make_text_node("summary", content);
}

Element dialog(Elements children, const Attrs& attrs) {
    return apply_attrs(make_node("dialog", std::move(children)), attrs);
}

Element template_elem(Elements children) {
    return make_node("template", std::move(children));
}

// --- Semantic elements ---

Element time_elem(const std::string& content, const std::string& datetime) {
    auto node = make_text_node("time", content);
    node->SetAttribute("datetime", datetime);
    return node;
}

Element abbr(const std::string& content, const std::string& title) {
    auto node = make_text_node("abbr", content);
    node->SetAttribute("title", title);
    return node;
}

Element progress(int value, int max) {
    auto node = std::make_shared<Node>("progress");
    node->SetAttribute("value", std::to_string(value));
    node->SetAttribute("max", std::to_string(max));
    return node;
}

Element meter(int value, int min, int max) {
    auto node = std::make_shared<Node>("meter");
    node->SetAttribute("value", std::to_string(value));
    node->SetAttribute("min", std::to_string(min));
    node->SetAttribute("max", std::to_string(max));
    return node;
}

// --- Data elements ---

Element datalist(const std::string& id, Elements options) {
    auto node = make_node("datalist", std::move(options));
    node->SetID(id);
    return node;
}

Element output_elem(const Attrs& attrs) {
    return apply_attrs(std::make_shared<Node>("output"), attrs);
}

// --- Legacy compat ---

Element separator() {
    auto node = hr();
    node->SetStyle("border", "1px solid #ccc");
    return node;
}

} // namespace nodex
