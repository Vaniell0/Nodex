#pragma once

#include "fwui/pdf_renderer.hpp"

#include <hpdf.h>
#include <string>

namespace fwui::pdf {

class FontManager {
public:
    FontManager(HPDF_Doc doc, const PdfFontConfig& config);

    HPDF_Font Get(bool bold, bool italic, bool mono) const;

    HPDF_Font Regular()    const { return regular_; }
    HPDF_Font Bold()       const { return bold_; }
    HPDF_Font Italic()     const { return italic_; }
    HPDF_Font BoldItalic() const { return bold_italic_; }
    HPDF_Font Mono()       const { return mono_; }
    HPDF_Font MonoBold()   const { return mono_bold_; }

    // Measure text width using the specified style, sets font on the page as a side effect
    float TextWidth(HPDF_Page page, const std::string& text,
                    float font_size, bool bold, bool italic, bool mono) const;

private:
    HPDF_Font regular_;
    HPDF_Font bold_;
    HPDF_Font italic_;
    HPDF_Font bold_italic_;
    HPDF_Font mono_;
    HPDF_Font mono_bold_;
};

} // namespace fwui::pdf
