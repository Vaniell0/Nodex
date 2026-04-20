#include <catch2/catch_test_macros.hpp>
#include <nodex/nodex.hpp>

using namespace nodex;

TEST_CASE("Text elements") {
    SECTION("h1-h6 tags") {
        REQUIRE(h1("Title")->Tag() == "h1");
        REQUIRE(h2("Sub")->Tag() == "h2");
        REQUIRE(h3("H3")->Tag() == "h3");
        REQUIRE(h4("H4")->Tag() == "h4");
        REQUIRE(h5("H5")->Tag() == "h5");
        REQUIRE(h6("H6")->Tag() == "h6");
    }

    SECTION("h1 content") {
        auto el = h1("Hello");
        REQUIRE(el->TextContent() == "Hello");
    }

    SECTION("paragraph") {
        auto el = paragraph("Text");
        REQUIRE(el->Tag() == "p");
        REQUIRE(el->TextContent() == "Text");
    }

    SECTION("code and pre") {
        REQUIRE(code("x")->Tag() == "code");
        REQUIRE(pre("y")->Tag() == "pre");
    }
}

TEST_CASE("Container elements") {
    SECTION("div") {
        auto el = div({});
        REQUIRE(el->Tag() == "div");
        REQUIRE(el->ChildCount() == 0);
    }

    SECTION("div with children") {
        auto el = div({h1("Title"), paragraph("Body")});
        REQUIRE(el->ChildCount() == 2);
    }

    SECTION("section, article, nav, header, footer") {
        REQUIRE(section({})->Tag() == "section");
        REQUIRE(article({})->Tag() == "article");
        REQUIRE(nav({})->Tag() == "nav");
        REQUIRE(header({})->Tag() == "header");
        REQUIRE(footer({})->Tag() == "footer");
        REQUIRE(main_elem({})->Tag() == "main");
        REQUIRE(aside({})->Tag() == "aside");
    }
}

TEST_CASE("Layout elements") {
    SECTION("hbox") {
        auto el = hbox({});
        REQUIRE(el->Tag() == "div");
        REQUIRE(el->GetStyle("display") == "flex");
        REQUIRE(el->GetStyle("flex-direction") == "row");
    }

    SECTION("vbox") {
        auto el = vbox({});
        REQUIRE(el->GetStyle("display") == "flex");
        REQUIRE(el->GetStyle("flex-direction") == "column");
    }

    SECTION("grid") {
        auto el = grid({}, 3);
        REQUIRE(el->GetStyle("display") == "grid");
        REQUIRE(el->GetStyle("grid-template-columns") == "repeat(3, 1fr)");
    }
}

TEST_CASE("List elements") {
    SECTION("ul with items") {
        auto el = ul({li("A"), li("B")});
        REQUIRE(el->Tag() == "ul");
        REQUIRE(el->ChildCount() == 2);
    }

    SECTION("ol") {
        auto el = ol({li("1")});
        REQUIRE(el->Tag() == "ol");
    }

    SECTION("li text") {
        auto el = li("Item");
        REQUIRE(el->Tag() == "li");
        REQUIRE(el->TextContent() == "Item");
    }
}

TEST_CASE("Form elements") {
    SECTION("input") {
        auto el = input("email", {{"name", "email"}, {"placeholder", "you@example.com"}});
        REQUIRE(el->Tag() == "input");
        REQUIRE(el->GetAttribute("type") == "email");
        REQUIRE(el->GetAttribute("name") == "email");
        REQUIRE(el->IsSelfClosing());
    }

    SECTION("button") {
        auto el = button("Submit");
        REQUIRE(el->Tag() == "button");
        REQUIRE(el->TextContent() == "Submit");
    }

    SECTION("textarea") {
        auto el = textarea("Initial value");
        REQUIRE(el->Tag() == "textarea");
    }
}

TEST_CASE("Media elements") {
    SECTION("img") {
        auto el = img("photo.jpg", "A photo");
        REQUIRE(el->Tag() == "img");
        REQUIRE(el->GetAttribute("src") == "photo.jpg");
        REQUIRE(el->GetAttribute("alt") == "A photo");
        REQUIRE(el->IsSelfClosing());
    }
}

TEST_CASE("Link element") {
    auto el = a("Click me", "/about");
    REQUIRE(el->Tag() == "a");
    REQUIRE(el->GetAttribute("href") == "/about");
    REQUIRE(el->TextContent() == "Click me");
}

TEST_CASE("Semantic inline elements") {
    REQUIRE(strong("Bold")->Tag() == "strong");
    REQUIRE(em("Italic")->Tag() == "em");
    REQUIRE(mark("Highlight")->Tag() == "mark");
    REQUIRE(br()->Tag() == "br");
    REQUIRE(hr()->Tag() == "hr");
}

TEST_CASE("Raw HTML") {
    auto el = raw("<b>Bold</b>");
    REQUIRE(el->IsRaw());
    REQUIRE(el->TextContent() == "<b>Bold</b>");
}

TEST_CASE("Document structure") {
    auto doc = document("Test Page", {stylesheet("/style.css")}, {h1("Hello")});
    REQUIRE(doc->Tag() == "html");
    // Head should have title and meta tags
    auto head_node = doc->Children()[0];
    REQUIRE(head_node->Tag() == "head");
    // Body should have h1
    auto body_node = doc->Children()[1];
    REQUIRE(body_node->Tag() == "body");
}

TEST_CASE("New interactive elements") {
    SECTION("details with text summary") {
        auto el = details({paragraph("Content")}, "Click to expand");
        REQUIRE(el->Tag() == "details");
        REQUIRE(el->ChildCount() == 2);
        REQUIRE(el->Children()[0]->Tag() == "summary");
        REQUIRE(el->Children()[0]->TextContent() == "Click to expand");
    }

    SECTION("summary") {
        auto el = summary("Title");
        REQUIRE(el->Tag() == "summary");
    }

    SECTION("dialog") {
        auto el = dialog({paragraph("Modal content")});
        REQUIRE(el->Tag() == "dialog");
    }

    SECTION("template") {
        auto el = template_elem({div({})});
        REQUIRE(el->Tag() == "template");
    }
}

TEST_CASE("New semantic elements") {
    SECTION("time") {
        auto el = time_elem("January 1", "2024-01-01");
        REQUIRE(el->Tag() == "time");
        REQUIRE(el->GetAttribute("datetime") == "2024-01-01");
    }

    SECTION("abbr") {
        auto el = abbr("HTML", "HyperText Markup Language");
        REQUIRE(el->Tag() == "abbr");
        REQUIRE(el->GetAttribute("title") == "HyperText Markup Language");
    }

    SECTION("progress") {
        auto el = progress(75, 100);
        REQUIRE(el->Tag() == "progress");
        REQUIRE(el->GetAttribute("value") == "75");
        REQUIRE(el->GetAttribute("max") == "100");
    }

    SECTION("meter") {
        auto el = meter(50, 0, 100);
        REQUIRE(el->Tag() == "meter");
        REQUIRE(el->GetAttribute("value") == "50");
        REQUIRE(el->GetAttribute("min") == "0");
    }
}

TEST_CASE("Data elements") {
    SECTION("datalist") {
        auto el = datalist("browsers", {option("Chrome", "chrome")});
        REQUIRE(el->Tag() == "datalist");
        REQUIRE(el->GetID() == "browsers");
    }

    SECTION("output") {
        auto el = output_elem({{"for", "range1"}});
        REQUIRE(el->Tag() == "output");
    }
}
