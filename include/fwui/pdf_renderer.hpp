#pragma once

#include "core.hpp"
#include "renderer.hpp"

#include <string>
#include <functional>
#include <filesystem>
#include <optional>

namespace fwui {

struct PageSize {
    float width;
    float height;

    static PageSize A4()     { return {595.28f, 841.89f}; }
    static PageSize Letter() { return {612.0f,  792.0f};  }
    static PageSize A3()     { return {841.89f, 1190.55f}; }
    static PageSize Custom(float w, float h) { return {w, h}; }
};

struct PageMargins {
    float top    = 72.0f;
    float right  = 72.0f;
    float bottom = 72.0f;
    float left   = 72.0f;
};

struct PdfFontConfig {
    std::string default_family = "Helvetica";
    std::string mono_family    = "Courier";
    float default_size         = 12.0f;

    std::optional<std::filesystem::path> ttf_regular;
    std::optional<std::filesystem::path> ttf_bold;
    std::optional<std::filesystem::path> ttf_italic;
    std::optional<std::filesystem::path> ttf_bold_italic;
    std::optional<std::filesystem::path> ttf_mono;
};

using HeaderFooterFn = std::function<Element(int page_number, int total_pages)>;

class PdfRenderer : public Renderer {
public:
    struct Options {
        PageSize      page_size = PageSize::A4();
        PageMargins   margins;
        PdfFontConfig fonts;
        std::string   title;
        std::string   author;
        std::string   subject;

        HeaderFooterFn header;
        HeaderFooterFn footer;

        bool        auto_page_numbers   = false;
        std::string page_number_format  = "Page {page} of {total}";

        Options() = default;
    };

    PdfRenderer();
    explicit PdfRenderer(Options opts);

    std::string Render(const Element& root) const override;

    void RenderToFile(const Element& root,
                      const std::filesystem::path& output) const;

    static std::string RenderToString(const Element& root);
    static void RenderToFile(const Element& root,
                             const std::filesystem::path& output,
                             Options opts);

private:
    Options opts_;
};

} // namespace fwui
