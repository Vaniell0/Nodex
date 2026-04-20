#pragma once

#include <string>
#include <nlohmann/json.hpp>

namespace nodex {

class TemplateEngine {
public:
    static std::string Render(const std::string& template_str,
                              const nlohmann::json& data);

    static std::string RenderFile(const std::string& template_path,
                                  const nlohmann::json& data);

    static void SetTemplateDirectory(const std::string& dir);

private:
    static std::string template_dir_;
};

} // namespace nodex
