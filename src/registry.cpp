#include "nodex/registry.hpp"

#include <mutex>

namespace nodex {

// --- Component registration ---

void Registry::RegisterComponent(const std::string& name,
                                  ComponentFactory factory) {
    std::unique_lock lock(mutex_);
    components_[name] = std::move(factory);
}

void Registry::UnregisterComponent(const std::string& name) {
    std::unique_lock lock(mutex_);
    components_.erase(name);
}

bool Registry::HasComponent(const std::string& name) const {
    std::shared_lock lock(mutex_);
    return components_.contains(name);
}

Element Registry::CreateComponent(const std::string& name,
                                   const nlohmann::json& data) const {
    std::shared_lock lock(mutex_);
    auto it = components_.find(name);
    if (it == components_.end()) {
        throw std::runtime_error("Component not found: " + name);
    }
    auto factory = it->second;
    lock.unlock();
    return factory(data);
}

// --- Page registration ---

void Registry::RegisterPage(const std::string& route, PageFactory factory) {
    std::unique_lock lock(mutex_);
    pages_[route] = std::move(factory);
}

void Registry::UnregisterPage(const std::string& route) {
    std::unique_lock lock(mutex_);
    pages_.erase(route);
}

bool Registry::HasPage(const std::string& route) const {
    std::shared_lock lock(mutex_);
    return pages_.contains(route);
}

Element Registry::CreatePage(const std::string& route,
                              const nlohmann::json& data) const {
    std::shared_lock lock(mutex_);
    auto it = pages_.find(route);
    if (it == pages_.end()) {
        throw std::runtime_error("Page not found: " + route);
    }
    auto factory = it->second;
    lock.unlock();
    return factory(data);
}

// --- Introspection ---

std::vector<std::string> Registry::ComponentNames() const {
    std::shared_lock lock(mutex_);
    std::vector<std::string> names;
    names.reserve(components_.size());
    for (const auto& [name, _] : components_) {
        names.push_back(name);
    }
    return names;
}

std::vector<std::string> Registry::PageRoutes() const {
    std::shared_lock lock(mutex_);
    std::vector<std::string> routes;
    routes.reserve(pages_.size());
    for (const auto& [route, _] : pages_) {
        routes.push_back(route);
    }
    return routes;
}

} // namespace nodex
