#include "nodex/decorators.hpp"

namespace nodex {

// --- Pipe operators ---

Element operator|(Element element, const Decorator& decorator) {
    return decorator(std::move(element));
}

Element& operator|=(Element& element, const Decorator& decorator) {
    element = decorator(std::move(element));
    return element;
}

Elements operator|(Elements elements, const Decorator& decorator) {
    for (auto& elem : elements) {
        elem = decorator(std::move(elem));
    }
    return elements;
}

Decorator operator|(const Decorator& d1, const Decorator& d2) {
    return {[d1, d2](Element elem) -> Element {
        return d2(d1(std::move(elem)));
    }};
}

// --- Text style decorators ---

Decorator Bold() {
    return {[](Element elem) -> Element {
        elem->SetStyle("font-weight", "bold");
        return elem;
    }};
}

Decorator Italic() {
    return {[](Element elem) -> Element {
        elem->SetStyle("font-style", "italic");
        return elem;
    }};
}

Decorator Underline() {
    return {[](Element elem) -> Element {
        elem->SetStyle("text-decoration", "underline");
        return elem;
    }};
}

Decorator Strikethrough() {
    return {[](Element elem) -> Element {
        elem->SetStyle("text-decoration", "line-through");
        return elem;
    }};
}

Decorator Dim() {
    return {[](Element elem) -> Element {
        elem->SetStyle("opacity", "0.5");
        return elem;
    }};
}

Decorator Color(const std::string& color) {
    return {[color](Element elem) -> Element {
        elem->SetStyle("color", color);
        return elem;
    }};
}

Decorator BgColor(const std::string& color) {
    return {[color](Element elem) -> Element {
        elem->SetStyle("background-color", color);
        return elem;
    }};
}

Decorator FontSize(const std::string& size) {
    return {[size](Element elem) -> Element {
        elem->SetStyle("font-size", size);
        return elem;
    }};
}

Decorator FontSize(int px) {
    return FontSize(fmt::format("{}px", px));
}

Decorator FontFamily(const std::string& family) {
    return {[family](Element elem) -> Element {
        elem->SetStyle("font-family", family);
        return elem;
    }};
}

Decorator Opacity(float value) {
    return {[value](Element elem) -> Element {
        elem->SetStyle("opacity", fmt::format("{:.2f}", value));
        return elem;
    }};
}

Decorator Width(const std::string& w) {
    return {[w](Element elem) -> Element {
        elem->SetStyle("width", w);
        return elem;
    }};
}

Decorator Height(const std::string& h) {
    return {[h](Element elem) -> Element {
        elem->SetStyle("height", h);
        return elem;
    }};
}

Decorator FlexGrow(int value) {
    return {[value](Element elem) -> Element {
        elem->SetStyle("flex-grow", std::to_string(value));
        return elem;
    }};
}

// --- Alignment decorators ---

Decorator Center() {
    return {[](Element elem) -> Element {
        elem->SetStyle("display", "flex");
        elem->SetStyle("justify-content", "center");
        elem->SetStyle("align-items", "center");
        return elem;
    }};
}

Decorator AlignLeft() {
    return {[](Element elem) -> Element {
        elem->SetStyle("text-align", "left");
        return elem;
    }};
}

Decorator AlignCenter() {
    return {[](Element elem) -> Element {
        elem->SetStyle("text-align", "center");
        return elem;
    }};
}

Decorator AlignRight() {
    return {[](Element elem) -> Element {
        elem->SetStyle("text-align", "right");
        return elem;
    }};
}

Decorator AlignTop() {
    return {[](Element elem) -> Element {
        elem->SetStyle("vertical-align", "top");
        return elem;
    }};
}

Decorator AlignMiddle() {
    return {[](Element elem) -> Element {
        elem->SetStyle("vertical-align", "middle");
        return elem;
    }};
}

Decorator AlignBottom() {
    return {[](Element elem) -> Element {
        elem->SetStyle("vertical-align", "bottom");
        return elem;
    }};
}

// --- Box model decorators ---

Decorator Margin(int all) {
    return {[all](Element elem) -> Element {
        elem->SetStyle("margin", fmt::format("{}px", all));
        return elem;
    }};
}

Decorator Margin(int vertical, int horizontal) {
    return {[vertical, horizontal](Element elem) -> Element {
        elem->SetStyle("margin", fmt::format("{}px {}px", vertical, horizontal));
        return elem;
    }};
}

Decorator Margin(int top, int right, int bottom, int left) {
    return {[top, right, bottom, left](Element elem) -> Element {
        elem->SetStyle("margin",
            fmt::format("{}px {}px {}px {}px", top, right, bottom, left));
        return elem;
    }};
}

Decorator Padding(int all) {
    return {[all](Element elem) -> Element {
        elem->SetStyle("padding", fmt::format("{}px", all));
        return elem;
    }};
}

Decorator Padding(int vertical, int horizontal) {
    return {[vertical, horizontal](Element elem) -> Element {
        elem->SetStyle("padding", fmt::format("{}px {}px", vertical, horizontal));
        return elem;
    }};
}

Decorator Padding(int top, int right, int bottom, int left) {
    return {[top, right, bottom, left](Element elem) -> Element {
        elem->SetStyle("padding",
            fmt::format("{}px {}px {}px {}px", top, right, bottom, left));
        return elem;
    }};
}

Decorator Border(int thickness, const std::string& color,
                 const std::string& style) {
    return {[thickness, color, style](Element elem) -> Element {
        elem->SetStyle("border",
            fmt::format("{}px {} {}", thickness, style, color));
        return elem;
    }};
}

Decorator BorderRadius(const std::string& radius) {
    return {[radius](Element elem) -> Element {
        elem->SetStyle("border-radius", radius);
        return elem;
    }};
}

Decorator BorderRadius(int px) {
    return BorderRadius(fmt::format("{}px", px));
}

// --- Structural decorators ---

Decorator Hyperlink(const std::string& url, const std::string& target) {
    return {[url, target](Element elem) -> Element {
        auto anchor = std::make_shared<Node>("a");
        anchor->SetAttribute("href", url);
        anchor->SetAttribute("target", target);
        anchor->AppendChild(std::move(elem));
        return anchor;
    }};
}

// --- Attribute decorators ---

Decorator SetAttr(const std::string& key, const std::string& value) {
    return {[key, value](Element elem) -> Element {
        elem->SetAttribute(key, value);
        return elem;
    }};
}

Decorator SetStyle(const std::string& style_string) {
    return {[style_string](Element elem) -> Element {
        elem->SetStyleString(style_string);
        return elem;
    }};
}

Decorator SetClass(const std::string& cls) {
    return {[cls](Element elem) -> Element {
        elem->SetClass(cls);
        return elem;
    }};
}

Decorator AddClass(const std::string& cls) {
    return {[cls](Element elem) -> Element {
        elem->AddClass(cls);
        return elem;
    }};
}

Decorator SetID(const std::string& id) {
    return {[id](Element elem) -> Element {
        elem->SetID(id);
        return elem;
    }};
}

// --- Visual effect decorators ---

Decorator Transform(const std::string& transform) {
    return {[transform](Element elem) -> Element {
        elem->SetStyle("transform", transform);
        return elem;
    }};
}

Decorator BoxShadow(const std::string& shadow) {
    return {[shadow](Element elem) -> Element {
        elem->SetStyle("box-shadow", shadow);
        return elem;
    }};
}

Decorator TextShadow(const std::string& shadow) {
    return {[shadow](Element elem) -> Element {
        elem->SetStyle("text-shadow", shadow);
        return elem;
    }};
}

Decorator Filter(const std::string& filter) {
    return {[filter](Element elem) -> Element {
        elem->SetStyle("filter", filter);
        return elem;
    }};
}

Decorator BackdropFilter(const std::string& filter) {
    return {[filter](Element elem) -> Element {
        elem->SetStyle("backdrop-filter", filter);
        return elem;
    }};
}

Decorator Transition(const std::string& property,
                     const std::string& duration,
                     const std::string& easing) {
    return {[property, duration, easing](Element elem) -> Element {
        elem->SetStyle("transition",
            fmt::format("{} {} {}", property, duration, easing));
        return elem;
    }};
}

Decorator TransitionAll(const std::string& duration,
                        const std::string& easing) {
    return Transition("all", duration, easing);
}

// --- Positioning decorators ---

Decorator Position(const std::string& pos) {
    return {[pos](Element elem) -> Element {
        elem->SetStyle("position", pos);
        return elem;
    }};
}

Decorator ZIndex(int z) {
    return {[z](Element elem) -> Element {
        elem->SetStyle("z-index", std::to_string(z));
        return elem;
    }};
}

Decorator Top(const std::string& val) {
    return {[val](Element elem) -> Element {
        elem->SetStyle("top", val);
        return elem;
    }};
}

Decorator Right(const std::string& val) {
    return {[val](Element elem) -> Element {
        elem->SetStyle("right", val);
        return elem;
    }};
}

Decorator Bottom(const std::string& val) {
    return {[val](Element elem) -> Element {
        elem->SetStyle("bottom", val);
        return elem;
    }};
}

Decorator Left(const std::string& val) {
    return {[val](Element elem) -> Element {
        elem->SetStyle("left", val);
        return elem;
    }};
}

Decorator Inset(const std::string& val) {
    return {[val](Element elem) -> Element {
        elem->SetStyle("inset", val);
        return elem;
    }};
}

Decorator Overflow(const std::string& overflow) {
    return {[overflow](Element elem) -> Element {
        elem->SetStyle("overflow", overflow);
        return elem;
    }};
}

Decorator OverflowX(const std::string& overflow) {
    return {[overflow](Element elem) -> Element {
        elem->SetStyle("overflow-x", overflow);
        return elem;
    }};
}

Decorator OverflowY(const std::string& overflow) {
    return {[overflow](Element elem) -> Element {
        elem->SetStyle("overflow-y", overflow);
        return elem;
    }};
}

// --- Extended layout decorators ---

Decorator Gap(const std::string& gap) {
    return {[gap](Element elem) -> Element {
        elem->SetStyle("gap", gap);
        return elem;
    }};
}

Decorator Gap(int px) {
    return Gap(fmt::format("{}px", px));
}

Decorator RowGap(const std::string& gap) {
    return {[gap](Element elem) -> Element {
        elem->SetStyle("row-gap", gap);
        return elem;
    }};
}

Decorator ColumnGap(const std::string& gap) {
    return {[gap](Element elem) -> Element {
        elem->SetStyle("column-gap", gap);
        return elem;
    }};
}

Decorator JustifyContent(const std::string& jc) {
    return {[jc](Element elem) -> Element {
        elem->SetStyle("justify-content", jc);
        return elem;
    }};
}

Decorator AlignItems(const std::string& ai) {
    return {[ai](Element elem) -> Element {
        elem->SetStyle("align-items", ai);
        return elem;
    }};
}

Decorator AlignSelf(const std::string& as) {
    return {[as](Element elem) -> Element {
        elem->SetStyle("align-self", as);
        return elem;
    }};
}

Decorator FlexWrap(const std::string& wrap) {
    return {[wrap](Element elem) -> Element {
        elem->SetStyle("flex-wrap", wrap);
        return elem;
    }};
}

Decorator FlexShrink(int value) {
    return {[value](Element elem) -> Element {
        elem->SetStyle("flex-shrink", std::to_string(value));
        return elem;
    }};
}

Decorator FlexBasis(const std::string& basis) {
    return {[basis](Element elem) -> Element {
        elem->SetStyle("flex-basis", basis);
        return elem;
    }};
}

Decorator GridColumn(const std::string& col) {
    return {[col](Element elem) -> Element {
        elem->SetStyle("grid-column", col);
        return elem;
    }};
}

Decorator GridRow(const std::string& row) {
    return {[row](Element elem) -> Element {
        elem->SetStyle("grid-row", row);
        return elem;
    }};
}

// --- Interaction decorators ---

Decorator Cursor(const std::string& cursor) {
    return {[cursor](Element elem) -> Element {
        elem->SetStyle("cursor", cursor);
        return elem;
    }};
}

Decorator UserSelect(const std::string& select) {
    return {[select](Element elem) -> Element {
        elem->SetStyle("user-select", select);
        return elem;
    }};
}

Decorator PointerEvents(const std::string& pe) {
    return {[pe](Element elem) -> Element {
        elem->SetStyle("pointer-events", pe);
        return elem;
    }};
}

// --- CSS custom properties ---

Decorator CSSVar(const std::string& name, const std::string& value) {
    return {[name, value](Element elem) -> Element {
        auto prop = name.substr(0, 2) == "--" ? name : "--" + name;
        elem->SetStyle(prop, value);
        return elem;
    }};
}

// --- Data attributes ---

Decorator Data(const std::string& key, const std::string& value) {
    return SetAttr("data-" + key, value);
}

// --- Display ---

Decorator Display(const std::string& display) {
    return {[display](Element elem) -> Element {
        elem->SetStyle("display", display);
        return elem;
    }};
}

Decorator Visibility(const std::string& vis) {
    return {[vis](Element elem) -> Element {
        elem->SetStyle("visibility", vis);
        return elem;
    }};
}

// --- Typography extras ---

Decorator LetterSpacing(const std::string& spacing) {
    return {[spacing](Element elem) -> Element {
        elem->SetStyle("letter-spacing", spacing);
        return elem;
    }};
}

Decorator LineHeight(const std::string& height) {
    return {[height](Element elem) -> Element {
        elem->SetStyle("line-height", height);
        return elem;
    }};
}

Decorator TextTransform(const std::string& transform) {
    return {[transform](Element elem) -> Element {
        elem->SetStyle("text-transform", transform);
        return elem;
    }};
}

Decorator WordBreak(const std::string& wb) {
    return {[wb](Element elem) -> Element {
        elem->SetStyle("word-break", wb);
        return elem;
    }};
}

Decorator WhiteSpace(const std::string& ws) {
    return {[ws](Element elem) -> Element {
        elem->SetStyle("white-space", ws);
        return elem;
    }};
}

// --- Sizing extras ---

Decorator MinWidth(const std::string& w) {
    return {[w](Element elem) -> Element {
        elem->SetStyle("min-width", w);
        return elem;
    }};
}

Decorator MaxWidth(const std::string& w) {
    return {[w](Element elem) -> Element {
        elem->SetStyle("max-width", w);
        return elem;
    }};
}

Decorator MinHeight(const std::string& h) {
    return {[h](Element elem) -> Element {
        elem->SetStyle("min-height", h);
        return elem;
    }};
}

Decorator MaxHeight(const std::string& h) {
    return {[h](Element elem) -> Element {
        elem->SetStyle("max-height", h);
        return elem;
    }};
}

// --- HTMX attribute decorators ---

Decorator HxGet(const std::string& url) {
    return SetAttr("hx-get", url);
}

Decorator HxPost(const std::string& url) {
    return SetAttr("hx-post", url);
}

Decorator HxPut(const std::string& url) {
    return SetAttr("hx-put", url);
}

Decorator HxPatch(const std::string& url) {
    return SetAttr("hx-patch", url);
}

Decorator HxDelete(const std::string& url) {
    return SetAttr("hx-delete", url);
}

Decorator HxTarget(const std::string& selector) {
    return SetAttr("hx-target", selector);
}

Decorator HxSwap(const std::string& strategy) {
    return SetAttr("hx-swap", strategy);
}

Decorator HxTrigger(const std::string& trigger) {
    return SetAttr("hx-trigger", trigger);
}

Decorator HxPushUrl(const std::string& url) {
    return SetAttr("hx-push-url", url);
}

Decorator HxSelect(const std::string& selector) {
    return SetAttr("hx-select", selector);
}

Decorator HxVals(const std::string& json_string) {
    return SetAttr("hx-vals", json_string);
}

Decorator HxConfirm(const std::string& message) {
    return SetAttr("hx-confirm", message);
}

Decorator HxIndicator(const std::string& selector) {
    return SetAttr("hx-indicator", selector);
}

Decorator HxBoost(bool enable) {
    return SetAttr("hx-boost", enable ? "true" : "false");
}

// --- Additional decorators ---

Decorator AspectRatio(const std::string& ratio) {
    return Decorator([ratio](Element e) {
        e->SetStyle("aspect-ratio", ratio);
        return e;
    });
}

Decorator ObjectFit(const std::string& fit) {
    return Decorator([fit](Element e) {
        e->SetStyle("object-fit", fit);
        return e;
    });
}

Decorator TextOverflow(const std::string& overflow) {
    return Decorator([overflow](Element e) {
        e->SetStyle("text-overflow", overflow);
        e->SetStyle("overflow", "hidden");
        e->SetStyle("white-space", "nowrap");
        return e;
    });
}

Decorator Gradient(const std::string& gradient) {
    return Decorator([gradient](Element e) {
        e->SetStyle("background", gradient);
        return e;
    });
}

Decorator Outline(int thickness, const std::string& color,
                  const std::string& style) {
    return Decorator([=](Element e) {
        e->SetStyle("outline",
                     fmt::format("{}px {} {}", thickness, style, color));
        return e;
    });
}

Decorator OutlineOffset(const std::string& offset) {
    return Decorator([offset](Element e) {
        e->SetStyle("outline-offset", offset);
        return e;
    });
}

Decorator Resize(const std::string& resize) {
    return Decorator([resize](Element e) {
        e->SetStyle("resize", resize);
        return e;
    });
}

Decorator ScrollBehavior(const std::string& behavior) {
    return Decorator([behavior](Element e) {
        e->SetStyle("scroll-behavior", behavior);
        return e;
    });
}

} // namespace nodex
