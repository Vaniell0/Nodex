#pragma once

#include "core.hpp"

#include <functional>
#include <map>
#include <optional>
#include <shared_mutex>
#include <stdexcept>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace nodex {

using ComponentFactory = std::function<Element(const nlohmann::json& data)>;
using PageFactory      = std::function<Element(const nlohmann::json& data)>;

class Registry {
public:
    // --- Component registration ---
    void RegisterComponent(const std::string& name, ComponentFactory factory);
    void UnregisterComponent(const std::string& name);
    bool HasComponent(const std::string& name) const;

    // --- Component invocation ---
    Element CreateComponent(const std::string& name,
                            const nlohmann::json& data = {}) const;

    // --- Page registration ---
    void RegisterPage(const std::string& route, PageFactory factory);
    void UnregisterPage(const std::string& route);
    bool HasPage(const std::string& route) const;

    // --- Page invocation ---
    Element CreatePage(const std::string& route,
                       const nlohmann::json& data = {}) const;

    // --- Introspection ---
    std::vector<std::string> ComponentNames() const;
    std::vector<std::string> PageRoutes() const;

private:
    mutable std::shared_mutex               mutex_;
    std::map<std::string, ComponentFactory> components_;
    std::map<std::string, PageFactory>      pages_;
};

} // namespace nodex
