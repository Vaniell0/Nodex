#include <catch2/catch_test_macros.hpp>
#include <nodex/nodex.hpp>

using namespace nodex;

TEST_CASE("Text style decorators") {
    auto el = div({});

    SECTION("Bold") {
        el = el | Bold();
        REQUIRE(el->GetStyle("font-weight") == "bold");
    }

    SECTION("Italic") {
        el = el | Italic();
        REQUIRE(el->GetStyle("font-style") == "italic");
    }

    SECTION("Underline") {
        el = el | Underline();
        REQUIRE(el->GetStyle("text-decoration") == "underline");
    }

    SECTION("Color") {
        el = el | Color("red");
        REQUIRE(el->GetStyle("color") == "red");
    }

    SECTION("BgColor") {
        el = el | BgColor("#fff");
        REQUIRE(el->GetStyle("background-color") == "#fff");
    }

    SECTION("FontSize string") {
        el = el | FontSize("1.5rem");
        REQUIRE(el->GetStyle("font-size") == "1.5rem");
    }

    SECTION("FontSize int") {
        el = el | FontSize(14);
        REQUIRE(el->GetStyle("font-size") == "14px");
    }

    SECTION("Opacity") {
        el = el | Opacity(0.5f);
        auto val = el->GetStyle("opacity");
        REQUIRE(val.find("0.5") != std::string::npos);
    }
}

TEST_CASE("Box model decorators") {
    auto el = div({});

    SECTION("Padding single") {
        el = el | Padding(10);
        REQUIRE(el->GetStyle("padding") == "10px");
    }

    SECTION("Padding two args") {
        el = el | Padding(10, 20);
        REQUIRE(el->GetStyle("padding") == "10px 20px");
    }

    SECTION("Padding four args") {
        el = el | Padding(1, 2, 3, 4);
        REQUIRE(el->GetStyle("padding") == "1px 2px 3px 4px");
    }

    SECTION("Margin") {
        el = el | Margin(5);
        REQUIRE(el->GetStyle("margin") == "5px");
    }

    SECTION("Border") {
        el = el | Border(2, "blue", "dashed");
        REQUIRE(el->GetStyle("border") == "2px dashed blue");
    }

    SECTION("BorderRadius string") {
        el = el | BorderRadius("50%");
        REQUIRE(el->GetStyle("border-radius") == "50%");
    }

    SECTION("BorderRadius int") {
        el = el | BorderRadius(8);
        REQUIRE(el->GetStyle("border-radius") == "8px");
    }
}

TEST_CASE("Alignment decorators") {
    SECTION("Center") {
        auto el = div({}) | Center();
        REQUIRE(el->GetStyle("display") == "flex");
        REQUIRE(el->GetStyle("justify-content") == "center");
        REQUIRE(el->GetStyle("align-items") == "center");
    }

    SECTION("AlignLeft") {
        auto el = div({}) | AlignLeft();
        REQUIRE(el->GetStyle("text-align") == "left");
    }

    SECTION("AlignCenter") {
        auto el = div({}) | AlignCenter();
        REQUIRE(el->GetStyle("text-align") == "center");
    }
}

TEST_CASE("Sizing decorators") {
    auto el = div({});

    SECTION("Width and Height") {
        el = el | Width("100%") | Height("50vh");
        REQUIRE(el->GetStyle("width") == "100%");
        REQUIRE(el->GetStyle("height") == "50vh");
    }

    SECTION("MinWidth MaxWidth") {
        el = el | MinWidth("200px") | MaxWidth("800px");
        REQUIRE(el->GetStyle("min-width") == "200px");
        REQUIRE(el->GetStyle("max-width") == "800px");
    }
}

TEST_CASE("Pipe operator composition") {
    SECTION("element | decorator") {
        auto el = div({}) | Bold() | Color("red");
        REQUIRE(el->GetStyle("font-weight") == "bold");
        REQUIRE(el->GetStyle("color") == "red");
    }

    SECTION("decorator | decorator composition") {
        auto style = Bold() | Color("blue") | Padding(10);
        auto el = div({}) | style;
        REQUIRE(el->GetStyle("font-weight") == "bold");
        REQUIRE(el->GetStyle("color") == "blue");
        REQUIRE(el->GetStyle("padding") == "10px");
    }

    SECTION("elements | decorator") {
        Elements elems = {div({}), span("text")};
        auto styled = elems | Color("green");
        REQUIRE(styled[0]->GetStyle("color") == "green");
        REQUIRE(styled[1]->GetStyle("color") == "green");
    }
}

TEST_CASE("Attribute decorators") {
    auto el = div({});

    SECTION("SetAttr") {
        el = el | SetAttr("data-id", "123");
        REQUIRE(el->GetAttribute("data-id") == "123");
    }

    SECTION("AddClass") {
        el = el | AddClass("active");
        REQUIRE(el->HasClass("active"));
    }

    SECTION("SetID") {
        el = el | SetID("main");
        REQUIRE(el->GetID() == "main");
    }

    SECTION("Data") {
        el = el | Data("value", "42");
        REQUIRE(el->GetAttribute("data-value") == "42");
    }
}

TEST_CASE("HTMX decorators") {
    auto el = div({});

    SECTION("HxGet") {
        el = el | HxGet("/api/data");
        REQUIRE(el->GetAttribute("hx-get") == "/api/data");
    }

    SECTION("HxPost") {
        el = el | HxPost("/api/submit");
        REQUIRE(el->GetAttribute("hx-post") == "/api/submit");
    }

    SECTION("HxTarget") {
        el = el | HxTarget("#result");
        REQUIRE(el->GetAttribute("hx-target") == "#result");
    }

    SECTION("HxSwap") {
        el = el | HxSwap("outerHTML");
        REQUIRE(el->GetAttribute("hx-swap") == "outerHTML");
    }

    SECTION("HxBoost") {
        el = el | HxBoost();
        REQUIRE(el->GetAttribute("hx-boost") == "true");
    }
}

TEST_CASE("New decorators") {
    auto el = div({});

    SECTION("AspectRatio") {
        el = el | AspectRatio("16/9");
        REQUIRE(el->GetStyle("aspect-ratio") == "16/9");
    }

    SECTION("ObjectFit") {
        el = el | ObjectFit("cover");
        REQUIRE(el->GetStyle("object-fit") == "cover");
    }

    SECTION("TextOverflow") {
        el = el | TextOverflow();
        REQUIRE(el->GetStyle("text-overflow") == "ellipsis");
        REQUIRE(el->GetStyle("overflow") == "hidden");
        REQUIRE(el->GetStyle("white-space") == "nowrap");
    }

    SECTION("Outline") {
        el = el | Outline(2, "red", "dashed");
        REQUIRE(el->GetStyle("outline") == "2px dashed red");
    }

    SECTION("Resize") {
        el = el | Resize("vertical");
        REQUIRE(el->GetStyle("resize") == "vertical");
    }

    SECTION("ScrollBehavior") {
        el = el | ScrollBehavior();
        REQUIRE(el->GetStyle("scroll-behavior") == "smooth");
    }
}

TEST_CASE("Structural decorators") {
    SECTION("Hyperlink wraps") {
        auto el = span("Click") | Hyperlink("https://example.com");
        REQUIRE(el->Tag() == "a");
        REQUIRE(el->GetAttribute("href") == "https://example.com");
        REQUIRE(el->ChildCount() == 1);
        REQUIRE(el->Children()[0]->Tag() == "span");
    }
}
