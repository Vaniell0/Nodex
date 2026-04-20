#include <catch2/catch_test_macros.hpp>
#include <nodex/nodex.hpp>

#include <atomic>
#include <thread>
#include <vector>

using namespace nodex;

TEST_CASE("Registry page operations") {
    Registry reg;

    SECTION("register and create page") {
        reg.RegisterPage("/home", [](const nlohmann::json&) {
            return h1("Home");
        });
        REQUIRE(reg.HasPage("/home"));
        auto el = reg.CreatePage("/home");
        REQUIRE(el->Tag() == "h1");
        REQUIRE(el->TextContent() == "Home");
    }

    SECTION("unregister page") {
        reg.RegisterPage("/about", [](auto) { return div({}); });
        REQUIRE(reg.HasPage("/about"));
        reg.UnregisterPage("/about");
        REQUIRE_FALSE(reg.HasPage("/about"));
    }

    SECTION("create unknown page throws") {
        REQUIRE_THROWS_AS(reg.CreatePage("/nonexistent"), std::runtime_error);
    }

    SECTION("page routes") {
        reg.RegisterPage("/a", [](auto) { return div({}); });
        reg.RegisterPage("/b", [](auto) { return div({}); });
        auto routes = reg.PageRoutes();
        REQUIRE(routes.size() == 2);
        REQUIRE(std::find(routes.begin(), routes.end(), "/a") != routes.end());
        REQUIRE(std::find(routes.begin(), routes.end(), "/b") != routes.end());
    }

    SECTION("overwrite page") {
        reg.RegisterPage("/home", [](auto) { return h1("Old"); });
        reg.RegisterPage("/home", [](auto) { return h1("New"); });
        auto el = reg.CreatePage("/home");
        REQUIRE(el->TextContent() == "New");
    }
}

TEST_CASE("Registry component operations") {
    Registry reg;

    SECTION("register and create component") {
        reg.RegisterComponent("card", [](const nlohmann::json& data) {
            return div({h2(data.value("title", ""))});
        });
        REQUIRE(reg.HasComponent("card"));
        auto el = reg.CreateComponent("card", {{"title", "Hello"}});
        REQUIRE(el->Tag() == "div");
        REQUIRE(el->ChildCount() == 1);
    }

    SECTION("unregister component") {
        reg.RegisterComponent("btn", [](auto) { return button("Click"); });
        reg.UnregisterComponent("btn");
        REQUIRE_FALSE(reg.HasComponent("btn"));
    }

    SECTION("create unknown component throws") {
        REQUIRE_THROWS_AS(reg.CreateComponent("missing"), std::runtime_error);
    }

    SECTION("component names") {
        reg.RegisterComponent("x", [](auto) { return div({}); });
        reg.RegisterComponent("y", [](auto) { return div({}); });
        auto names = reg.ComponentNames();
        REQUIRE(names.size() == 2);
    }
}

TEST_CASE("Registry page receives data") {
    Registry reg;
    reg.RegisterPage("/greet", [](const nlohmann::json& data) {
        return h1(data.value("name", "World"));
    });

    auto el = reg.CreatePage("/greet", {{"name", "Alice"}});
    REQUIRE(el->TextContent() == "Alice");
}

TEST_CASE("Registry concurrent access") {
    Registry reg;
    reg.RegisterPage("/test", [](auto) { return div({}); });

    std::atomic<int> reads{0};
    std::vector<std::thread> threads;

    // 8 reader threads
    for (int i = 0; i < 8; ++i) {
        threads.emplace_back([&] {
            for (int j = 0; j < 1000; ++j) {
                auto el = reg.CreatePage("/test");
                REQUIRE(el != nullptr);
                reads++;
            }
        });
    }

    // 1 writer thread doing concurrent register/unregister
    threads.emplace_back([&] {
        for (int j = 0; j < 100; ++j) {
            reg.RegisterPage("/dynamic", [](auto) { return div({}); });
            reg.UnregisterPage("/dynamic");
        }
    });

    for (auto& t : threads) t.join();
    REQUIRE(reads >= 8000);
}
