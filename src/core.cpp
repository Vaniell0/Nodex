#include "nodex/core.hpp"

#include <algorithm>
#include <sstream>

namespace nodex {

// --- Static data ---

static const std::set<std::string> kSelfClosingTags = {
    "area", "base", "br", "col", "embed", "hr", "img",
    "input", "link", "meta", "param", "source", "track", "wbr"
};

// --- Constructors ---

Node::Node(std::string tag) : tag_(std::move(tag)) {}

Node::Node(std::string tag, Elements children)
    : tag_(std::move(tag)), children_(std::move(children)) {}

Node::Node(std::string tag, const std::string& text_content)
    : tag_(std::move(tag)), text_content_(text_content) {}

// --- Tag ---

const std::string& Node::Tag() const { return tag_; }

Element Node::SetTag(const std::string& tag) {
    InvalidateCache();
    tag_ = tag;
    return shared_from_this();
}

// --- Text content ---

const std::string& Node::TextContent() const { return text_content_; }

Element Node::SetTextContent(const std::string& content) {
    InvalidateCache();
    text_content_ = content;
    return shared_from_this();
}

// --- Attributes ---

Element Node::SetAttribute(const std::string& key, const std::string& value) {
    InvalidateCache();
    attributes_[key] = value;
    return shared_from_this();
}

Element Node::RemoveAttribute(const std::string& key) {
    InvalidateCache();
    attributes_.erase(key);
    return shared_from_this();
}

std::string Node::GetAttribute(const std::string& key) const {
    auto it = attributes_.find(key);
    return it != attributes_.end() ? it->second : "";
}

bool Node::HasAttribute(const std::string& key) const {
    return attributes_.contains(key);
}

const Attrs& Node::Attributes() const { return attributes_; }

// --- ID ---

Element Node::SetID(const std::string& id) {
    return SetAttribute("id", id);
}

std::string Node::GetID() const {
    return GetAttribute("id");
}

// --- Classes ---

Element Node::SetClass(const std::string& cls) {
    InvalidateCache();
    classes_.clear();
    if (!cls.empty()) {
        std::istringstream iss(cls);
        std::string token;
        while (iss >> token) {
            classes_.push_back(std::move(token));
        }
    }
    return shared_from_this();
}

Element Node::AddClass(const std::string& cls) {
    if (!cls.empty() && !HasClass(cls)) {
        InvalidateCache();
        classes_.push_back(cls);
    }
    return shared_from_this();
}

Element Node::RemoveClass(const std::string& cls) {
    InvalidateCache();
    classes_.erase(
        std::remove(classes_.begin(), classes_.end(), cls),
        classes_.end()
    );
    return shared_from_this();
}

bool Node::HasClass(const std::string& cls) const {
    return std::find(classes_.begin(), classes_.end(), cls) != classes_.end();
}

std::string Node::ClassString() const {
    std::string result;
    for (size_t i = 0; i < classes_.size(); ++i) {
        if (i > 0) result += ' ';
        result += classes_[i];
    }
    return result;
}

const std::vector<std::string>& Node::Classes() const { return classes_; }

// --- Inline styles ---

Element Node::SetStyle(const std::string& property, const std::string& value) {
    InvalidateCache();
    styles_[property] = value;
    return shared_from_this();
}

Element Node::RemoveStyle(const std::string& property) {
    InvalidateCache();
    styles_.erase(property);
    return shared_from_this();
}

std::string Node::GetStyle(const std::string& property) const {
    auto it = styles_.find(property);
    return it != styles_.end() ? it->second : "";
}

Element Node::SetStyleString(const std::string& full_style) {
    InvalidateCache();
    // Merge, not replace — so chaining SetStyle() calls accumulates properties
    std::istringstream iss(full_style);
    std::string pair;
    while (std::getline(iss, pair, ';')) {
        auto colon = pair.find(':');
        if (colon == std::string::npos) continue;

        std::string key = pair.substr(0, colon);
        std::string val = pair.substr(colon + 1);

        // trim
        auto trim = [](std::string& s) {
            size_t start = s.find_first_not_of(" \t");
            size_t end   = s.find_last_not_of(" \t");
            s = (start == std::string::npos) ? "" : s.substr(start, end - start + 1);
        };
        trim(key);
        trim(val);

        if (!key.empty() && !val.empty()) {
            styles_[key] = val;
        }
    }
    return shared_from_this();
}

std::string Node::StyleString() const {
    std::string result;
    for (const auto& [prop, val] : styles_) {
        if (!result.empty()) result += ' ';
        result += prop + ": " + val + ";";
    }
    return result;
}

const std::map<std::string, std::string>& Node::Styles() const { return styles_; }

// --- Children ---

Element Node::AppendChild(Element child) {
    if (child) {
        InvalidateCache();
        child->parent_ = weak_from_this();
        children_.push_back(std::move(child));
    }
    return shared_from_this();
}

Element Node::PrependChild(Element child) {
    if (child) {
        InvalidateCache();
        child->parent_ = weak_from_this();
        children_.insert(children_.begin(), std::move(child));
    }
    return shared_from_this();
}

Element Node::RemoveChild(size_t index) {
    if (index < children_.size()) {
        InvalidateCache();
        children_.erase(children_.begin() + static_cast<ptrdiff_t>(index));
    }
    return shared_from_this();
}

Element Node::InsertChild(size_t index, Element child) {
    if (child) {
        InvalidateCache();
        child->parent_ = weak_from_this();
        if (index >= children_.size()) {
            children_.push_back(std::move(child));
        } else {
            children_.insert(children_.begin() + static_cast<ptrdiff_t>(index),
                             std::move(child));
        }
    }
    return shared_from_this();
}

const Elements& Node::Children() const { return children_; }

size_t Node::ChildCount() const { return children_.size(); }

// --- Parent ---

std::weak_ptr<Node> Node::Parent() const { return parent_; }

// --- Render cache ---

const std::string& Node::HtmlCache() const { return html_cache_; }

void Node::SetHtmlCache(std::string html) const { html_cache_ = std::move(html); }

void Node::InvalidateCache() {
    Node* node = this;
    while (node) {
        if (node->html_cache_.empty()) return;
        node->html_cache_.clear();
        if (auto p = node->parent_.lock())
            node = p.get();
        else
            return;
    }
}

// --- Self-closing ---

bool Node::IsSelfClosing() const {
    return kSelfClosingTags.contains(tag_);
}

// --- Clear ---

Element Node::ClearStyles() {
    InvalidateCache();
    styles_.clear();
    return shared_from_this();
}

Element Node::ClearClasses() {
    InvalidateCache();
    classes_.clear();
    return shared_from_this();
}

Element Node::ClearAttributes() {
    InvalidateCache();
    attributes_.clear();
    return shared_from_this();
}

// --- Deep copy ---

Element Node::Clone() const {
    auto copy = std::make_shared<Node>(tag_);
    copy->text_content_ = text_content_;
    copy->is_raw_ = is_raw_;
    copy->attributes_ = attributes_;
    copy->styles_ = styles_;
    copy->classes_ = classes_;
    for (const auto& child : children_) {
        if (child) copy->AppendChild(child->Clone());
    }
    return copy;
}

// --- Raw HTML ---

bool Node::IsRaw() const { return is_raw_; }

Element Node::SetRaw(bool raw) {
    InvalidateCache();
    is_raw_ = raw;
    return shared_from_this();
}

// --- EscapeHTML ---

std::string Node::EscapeHTML(const std::string& text) {
    size_t extra = 0;
    for (char c : text) {
        switch (c) {
            case '&':  extra += 4; break;
            case '<': case '>': extra += 3; break;
            case '"':  extra += 5; break;
            case '\'': extra += 4; break;
        }
    }
    if (extra == 0) return text;

    std::string out;
    out.reserve(text.size() + extra);
    for (char c : text) {
        switch (c) {
            case '&':  out += "&amp;";  break;
            case '<':  out += "&lt;";   break;
            case '>':  out += "&gt;";   break;
            case '"':  out += "&quot;"; break;
            case '\'': out += "&#39;";  break;
            default:   out += c;        break;
        }
    }
    return out;
}

// --- ToJSON ---

nlohmann::json Node::ToJSON() const {
    nlohmann::json j;

    if (!tag_.empty())          j["tag"]  = tag_;
    if (!text_content_.empty()) j["text"] = text_content_;
    if (is_raw_)                j["raw"]  = true;

    if (!attributes_.empty()) j["attrs"]   = attributes_;
    if (!styles_.empty())     j["styles"]  = styles_;
    if (!classes_.empty())    j["classes"] = classes_;

    if (!children_.empty()) {
        auto& arr = j["children"];
        arr = nlohmann::json::array();
        for (const auto& child : children_) {
            if (child) arr.push_back(child->ToJSON());
        }
    }

    return j;
}

// --- FromJSON ---

Element Node::FromJSON(const nlohmann::json& j) {
    auto node = std::make_shared<Node>(j.value("tag", ""));

    if (j.contains("text")) node->SetTextContent(j["text"].get<std::string>());
    if (j.contains("raw"))  node->SetRaw(j["raw"].get<bool>());
    if (j.contains("id"))   node->SetID(j["id"].get<std::string>());

    if (j.contains("attrs")) {
        for (auto& [k, v] : j["attrs"].items()) {
            node->SetAttribute(k, v.get<std::string>());
        }
    }
    if (j.contains("styles")) {
        for (auto& [k, v] : j["styles"].items()) {
            node->SetStyle(k, v.get<std::string>());
        }
    }
    if (j.contains("classes")) {
        for (const auto& cls : j["classes"]) {
            node->AddClass(cls.get<std::string>());
        }
    }
    if (j.contains("children")) {
        for (const auto& child_json : j["children"]) {
            node->AppendChild(FromJSON(child_json));
        }
    }

    return node;
}

} // namespace nodex
