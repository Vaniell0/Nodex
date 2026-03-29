#include "pdf_fonts.hpp"

namespace fwui::pdf {

FontManager::FontManager(HPDF_Doc doc, const PdfFontConfig& config) {
    // Load TrueType fonts if paths provided, otherwise use builtins
    if (config.ttf_regular) {
        const char* name = HPDF_LoadTTFontFromFile(doc, config.ttf_regular->c_str(), HPDF_TRUE);
        regular_ = HPDF_GetFont(doc, name, "UTF-8");
    } else {
        regular_ = HPDF_GetFont(doc, "Helvetica", nullptr);
    }

    if (config.ttf_bold) {
        const char* name = HPDF_LoadTTFontFromFile(doc, config.ttf_bold->c_str(), HPDF_TRUE);
        bold_ = HPDF_GetFont(doc, name, "UTF-8");
    } else {
        bold_ = HPDF_GetFont(doc, "Helvetica-Bold", nullptr);
    }

    if (config.ttf_italic) {
        const char* name = HPDF_LoadTTFontFromFile(doc, config.ttf_italic->c_str(), HPDF_TRUE);
        italic_ = HPDF_GetFont(doc, name, "UTF-8");
    } else {
        italic_ = HPDF_GetFont(doc, "Helvetica-Oblique", nullptr);
    }

    if (config.ttf_bold_italic) {
        const char* name = HPDF_LoadTTFontFromFile(doc, config.ttf_bold_italic->c_str(), HPDF_TRUE);
        bold_italic_ = HPDF_GetFont(doc, name, "UTF-8");
    } else {
        bold_italic_ = HPDF_GetFont(doc, "Helvetica-BoldOblique", nullptr);
    }

    if (config.ttf_mono) {
        const char* name = HPDF_LoadTTFontFromFile(doc, config.ttf_mono->c_str(), HPDF_TRUE);
        mono_      = HPDF_GetFont(doc, name, "UTF-8");
        mono_bold_ = mono_;
    } else {
        mono_      = HPDF_GetFont(doc, "Courier", nullptr);
        mono_bold_ = HPDF_GetFont(doc, "Courier-Bold", nullptr);
    }
}

HPDF_Font FontManager::Get(bool bold, bool italic, bool mono) const {
    if (mono) return bold ? mono_bold_ : mono_;
    if (bold && italic) return bold_italic_;
    if (bold)   return bold_;
    if (italic) return italic_;
    return regular_;
}

float FontManager::TextWidth(HPDF_Page page, const std::string& text,
                              float font_size, bool bold, bool italic, bool mono) const {
    HPDF_Font font = Get(bold, italic, mono);
    HPDF_Page_SetFontAndSize(page, font, font_size);
    return HPDF_Page_TextWidth(page, text.c_str());
}

} // namespace fwui::pdf
