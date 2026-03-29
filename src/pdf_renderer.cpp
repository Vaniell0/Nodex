#include "fwui/pdf_renderer.hpp"
#include "pdf_fonts.hpp"
#include "pdf_layout.hpp"

#include <hpdf.h>
#include <fmt/format.h>
#include <fstream>
#include <stdexcept>

namespace fwui {

static void hpdf_error_handler(HPDF_STATUS error_no,
                                HPDF_STATUS detail_no,
                                void* /*user_data*/) {
    throw std::runtime_error(
        fmt::format("libharu error: 0x{:04X} detail: {}", error_no, detail_no));
}

PdfRenderer::PdfRenderer() : opts_() {}
PdfRenderer::PdfRenderer(Options opts) : opts_(std::move(opts)) {}

std::string PdfRenderer::Render(const Element& root) const {
    if (!root) return {};

    HPDF_Doc doc = HPDF_New(hpdf_error_handler, nullptr);
    if (!doc) throw std::runtime_error("Failed to create PDF document");

    struct DocGuard {
        HPDF_Doc d;
        ~DocGuard() { HPDF_Free(d); }
    } guard{doc};

    // PDF metadata
    if (!opts_.title.empty())
        HPDF_SetInfoAttr(doc, HPDF_INFO_TITLE, opts_.title.c_str());
    if (!opts_.author.empty())
        HPDF_SetInfoAttr(doc, HPDF_INFO_AUTHOR, opts_.author.c_str());
    if (!opts_.subject.empty())
        HPDF_SetInfoAttr(doc, HPDF_INFO_SUBJECT, opts_.subject.c_str());

    HPDF_SetCompressionMode(doc, HPDF_COMP_ALL);

    // Font management and layout
    pdf::FontManager  fonts(doc, opts_.fonts);
    pdf::LayoutEngine layout(doc, opts_, fonts);
    layout.Layout(root);
    layout.Finalize(); // second pass: headers, footers, page numbers

    // Save to memory
    HPDF_SaveToStream(doc);
    HPDF_ResetStream(doc);

    std::string result;
    for (;;) {
        HPDF_BYTE buf[4096];
        HPDF_UINT32 size = sizeof(buf);
        HPDF_ReadFromStream(doc, buf, &size);
        if (size == 0) break;
        result.append(reinterpret_cast<const char*>(buf), size);
    }

    return result;
}

void PdfRenderer::RenderToFile(const Element& root,
                                const std::filesystem::path& output) const {
    auto data = Render(root);
    std::ofstream out(output, std::ios::binary);
    if (!out)
        throw std::runtime_error("Cannot open output file: " + output.string());
    out.write(data.data(), static_cast<std::streamsize>(data.size()));
}

std::string PdfRenderer::RenderToString(const Element& root) {
    PdfRenderer renderer;
    return renderer.Render(root);
}

void PdfRenderer::RenderToFile(const Element& root,
                                const std::filesystem::path& output,
                                Options opts) {
    PdfRenderer renderer(std::move(opts));
    renderer.RenderToFile(root, output);
}

} // namespace fwui
