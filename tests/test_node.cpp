#include <catch2/catch_test_macros.hpp>
#include <nodex/core.hpp>
#include <nodex/renderer.hpp>
#include <cstring>
#include <vector>

using namespace nodex;

TEST_CASE("Node creation") {
    auto node = std::make_shared<Node>("div");
    REQUIRE(node->Tag() == "div");
    REQUIRE(node->TextContent().empty());
    REQUIRE(node->Children().empty());
}

TEST_CASE("Node with text content") {
    auto node = std::make_shared<Node>("p", "Hello");
    REQUIRE(node->Tag() == "p");
    REQUIRE(node->TextContent() == "Hello");
}

TEST_CASE("Node SetTag") {
    auto node = std::make_shared<Node>("div");
    node->SetTag("span");
    REQUIRE(node->Tag() == "span");
}

TEST_CASE("Node attributes") {
    auto node = std::make_shared<Node>("input");

    SECTION("set and get") {
        node->SetAttribute("type", "text");
        REQUIRE(node->GetAttribute("type") == "text");
        REQUIRE(node->HasAttribute("type"));
    }

    SECTION("missing attribute returns empty string") {
        REQUIRE(node->GetAttribute("missing") == "");
        REQUIRE_FALSE(node->HasAttribute("missing"));
    }

    SECTION("remove attribute") {
        node->SetAttribute("name", "test");
        node->RemoveAttribute("name");
        REQUIRE_FALSE(node->HasAttribute("name"));
    }

    SECTION("clear attributes") {
        node->SetAttribute("a", "1");
        node->SetAttribute("b", "2");
        node->ClearAttributes();
        REQUIRE(node->Attributes().empty());
    }
}

TEST_CASE("Node ID") {
    auto node = std::make_shared<Node>("div");
    node->SetID("main");
    REQUIRE(node->GetID() == "main");
    REQUIRE(node->GetAttribute("id") == "main");
}

TEST_CASE("Node classes") {
    auto node = std::make_shared<Node>("div");

    SECTION("add class") {
        node->AddClass("active");
        REQUIRE(node->HasClass("active"));
        REQUIRE(node->ClassString() == "active");
    }

    SECTION("set class replaces") {
        node->AddClass("old");
        node->SetClass("new other");
        REQUIRE_FALSE(node->HasClass("old"));
        REQUIRE(node->HasClass("new"));
        REQUIRE(node->HasClass("other"));
    }

    SECTION("remove class") {
        node->AddClass("a");
        node->AddClass("b");
        node->RemoveClass("a");
        REQUIRE_FALSE(node->HasClass("a"));
        REQUIRE(node->HasClass("b"));
    }

    SECTION("duplicate class not added") {
        node->AddClass("x");
        node->AddClass("x");
        REQUIRE(node->Classes().size() == 1);
    }

    SECTION("clear classes") {
        node->AddClass("a");
        node->AddClass("b");
        node->ClearClasses();
        REQUIRE(node->Classes().empty());
    }
}

TEST_CASE("Node styles") {
    auto node = std::make_shared<Node>("div");

    SECTION("set and get") {
        node->SetStyle("color", "red");
        REQUIRE(node->GetStyle("color") == "red");
    }

    SECTION("style string") {
        node->SetStyle("color", "red");
        node->SetStyle("font-size", "14px");
        auto s = node->StyleString();
        REQUIRE(s.find("color: red;") != std::string::npos);
        REQUIRE(s.find("font-size: 14px;") != std::string::npos);
    }

    SECTION("set style string merges") {
        node->SetStyle("color", "red");
        node->SetStyleString("font-size: 14px; margin: 0");
        REQUIRE(node->GetStyle("color") == "red");
        REQUIRE(node->GetStyle("font-size") == "14px");
        REQUIRE(node->GetStyle("margin") == "0");
    }

    SECTION("remove style") {
        node->SetStyle("color", "red");
        node->RemoveStyle("color");
        REQUIRE(node->GetStyle("color") == "");
    }

    SECTION("clear styles") {
        node->SetStyle("a", "1");
        node->SetStyle("b", "2");
        node->ClearStyles();
        REQUIRE(node->Styles().empty());
    }
}

TEST_CASE("Node children") {
    auto parent = std::make_shared<Node>("div");
    auto child1 = std::make_shared<Node>("p", "First");
    auto child2 = std::make_shared<Node>("p", "Second");

    SECTION("append child") {
        parent->AppendChild(child1);
        REQUIRE(parent->ChildCount() == 1);
        REQUIRE(parent->Children()[0]->TextContent() == "First");
    }

    SECTION("prepend child") {
        parent->AppendChild(child1);
        parent->PrependChild(child2);
        REQUIRE(parent->Children()[0]->TextContent() == "Second");
        REQUIRE(parent->Children()[1]->TextContent() == "First");
    }

    SECTION("remove child") {
        parent->AppendChild(child1);
        parent->AppendChild(child2);
        parent->RemoveChild(0);
        REQUIRE(parent->ChildCount() == 1);
        REQUIRE(parent->Children()[0]->TextContent() == "Second");
    }

    SECTION("insert child") {
        parent->AppendChild(child1);
        parent->AppendChild(child2);
        auto mid = std::make_shared<Node>("p", "Mid");
        parent->InsertChild(1, mid);
        REQUIRE(parent->ChildCount() == 3);
        REQUIRE(parent->Children()[1]->TextContent() == "Mid");
    }

    SECTION("null child ignored") {
        parent->AppendChild(nullptr);
        REQUIRE(parent->ChildCount() == 0);
    }
}

TEST_CASE("Node Clone") {
    auto original = std::make_shared<Node>("div");
    original->SetID("test");
    original->AddClass("active");
    original->SetStyle("color", "red");
    original->AppendChild(std::make_shared<Node>("p", "Hello"));

    auto clone = original->Clone();

    SECTION("clone has same data") {
        REQUIRE(clone->Tag() == "div");
        REQUIRE(clone->GetID() == "test");
        REQUIRE(clone->HasClass("active"));
        REQUIRE(clone->GetStyle("color") == "red");
        REQUIRE(clone->ChildCount() == 1);
        REQUIRE(clone->Children()[0]->TextContent() == "Hello");
    }

    SECTION("clone is independent") {
        clone->SetID("modified");
        clone->AddClass("new");
        REQUIRE(original->GetID() == "test");
        REQUIRE_FALSE(original->HasClass("new"));
    }

    SECTION("deep clone - children are independent") {
        clone->Children()[0]->SetTextContent("Modified");
        REQUIRE(original->Children()[0]->TextContent() == "Hello");
    }
}

TEST_CASE("Node self-closing") {
    REQUIRE(std::make_shared<Node>("br")->IsSelfClosing());
    REQUIRE(std::make_shared<Node>("img")->IsSelfClosing());
    REQUIRE(std::make_shared<Node>("input")->IsSelfClosing());
    REQUIRE(std::make_shared<Node>("meta")->IsSelfClosing());
    REQUIRE(std::make_shared<Node>("hr")->IsSelfClosing());
    REQUIRE_FALSE(std::make_shared<Node>("div")->IsSelfClosing());
    REQUIRE_FALSE(std::make_shared<Node>("p")->IsSelfClosing());
}

TEST_CASE("Node raw HTML") {
    auto node = std::make_shared<Node>("", "<b>Raw</b>");
    REQUIRE_FALSE(node->IsRaw());
    node->SetRaw(true);
    REQUIRE(node->IsRaw());
}

TEST_CASE("EscapeHTML") {
    SECTION("no special chars - fast path") {
        REQUIRE(Node::EscapeHTML("hello world") == "hello world");
    }

    SECTION("all special chars") {
        REQUIRE(Node::EscapeHTML("&") == "&amp;");
        REQUIRE(Node::EscapeHTML("<") == "&lt;");
        REQUIRE(Node::EscapeHTML(">") == "&gt;");
        REQUIRE(Node::EscapeHTML("\"") == "&quot;");
        REQUIRE(Node::EscapeHTML("'") == "&#39;");
    }

    SECTION("mixed content") {
        REQUIRE(Node::EscapeHTML("<div class=\"test\">") ==
                "&lt;div class=&quot;test&quot;&gt;");
    }

    SECTION("empty string") {
        REQUIRE(Node::EscapeHTML("") == "");
    }
}

TEST_CASE("Node JSON round-trip") {
    auto original = std::make_shared<Node>("div");
    original->SetID("main");
    original->AddClass("container");
    original->SetStyle("color", "blue");
    original->AppendChild(std::make_shared<Node>("p", "Hello"));

    auto json = original->ToJSON();
    auto restored = Node::FromJSON(json);

    REQUIRE(restored->Tag() == "div");
    REQUIRE(restored->GetID() == "main");
    REQUIRE(restored->HasClass("container"));
    REQUIRE(restored->GetStyle("color") == "blue");
    REQUIRE(restored->ChildCount() == 1);
    REQUIRE(restored->Children()[0]->Tag() == "p");
    REQUIRE(restored->Children()[0]->TextContent() == "Hello");
}

TEST_CASE("FromJSON with explicit id field") {
    auto j = nlohmann::json::parse(R"({"tag":"div","id":"test","text":"Hello"})");
    auto node = Node::FromJSON(j);
    REQUIRE(node->GetID() == "test");
    REQUIRE(node->TextContent() == "Hello");
}

TEST_CASE("FromJSON batch - complex tree") {
    auto j = nlohmann::json::parse(R"({
        "tag": "div",
        "id": "main",
        "classes": ["container", "active"],
        "styles": {"color": "red", "padding": "10px"},
        "children": [
            {"tag": "h1", "text": "Title", "styles": {"font-weight": "bold"}},
            {"tag": "p", "text": "Body"},
            {"tag": "img", "attrs": {"src": "photo.jpg", "alt": "A photo"}},
            {"tag": "", "text": "<b>Raw</b>", "raw": true}
        ]
    })");
    auto tree = Node::FromJSON(j);

    REQUIRE(tree->Tag() == "div");
    REQUIRE(tree->GetID() == "main");
    REQUIRE(tree->HasClass("container"));
    REQUIRE(tree->HasClass("active"));
    REQUIRE(tree->GetStyle("color") == "red");
    REQUIRE(tree->GetStyle("padding") == "10px");
    REQUIRE(tree->ChildCount() == 4);

    REQUIRE(tree->Children()[0]->Tag() == "h1");
    REQUIRE(tree->Children()[0]->TextContent() == "Title");
    REQUIRE(tree->Children()[0]->GetStyle("font-weight") == "bold");

    REQUIRE(tree->Children()[1]->Tag() == "p");
    REQUIRE(tree->Children()[2]->GetAttribute("src") == "photo.jpg");
    REQUIRE(tree->Children()[3]->IsRaw());
}
