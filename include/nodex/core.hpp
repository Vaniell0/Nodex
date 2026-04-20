#pragma once

#include <algorithm>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include <fmt/core.h>
#include <nlohmann/json.hpp>

namespace nodex {

class Node;
using Element  = std::shared_ptr<Node>;
using Elements = std::vector<Element>;
using Attrs    = std::map<std::string, std::string>;

class Node : public std::enable_shared_from_this<Node> {
public:
    explicit Node(std::string tag);
    Node(std::string tag, Elements children);
    Node(std::string tag, const std::string& text_content);
    virtual ~Node() = default;

    // --- Tag ---
    const std::string& Tag() const;
    Element SetTag(const std::string& tag);

    // --- Text content (for leaf nodes) ---
    const std::string& TextContent() const;
    Element SetTextContent(const std::string& content);

    // --- Attributes ---
    Element SetAttribute(const std::string& key, const std::string& value);
    Element RemoveAttribute(const std::string& key);
    std::string GetAttribute(const std::string& key) const;
    bool HasAttribute(const std::string& key) const;
    const Attrs& Attributes() const;

    // --- ID ---
    Element SetID(const std::string& id);
    std::string GetID() const;

    // --- Classes ---
    Element SetClass(const std::string& cls);
    Element AddClass(const std::string& cls);
    Element RemoveClass(const std::string& cls);
    bool HasClass(const std::string& cls) const;
    std::string ClassString() const;
    const std::vector<std::string>& Classes() const;

    // --- Inline styles ---
    Element SetStyle(const std::string& property, const std::string& value);
    Element RemoveStyle(const std::string& property);
    std::string GetStyle(const std::string& property) const;
    Element SetStyleString(const std::string& full_style);
    std::string StyleString() const;
    const std::map<std::string, std::string>& Styles() const;

    // --- Children ---
    Element AppendChild(Element child);
    Element PrependChild(Element child);
    Element RemoveChild(size_t index);
    Element InsertChild(size_t index, Element child);
    const Elements& Children() const;
    size_t ChildCount() const;

    // --- Parent ---
    std::weak_ptr<Node> Parent() const;

    // --- Render cache ---
    const std::string& HtmlCache() const;
    void SetHtmlCache(std::string html) const;
    void InvalidateCache();

    // --- Self-closing ---
    bool IsSelfClosing() const;

    // --- Clear ---
    Element ClearStyles();
    Element ClearClasses();
    Element ClearAttributes();

    // --- Deep copy ---
    Element Clone() const;

    // --- Raw HTML ---
    bool IsRaw() const;
    Element SetRaw(bool raw);

    // --- Utilities ---
    static std::string EscapeHTML(const std::string& text);

    // --- Serialization ---
    nlohmann::json ToJSON() const;
    static Element FromJSON(const nlohmann::json& j);

protected:
    std::string tag_;
    std::string text_content_;
    bool        is_raw_ = false;

    Attrs                              attributes_;
    std::map<std::string, std::string> styles_;
    std::vector<std::string>           classes_;

    Elements            children_;
    std::weak_ptr<Node> parent_;
    mutable std::string html_cache_;
};

} // namespace nodex
