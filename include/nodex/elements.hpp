#pragma once

#include "core.hpp"

#include <filesystem>

namespace nodex {

// --- Text elements ---
Element text(const std::string& content);
Element text(const std::string& content, const Attrs& attrs);
Element paragraph(const std::string& content);
Element paragraph(const std::string& content, const Attrs& attrs);
Element paragraph(Elements children);

inline Element p(const std::string& content) { return paragraph(content); }
inline Element p(const std::string& content, const Attrs& attrs) { return paragraph(content, attrs); }
inline Element p(Elements children) { return paragraph(std::move(children)); }

Element heading(int level, const std::string& content);
Element heading(int level, const std::string& content, const Attrs& attrs);
Element h1(const std::string& content);
Element h2(const std::string& content);
Element h3(const std::string& content);
Element h4(const std::string& content);
Element h5(const std::string& content);
Element h6(const std::string& content);
Element code(const std::string& content);
Element pre(const std::string& content);
Element blockquote(const std::string& content);
Element blockquote(Elements children);

// --- Containers ---
Element div(Elements children = {});
Element div(Elements children, const Attrs& attrs);
Element section(Elements children = {});
Element section(Elements children, const Attrs& attrs);
Element article(Elements children = {});
Element article(Elements children, const Attrs& attrs);
Element nav(Elements children = {});
Element nav(Elements children, const Attrs& attrs);
Element header(Elements children = {});
Element header(Elements children, const Attrs& attrs);
Element footer(Elements children = {});
Element footer(Elements children, const Attrs& attrs);
Element main_elem(Elements children = {});
Element main_elem(Elements children, const Attrs& attrs);
Element aside(Elements children = {});
Element aside(Elements children, const Attrs& attrs);
Element span(Elements children);
Element span(const std::string& content);
Element span(const std::string& content, const Attrs& attrs);

// --- Layout (FTXUI-style) ---
Element hbox(Elements children = {});
Element hbox(Elements children, const Attrs& attrs);
Element vbox(Elements children = {});
Element vbox(Elements children, const Attrs& attrs);
Element grid(Elements children, int columns);
Element grid(Elements children, int columns, const Attrs& attrs);

// --- Lists ---
Element ul(Elements items = {});
Element ul(Elements items, const Attrs& attrs);
Element ol(Elements items = {});
Element ol(Elements items, const Attrs& attrs);
Element li(const std::string& content);
Element li(Elements children);

// --- Tables ---
Element table(Elements rows = {});
Element table(Elements rows, const Attrs& attrs);
Element thead(Elements rows);
Element tbody(Elements rows);
Element tr(Elements cells);
Element th(const std::string& content);
Element th(Elements children);
Element td(const std::string& content);
Element td(Elements children);

// --- Forms ---
Element form(Elements children = {});
Element form(Elements children, const Attrs& attrs);
Element input(const std::string& type, const Attrs& attrs = {});
Element textarea(const std::string& content = "", const Attrs& attrs = {});
Element select(Elements options, const Attrs& attrs = {});
Element option(const std::string& label, const std::string& value);
Element button(const std::string& label, const Attrs& attrs = {});
Element label(const std::string& content, const Attrs& attrs = {});

// --- Media ---
Element img(const std::string& src, const std::string& alt = "");
Element img(const std::string& src, const Attrs& attrs);
Element video(const std::string& src, const Attrs& attrs = {});
Element video(Elements sources, const Attrs& attrs = {});
Element audio(const std::string& src, const Attrs& attrs = {});
Element audio(Elements sources, const Attrs& attrs = {});
Element canvas(const Attrs& attrs = {});
Element source(const std::string& src, const std::string& type);
Element picture(Elements sources, Element fallback_img);
Element figure(Element content, const std::string& caption);
Element figure(Elements children, const std::string& caption);
Element iframe(const std::string& src, const Attrs& attrs = {});
Element svg(const std::string& content, const Attrs& attrs = {});

// --- Links ---
Element a(const std::string& content, const std::string& href,
          const std::string& target = "_self");
Element a(Element child, const std::string& href,
          const std::string& target = "_self");

// --- Semantic inline ---
Element strong(const std::string& content);
Element em(const std::string& content);
Element mark(const std::string& content);
Element small(const std::string& content);
Element sub(const std::string& content);
Element sup(const std::string& content);
Element br();
Element hr();

// --- Raw HTML ---
Element raw(const std::string& html);

// --- Document structure ---
Element html_elem(Elements children, const Attrs& attrs = {});
Element head_elem(Elements children);
Element body_elem(Elements children, const Attrs& attrs = {});
Element title_elem(const std::string& text);
Element meta(const Attrs& attrs);
Element link_elem(const Attrs& attrs);
Element script(const std::string& src);
Element script_inline(const std::string& code);
Element style_elem(const std::string& css);

// Full HTML page: <!DOCTYPE html>\n<html>...<head>...<body>...
Element document(const std::string& title,
                 Elements head_extra,
                 Elements body_children,
                 const Attrs& body_attrs = {});

// --- File-based helpers ---

// <link rel="stylesheet" href="...">
Element stylesheet(const std::string& href);

// <link rel="stylesheet" href="..."> with extra attrs (media, crossorigin, etc.)
Element stylesheet(const std::string& href, const Attrs& attrs);

// <style>...contents of file...</style>  (inline CSS from file path)
Element style_file(const std::filesystem::path& path);

// <script>...contents of file...</script>  (inline JS from file path)
Element script_file(const std::filesystem::path& path);

// Reads file and returns raw() — for loading HTML fragments from disk
Element html_file(const std::filesystem::path& path);

// Google Fonts shortcut: <link href="https://fonts.googleapis.com/css2?family=..." rel="stylesheet">
Element google_font(const std::string& family);

// --- Interactive elements ---
Element details(Elements children, const std::string& summary_text);
Element details(Elements children, Element summary_elem);
Element summary(const std::string& content);
Element dialog(Elements children, const Attrs& attrs = {});
Element template_elem(Elements children);

// --- Semantic elements ---
Element time_elem(const std::string& content, const std::string& datetime);
Element abbr(const std::string& content, const std::string& title);
Element progress(int value, int max = 100);
Element meter(int value, int min = 0, int max = 100);

// --- Data elements ---
Element datalist(const std::string& id, Elements options);
Element output_elem(const Attrs& attrs = {});

// --- Legacy compat ---
Element separator();

} // namespace nodex
