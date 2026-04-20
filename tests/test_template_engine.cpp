#include <catch2/catch_test_macros.hpp>
#include <nodex/template_engine.hpp>

using namespace nodex;

TEST_CASE("TemplateEngine simple rendering") {
    SECTION("variable substitution") {
        auto result = TemplateEngine::Render("Hello {{ name }}!", {{"name", "World"}});
        REQUIRE(result == "Hello World!");
    }

    SECTION("multiple variables") {
        auto result = TemplateEngine::Render(
            "{{ first }} {{ last }}",
            {{"first", "John"}, {"last", "Doe"}}
        );
        REQUIRE(result == "John Doe");
    }

    SECTION("empty data") {
        auto result = TemplateEngine::Render("Static text", nlohmann::json::object());
        REQUIRE(result == "Static text");
    }
}

TEST_CASE("TemplateEngine loops") {
    SECTION("for loop") {
        auto result = TemplateEngine::Render(
            "{% for item in items %}{{ item }} {% endfor %}",
            {{"items", {"a", "b", "c"}}}
        );
        REQUIRE(result == "a b c ");
    }

    SECTION("loop with index") {
        auto result = TemplateEngine::Render(
            "{% for item in items %}{{ loop.index1 }}:{{ item }} {% endfor %}",
            {{"items", {"x", "y"}}}
        );
        REQUIRE(result == "1:x 2:y ");
    }

    SECTION("empty loop") {
        auto result = TemplateEngine::Render(
            "{% for item in items %}{{ item }}{% endfor %}",
            {{"items", nlohmann::json::array()}}
        );
        REQUIRE(result.empty());
    }
}

TEST_CASE("TemplateEngine conditions") {
    SECTION("if true") {
        auto result = TemplateEngine::Render(
            "{% if show %}visible{% endif %}",
            {{"show", true}}
        );
        REQUIRE(result == "visible");
    }

    SECTION("if false") {
        auto result = TemplateEngine::Render(
            "{% if show %}visible{% endif %}",
            {{"show", false}}
        );
        REQUIRE(result.empty());
    }

    SECTION("if-else") {
        auto result = TemplateEngine::Render(
            "{% if logged_in %}Welcome{% else %}Login{% endif %}",
            {{"logged_in", false}}
        );
        REQUIRE(result == "Login");
    }
}

TEST_CASE("TemplateEngine functions") {
    SECTION("length") {
        auto result = TemplateEngine::Render(
            "{{ length(items) }}",
            {{"items", {1, 2, 3}}}
        );
        REQUIRE(result == "3");
    }

    SECTION("upper") {
        auto result = TemplateEngine::Render(
            "{{ upper(name) }}",
            {{"name", "hello"}}
        );
        REQUIRE(result == "HELLO");
    }

    SECTION("lower") {
        auto result = TemplateEngine::Render(
            "{{ lower(name) }}",
            {{"name", "WORLD"}}
        );
        REQUIRE(result == "world");
    }
}

TEST_CASE("TemplateEngine nested data") {
    SECTION("object access") {
        nlohmann::json data = {
            {"user", {{"name", "Alice"}, {"age", 30}}}
        };
        auto result = TemplateEngine::Render("{{ user.name }} is {{ user.age }}", data);
        REQUIRE(result == "Alice is 30");
    }

    SECTION("array of objects") {
        nlohmann::json data = {
            {"users", {{{"name", "A"}}, {{"name", "B"}}}}
        };
        auto result = TemplateEngine::Render(
            "{% for u in users %}{{ u.name }}{% endfor %}", data
        );
        REQUIRE(result == "AB");
    }
}

TEST_CASE("TemplateEngine HTML generation") {
    SECTION("generate HTML list") {
        nlohmann::json data = {{"items", {"Home", "About", "Contact"}}};
        auto result = TemplateEngine::Render(
            "<ul>{% for item in items %}<li>{{ item }}</li>{% endfor %}</ul>",
            data
        );
        REQUIRE(result == "<ul><li>Home</li><li>About</li><li>Contact</li></ul>");
    }
}
