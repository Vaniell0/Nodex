#include "nodex/template_engine.hpp"
#include <inja/inja.hpp>

namespace nodex {

std::string TemplateEngine::template_dir_;

std::string TemplateEngine::Render(const std::string& template_str,
                                   const nlohmann::json& data) {
    inja::Environment env;
    return env.render(template_str, data);
}

std::string TemplateEngine::RenderFile(const std::string& template_path,
                                       const nlohmann::json& data) {
    if (!template_dir_.empty()) {
        inja::Environment env(template_dir_);
        return env.render_file(template_path, data);
    }
    inja::Environment env;
    return env.render_file(template_path, data);
}

void TemplateEngine::SetTemplateDirectory(const std::string& dir) {
    template_dir_ = dir;
}

} // namespace nodex
