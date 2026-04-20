#include <catch2/catch_test_macros.hpp>
#include <nodex/nodex.hpp>

using namespace nodex;

TEST_CASE("HtmlRenderer simple elements") {
    SECTION("empty div") {
        auto html = HtmlRenderer::RenderToString(div({}));
        REQUIRE(html == "<div></div>");
    }

    SECTION("div with text") {
        auto el = std::make_shared<Node>("div", "hello");
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html == "<div>hello</div>");
    }

    SECTION("paragraph text") {
        auto html = HtmlRenderer::RenderToString(paragraph("Hello world"));
        REQUIRE(html == "<p>Hello world</p>");
    }

    SECTION("nested elements") {
        auto el = div({h1("Title"), paragraph("Body")});
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html.find("<div>") != std::string::npos);
        REQUIRE(html.find("<h1>Title</h1>") != std::string::npos);
        REQUIRE(html.find("<p>Body</p>") != std::string::npos);
        REQUIRE(html.find("</div>") != std::string::npos);
    }
}

TEST_CASE("HtmlRenderer self-closing tags") {
    SECTION("br") {
        auto html = HtmlRenderer::RenderToString(br());
        REQUIRE(html == "<br />");
    }

    SECTION("hr") {
        auto html = HtmlRenderer::RenderToString(hr());
        REQUIRE(html == "<hr />");
    }

    SECTION("img") {
        auto html = HtmlRenderer::RenderToString(img("photo.jpg", "A photo"));
        REQUIRE(html.find("<img") != std::string::npos);
        REQUIRE(html.find("src=\"photo.jpg\"") != std::string::npos);
        REQUIRE(html.find("alt=\"A photo\"") != std::string::npos);
        REQUIRE(html.find("/>") != std::string::npos);
    }
}

TEST_CASE("HtmlRenderer attributes and styles") {
    SECTION("id attribute") {
        auto el = div({});
        el->SetID("main");
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html.find("id=\"main\"") != std::string::npos);
    }

    SECTION("class attribute") {
        auto el = div({});
        el->AddClass("container");
        el->AddClass("active");
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html.find("class=\"") != std::string::npos);
        REQUIRE(html.find("container") != std::string::npos);
        REQUIRE(html.find("active") != std::string::npos);
    }

    SECTION("style attribute") {
        auto el = div({}) | Color("red") | Bold();
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html.find("style=\"") != std::string::npos);
        REQUIRE(html.find("color: red") != std::string::npos);
        REQUIRE(html.find("font-weight: bold") != std::string::npos);
    }

    SECTION("custom attribute") {
        auto el = div({});
        el->SetAttribute("data-id", "42");
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html.find("data-id=\"42\"") != std::string::npos);
    }
}

TEST_CASE("HtmlRenderer escaping") {
    SECTION("text content is escaped") {
        auto el = paragraph("<script>alert('xss')</script>");
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html.find("<script>") == std::string::npos);
        REQUIRE(html.find("&lt;script&gt;") != std::string::npos);
    }

    SECTION("raw HTML is not escaped") {
        auto el = raw("<b>Bold</b>");
        auto html = HtmlRenderer::RenderToString(el);
        REQUIRE(html.find("<b>Bold</b>") != std::string::npos);
    }
}

TEST_CASE("HtmlRenderer DOCTYPE") {
    SECTION("html root gets DOCTYPE") {
        auto doc = document("Test", {}, {});
        auto html = HtmlRenderer::RenderToString(doc);
        REQUIRE(html.find("<!DOCTYPE html>") != std::string::npos);
        REQUIRE(html.find("<html") != std::string::npos);
    }
}

TEST_CASE("HtmlRenderer pretty print") {
    HtmlRenderer::Options opts;
    opts.pretty = true;
    opts.indent_size = 2;
    HtmlRenderer renderer(opts);

    SECTION("indentation") {
        auto el = div({paragraph("Text")});
        auto html = renderer.Render(el);
        REQUIRE(html.find("  <p>") != std::string::npos);
    }

    SECTION("newlines") {
        auto el = div({paragraph("A"), paragraph("B")});
        auto html = renderer.Render(el);
        // Should contain newlines between elements
        auto count = std::count(html.begin(), html.end(), '\n');
        REQUIRE(count >= 3);
    }
}

TEST_CASE("HtmlRenderer null element") {
    auto html = HtmlRenderer::RenderToString(nullptr);
    REQUIRE(html.empty());
}

TEST_CASE("JsonRenderer") {
    SECTION("compact") {
        JsonRenderer renderer;
        auto el = div({});
        el->SetID("test");
        auto json = renderer.Render(el);
        REQUIRE(json.find("\"tag\":\"div\"") != std::string::npos);
        REQUIRE(json.find("\"id\":\"test\"") != std::string::npos);
    }

    SECTION("pretty") {
        JsonRenderer::Options opts;
        opts.indent = 2;
        JsonRenderer renderer(opts);
        auto json = renderer.Render(paragraph("Hello"));
        REQUIRE(json.find("  ") != std::string::npos); // indented
        REQUIRE(json.find("\"tag\": \"p\"") != std::string::npos);
    }

    SECTION("null element") {
        JsonRenderer renderer;
        REQUIRE(renderer.Render(nullptr) == "null");
    }

    SECTION("round-trip with Node::FromJSON") {
        auto original = div({h1("Title")});
        original->SetID("page");
        original->AddClass("main");
        original->SetStyle("color", "blue");

        JsonRenderer renderer;
        auto json_str = renderer.Render(original);
        auto j = nlohmann::json::parse(json_str);
        auto restored = Node::FromJSON(j);

        REQUIRE(restored->Tag() == "div");
        REQUIRE(restored->GetID() == "page");
        REQUIRE(restored->HasClass("main"));
        REQUIRE(restored->GetStyle("color") == "blue");
        REQUIRE(restored->ChildCount() == 1);
    }
}

TEST_CASE("HtmxRenderer") {
    SECTION("basic render delegates to HTML") {
        HtmxRenderer renderer;
        auto el = div({});
        auto html = renderer.Render(el);
        REQUIRE(html == "<div></div>");
    }

    SECTION("oob attribute") {
        HtmxRenderer::Options opts;
        opts.oob = true;
        HtmxRenderer renderer(opts);
        auto el = div({});
        el->SetID("target");
        auto html = renderer.Render(el);
        REQUIRE(html.find("hx-swap-oob=\"true\"") != std::string::npos);
    }

    SECTION("swap strategy") {
        HtmxRenderer::Options opts;
        opts.swap_strategy = "outerHTML";
        HtmxRenderer renderer(opts);
        auto el = div({});
        auto html = renderer.Render(el);
        REQUIRE(html.find("hx-swap=\"outerHTML\"") != std::string::npos);
    }

    SECTION("swap strategy not overwritten if already set") {
        HtmxRenderer::Options opts;
        opts.swap_strategy = "outerHTML";
        HtmxRenderer renderer(opts);
        auto el = div({});
        el->SetAttribute("hx-swap", "innerHTML");
        auto html = renderer.Render(el);
        REQUIRE(html.find("hx-swap=\"innerHTML\"") != std::string::npos);
    }
}
