#pragma once

#include "fwui/pdf_renderer.hpp"
#include "pdf_fonts.hpp"

#include <hpdf.h>
#include <string>
#include <vector>

namespace fwui::pdf {

struct TextStyle {
    float font_size = 12.0f;
    bool  bold      = false;
    bool  italic    = false;
    bool  mono      = false;
    float r = 0.0f, g = 0.0f, b = 0.0f; // text color
};

struct InlineSegment {
    std::string text;
    TextStyle   style;
};

// --- Table data structures ---

struct ParsedCell {
    std::vector<InlineSegment> segments;
    bool is_header = false;
};

struct ParsedRow {
    std::vector<ParsedCell> cells;
    bool is_header = false;
};

class LayoutEngine {
public:
    LayoutEngine(HPDF_Doc doc, const PdfRenderer::Options& opts, const FontManager& fonts);

    void Layout(const Element& root);

    // Second pass: render headers/footers on all pages with final page count
    void Finalize();

private:
    HPDF_Doc                    doc_;
    const PdfRenderer::Options& opts_;
    const FontManager&          fonts_;

    HPDF_Page              page_       = nullptr;
    float                  cursor_y_   = 0;
    float                  content_left_;
    float                  content_right_;
    float                  content_width_;
    float                  page_bottom_;
    int                    page_count_ = 0;
    std::vector<HPDF_Page> pages_;     // all pages for header/footer pass

    // --- Page management ---
    void NewPage();
    bool EnsureSpace(float needed);

    // --- Node dispatch ---
    void LayoutNode(const Element& node, const TextStyle& inherited, float indent);

    // --- Block elements ---
    void LayoutHeading   (const Element& node, int level, const TextStyle& inherited, float indent);
    void LayoutParagraph (const Element& node, const TextStyle& inherited, float indent);
    void LayoutCodeBlock (const Element& node, const TextStyle& inherited, float indent);
    void LayoutBlockquote(const Element& node, const TextStyle& inherited, float indent);
    void LayoutList      (const Element& node, bool ordered, const TextStyle& inherited, float indent);
    void LayoutListItem  (const Element& node, const std::string& marker, const TextStyle& inherited, float indent);
    void LayoutHr        (float indent);

    // --- Tables ---
    void LayoutTable(const Element& node, const TextStyle& inherited, float indent);
    std::vector<ParsedRow> ParseTable(const Element& node, const TextStyle& inherited);
    std::vector<float> MeasureColumns(const std::vector<ParsedRow>& rows, float available_width);
    float MeasureWrappedHeight(const std::vector<InlineSegment>& segments, float max_width,
                               float line_height_factor = 1.4f);
    void DrawTableRow(const ParsedRow& row, const std::vector<float>& col_widths,
                      float x, const TextStyle& inherited);

    // --- Images ---
    void LayoutImage(const Element& node, float indent);

    // --- Inline collection ---
    void CollectInlineSegments(const Element& node, const TextStyle& style,
                               std::vector<InlineSegment>& out);

    // --- Text rendering ---
    float DrawWrappedSegments(const std::vector<InlineSegment>& segments,
                              float x, float max_width, float line_height_factor = 1.4f);
    void  DrawTextRun(const std::string& text, float x,
                      float font_size, bool bold, bool italic, bool mono,
                      float r, float g, float b);

    // --- Drawing helpers ---
    void DrawFilledRect(float x, float y, float w, float h, float r, float g, float b);
    void DrawLine(float x1, float y1, float x2, float y2,
                  float r, float g, float b, float width = 1.0f);
    void DrawRect(float x, float y, float w, float h,
                  float r, float g, float b, float width = 0.5f);

    // --- Style helpers ---
    TextStyle StyleForTag(const std::string& tag, const TextStyle& inherited) const;
    static void ParseColorHex(const std::string& hex, float& r, float& g, float& b);
    static bool IsBlockTag (const std::string& tag);
    static bool IsInlineTag(const std::string& tag);
};

} // namespace fwui::pdf
