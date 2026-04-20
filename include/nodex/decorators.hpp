#pragma once

#include "core.hpp"

#include <functional>
#include <string>

namespace nodex {

struct Decorator {
    std::function<Element(Element)> apply;

    Decorator(std::function<Element(Element)> func)
        : apply(std::move(func)) {}

    Element operator()(Element elem) const {
        return apply(std::move(elem));
    }
};

// --- Pipe operators ---
Element   operator|(Element element, const Decorator& decorator);
Element&  operator|=(Element& element, const Decorator& decorator);
Elements  operator|(Elements elements, const Decorator& decorator);
Decorator operator|(const Decorator& d1, const Decorator& d2);

// --- Text style decorators (in-place, no wrapping) ---
Decorator Bold();
Decorator Italic();
Decorator Underline();
Decorator Strikethrough();
Decorator Dim();
Decorator Color(const std::string& color);
Decorator BgColor(const std::string& color);
Decorator FontSize(const std::string& size);
Decorator FontSize(int px);
Decorator FontFamily(const std::string& family);
Decorator Opacity(float value);
Decorator Width(const std::string& w);
Decorator Height(const std::string& h);
Decorator FlexGrow(int value = 1);

// --- Alignment decorators (in-place) ---
Decorator Center();
Decorator AlignLeft();
Decorator AlignCenter();
Decorator AlignRight();
Decorator AlignTop();
Decorator AlignMiddle();
Decorator AlignBottom();

// --- Box model decorators (in-place) ---
Decorator Margin(int all);
Decorator Margin(int vertical, int horizontal);
Decorator Margin(int top, int right, int bottom, int left);
Decorator Padding(int all);
Decorator Padding(int vertical, int horizontal);
Decorator Padding(int top, int right, int bottom, int left);
Decorator Border(int thickness = 1, const std::string& color = "black",
                 const std::string& style = "solid");
Decorator BorderRadius(const std::string& radius);
Decorator BorderRadius(int px);

// --- Structural decorators (wraps in new node) ---
Decorator Hyperlink(const std::string& url, const std::string& target = "_blank");

// --- Attribute decorators ---
Decorator SetAttr(const std::string& key, const std::string& value);
Decorator SetStyle(const std::string& style_string);
Decorator SetClass(const std::string& cls);
Decorator AddClass(const std::string& cls);
Decorator SetID(const std::string& id);

// --- Visual effect decorators ---
Decorator Transform(const std::string& transform);
Decorator BoxShadow(const std::string& shadow);
Decorator TextShadow(const std::string& shadow);
Decorator Filter(const std::string& filter);
Decorator BackdropFilter(const std::string& filter);
Decorator Transition(const std::string& property,
                     const std::string& duration = "0.3s",
                     const std::string& easing = "ease");
Decorator TransitionAll(const std::string& duration = "0.3s",
                        const std::string& easing = "ease");

// --- Positioning decorators ---
Decorator Position(const std::string& pos);
Decorator ZIndex(int z);
Decorator Top(const std::string& val);
Decorator Right(const std::string& val);
Decorator Bottom(const std::string& val);
Decorator Left(const std::string& val);
Decorator Inset(const std::string& val);
Decorator Overflow(const std::string& overflow);
Decorator OverflowX(const std::string& overflow);
Decorator OverflowY(const std::string& overflow);

// --- Extended layout decorators ---
Decorator Gap(const std::string& gap);
Decorator Gap(int px);
Decorator RowGap(const std::string& gap);
Decorator ColumnGap(const std::string& gap);
Decorator JustifyContent(const std::string& jc);
Decorator AlignItems(const std::string& ai);
Decorator AlignSelf(const std::string& as);
Decorator FlexWrap(const std::string& wrap = "wrap");
Decorator FlexShrink(int value);
Decorator FlexBasis(const std::string& basis);
Decorator GridColumn(const std::string& col);
Decorator GridRow(const std::string& row);

// --- Interaction decorators ---
Decorator Cursor(const std::string& cursor);
Decorator UserSelect(const std::string& select);
Decorator PointerEvents(const std::string& pe);

// --- CSS custom properties ---
Decorator CSSVar(const std::string& name, const std::string& value);

// --- Data attributes ---
Decorator Data(const std::string& key, const std::string& value);

// --- Display ---
Decorator Display(const std::string& display);
Decorator Visibility(const std::string& vis);

// --- Typography extras ---
Decorator LetterSpacing(const std::string& spacing);
Decorator LineHeight(const std::string& height);
Decorator TextTransform(const std::string& transform);
Decorator WordBreak(const std::string& wb);
Decorator WhiteSpace(const std::string& ws);

// --- Sizing extras ---
Decorator MinWidth(const std::string& w);
Decorator MaxWidth(const std::string& w);
Decorator MinHeight(const std::string& h);
Decorator MaxHeight(const std::string& h);

// --- HTMX attribute decorators ---
Decorator HxGet(const std::string& url);
Decorator HxPost(const std::string& url);
Decorator HxPut(const std::string& url);
Decorator HxPatch(const std::string& url);
Decorator HxDelete(const std::string& url);
Decorator HxTarget(const std::string& selector);
Decorator HxSwap(const std::string& strategy);
Decorator HxTrigger(const std::string& trigger);
Decorator HxPushUrl(const std::string& url = "true");
Decorator HxSelect(const std::string& selector);
Decorator HxVals(const std::string& json_string);
Decorator HxConfirm(const std::string& message);
Decorator HxIndicator(const std::string& selector);
Decorator HxBoost(bool enable = true);

// --- Additional decorators ---
Decorator AspectRatio(const std::string& ratio);
Decorator ObjectFit(const std::string& fit);
Decorator TextOverflow(const std::string& overflow = "ellipsis");
Decorator Gradient(const std::string& gradient);
Decorator Outline(int thickness = 1, const std::string& color = "black",
                  const std::string& style = "solid");
Decorator OutlineOffset(const std::string& offset);
Decorator Resize(const std::string& resize = "both");
Decorator ScrollBehavior(const std::string& behavior = "smooth");

} // namespace nodex
