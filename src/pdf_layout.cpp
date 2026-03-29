#include "pdf_layout.hpp"

#include <hpdf_config.h>
#include <algorithm>
#include <sstream>
#include <cmath>
#include <set>

namespace fwui::pdf {

// --- Constants ---

static constexpr float HEADING_SIZES[]         = {28.0f, 24.0f, 20.0f, 16.0f, 14.0f, 12.0f};
static constexpr float HEADING_MARGIN_TOP[]    = {20.0f, 18.0f, 16.0f, 14.0f, 12.0f, 10.0f};
static constexpr float HEADING_MARGIN_BOTTOM[] = {10.0f,  8.0f,  6.0f,  6.0f,  4.0f,  4.0f};
static constexpr float PARAGRAPH_MARGIN_BOTTOM = 8.0f;
static constexpr float CODE_BLOCK_PADDING      = 6.0f;
static constexpr float BLOCKQUOTE_INDENT       = 20.0f;
static constexpr float BLOCKQUOTE_BAR_WIDTH    = 3.0f;
static constexpr float LIST_INDENT             = 20.0f;

// --- Helpers ---

static std::vector<std::string> SplitWords(const std::string& text) {
    std::vector<std::string> words;
    std::string current;
    for (char c : text) {
        if (c == ' ' || c == '\t' || c == '\n') {
            if (!current.empty()) {
                words.push_back(std::move(current));
                current.clear();
            }
        } else {
            current += c;
        }
    }
    if (!current.empty()) words.push_back(std::move(current));
    return words;
}

// --- LayoutEngine ---

LayoutEngine::LayoutEngine(HPDF_Doc doc, const PdfRenderer::Options& opts,
                           const FontManager& fonts)
    : doc_(doc), opts_(opts), fonts_(fonts)
{
    content_left_  = opts_.margins.left;
    content_right_ = opts_.page_size.width - opts_.margins.right;
    content_width_ = content_right_ - content_left_;
    page_bottom_   = opts_.margins.bottom;
}

void LayoutEngine::NewPage() {
    page_ = HPDF_AddPage(doc_);
    HPDF_Page_SetWidth(page_, opts_.page_size.width);
    HPDF_Page_SetHeight(page_, opts_.page_size.height);
    cursor_y_ = opts_.page_size.height - opts_.margins.top;
    page_count_++;
    pages_.push_back(page_);
}

bool LayoutEngine::EnsureSpace(float needed) {
    if (!page_ || cursor_y_ - needed < page_bottom_) {
        NewPage();
        return true;
    }
    return false;
}

void LayoutEngine::Layout(const Element& root) {
    if (!root) return;
    NewPage();
    TextStyle base;
    base.font_size = opts_.fonts.default_size;
    LayoutNode(root, base, 0);
}

// --- Tag classification ---

bool LayoutEngine::IsBlockTag(const std::string& tag) {
    static const std::set<std::string> blocks = {
        "div", "section", "article", "nav", "header", "footer", "main", "aside",
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "pre", "blockquote", "ul", "ol", "li",
        "table", "thead", "tbody", "tr",
        "hr", "br", "hbox", "vbox", "grid",
        "form", "details", "dialog", "figure"
    };
    return blocks.count(tag) > 0;
}

bool LayoutEngine::IsInlineTag(const std::string& tag) {
    static const std::set<std::string> inlines = {
        "strong", "em", "code", "span", "a", "mark", "small",
        "sub", "sup", "b", "i", "u", "abbr", "time"
    };
    return inlines.count(tag) > 0;
}

// --- Node dispatch ---

void LayoutEngine::LayoutNode(const Element& node, const TextStyle& inherited, float indent) {
    if (!node) return;

    const auto& tag = node->Tag();

    // Headings: h1-h6
    if (tag.size() == 2 && tag[0] == 'h' && tag[1] >= '1' && tag[1] <= '6') {
        LayoutHeading(node, tag[1] - '0', inherited, indent);
        return;
    }

    if (tag == "p")          { LayoutParagraph(node, inherited, indent); return; }
    if (tag == "hr")         { LayoutHr(indent); return; }
    if (tag == "pre")        { LayoutCodeBlock(node, inherited, indent); return; }
    if (tag == "blockquote") { LayoutBlockquote(node, inherited, indent); return; }
    if (tag == "ul")         { LayoutList(node, false, inherited, indent); return; }
    if (tag == "ol")         { LayoutList(node, true,  inherited, indent); return; }
    if (tag == "table")      { LayoutTable(node, inherited, indent); return; }
    if (tag == "img")        { LayoutImage(node, indent); return; }

    if (tag == "br") {
        cursor_y_ -= inherited.font_size * 1.4f;
        return;
    }

    // Generic block containers — recurse children
    if (IsBlockTag(tag) || (!IsInlineTag(tag) && tag != "")) {
        // Leaf with text only → treat as paragraph
        if (!node->TextContent().empty() && node->Children().empty()) {
            LayoutParagraph(node, inherited, indent);
            return;
        }
        for (const auto& child : node->Children()) {
            LayoutNode(child, inherited, indent);
        }
        return;
    }

    // Inline or text node at top level — treat as paragraph
    LayoutParagraph(node, inherited, indent);
}

// --- Style resolution ---

TextStyle LayoutEngine::StyleForTag(const std::string& tag, const TextStyle& inherited) const {
    TextStyle s = inherited;
    if (tag == "strong" || tag == "b") s.bold   = true;
    else if (tag == "em" || tag == "i") s.italic = true;
    else if (tag == "code") {
        s.mono = true;
        s.font_size = inherited.font_size * 0.9f;
    }
    else if (tag == "small") s.font_size = inherited.font_size * 0.85f;
    return s;
}

void LayoutEngine::ParseColorHex(const std::string& hex, float& r, float& g, float& b) {
    std::string h = hex;
    if (!h.empty() && h[0] == '#') h = h.substr(1);

    if (h.size() == 3) {
        r = static_cast<float>(std::stoi(std::string(2, h[0]), nullptr, 16)) / 255.0f;
        g = static_cast<float>(std::stoi(std::string(2, h[1]), nullptr, 16)) / 255.0f;
        b = static_cast<float>(std::stoi(std::string(2, h[2]), nullptr, 16)) / 255.0f;
    } else if (h.size() == 6) {
        r = static_cast<float>(std::stoi(h.substr(0, 2), nullptr, 16)) / 255.0f;
        g = static_cast<float>(std::stoi(h.substr(2, 2), nullptr, 16)) / 255.0f;
        b = static_cast<float>(std::stoi(h.substr(4, 2), nullptr, 16)) / 255.0f;
    }
}

// --- Inline segment collection ---

void LayoutEngine::CollectInlineSegments(const Element& node, const TextStyle& style,
                                          std::vector<InlineSegment>& out) {
    if (!node) return;

    TextStyle s = StyleForTag(node->Tag(), style);

    // Apply inline styles from the node
    const auto& styles = node->Styles();
    {
        auto it = styles.find("color");
        if (it != styles.end()) ParseColorHex(it->second, s.r, s.g, s.b);
    }
    {
        auto it = styles.find("font-size");
        if (it != styles.end()) {
            try { s.font_size = std::stof(it->second); } catch (...) {}
        }
    }
    {
        auto it = styles.find("font-weight");
        if (it != styles.end() && (it->second == "bold" || it->second == "700"))
            s.bold = true;
    }
    {
        auto it = styles.find("font-style");
        if (it != styles.end() && it->second == "italic")
            s.italic = true;
    }

    // Leaf text content
    if (!node->TextContent().empty()) {
        out.push_back({node->TextContent(), s});
    }

    // Recurse into inline/text children
    for (const auto& child : node->Children()) {
        const auto& ctag = child->Tag();
        if (IsInlineTag(ctag) || ctag.empty() ||
            (!IsBlockTag(ctag) && child->Children().empty())) {
            CollectInlineSegments(child, s, out);
        }
    }
}

// --- Text rendering ---

float LayoutEngine::DrawWrappedSegments(const std::vector<InlineSegment>& segments,
                                         float x, float max_width,
                                         float line_height_factor) {
    if (segments.empty()) return 0;

    // Flatten segments into word tokens with style info
    struct WordToken {
        std::string word;
        TextStyle   style;
        float       width;
    };

    std::vector<WordToken> tokens;
    for (const auto& seg : segments) {
        auto words = SplitWords(seg.text);
        for (auto& w : words) {
            float width = fonts_.TextWidth(page_, w, seg.style.font_size,
                                           seg.style.bold, seg.style.italic, seg.style.mono);
            tokens.push_back({std::move(w), seg.style, width});
        }
    }

    if (tokens.empty()) return 0;

    // Build lines of parts
    struct LinePart {
        std::string text;
        TextStyle   style;
        float       x_offset;
    };

    struct Line {
        std::vector<LinePart> parts;
        float max_font_size = 0;
    };

    std::vector<Line> lines;
    Line current_line;
    float line_x = 0;

    for (const auto& tok : tokens) {
        float space_width = 0;
        if (line_x > 0) {
            space_width = fonts_.TextWidth(page_, " ", tok.style.font_size,
                                           tok.style.bold, tok.style.italic, tok.style.mono);
        }

        if (line_x > 0 && line_x + space_width + tok.width > max_width) {
            lines.push_back(std::move(current_line));
            current_line = {};
            line_x = 0;
            space_width = 0;
        }

        float x_off = (line_x > 0) ? line_x + space_width : 0.0f;
        current_line.parts.push_back({tok.word, tok.style, x_off});
        current_line.max_font_size = std::max(current_line.max_font_size, tok.style.font_size);
        line_x = x_off + tok.width;
    }
    if (!current_line.parts.empty()) lines.push_back(std::move(current_line));

    // Draw lines
    float total_height = 0;
    for (const auto& line : lines) {
        float line_height = line.max_font_size * line_height_factor;
        EnsureSpace(line_height);
        cursor_y_ -= line_height;

        for (const auto& part : line.parts) {
            DrawTextRun(part.text, x + part.x_offset,
                        part.style.font_size, part.style.bold, part.style.italic,
                        part.style.mono, part.style.r, part.style.g, part.style.b);
        }
        total_height += line_height;
    }
    return total_height;
}

void LayoutEngine::DrawTextRun(const std::string& text, float x,
                                float font_size, bool bold, bool italic, bool mono,
                                float r, float g, float b) {
    HPDF_Font font = fonts_.Get(bold, italic, mono);
    HPDF_Page_SetFontAndSize(page_, font, font_size);
    HPDF_Page_SetRGBFill(page_, r, g, b);
    HPDF_Page_BeginText(page_);
    HPDF_Page_MoveTextPos(page_, x, cursor_y_);
    HPDF_Page_ShowText(page_, text.c_str());
    HPDF_Page_EndText(page_);
}

// --- Drawing helpers ---

void LayoutEngine::DrawFilledRect(float x, float y, float w, float h,
                                   float r, float g, float b) {
    HPDF_Page_SetRGBFill(page_, r, g, b);
    HPDF_Page_Rectangle(page_, x, y, w, h);
    HPDF_Page_Fill(page_);
}

void LayoutEngine::DrawLine(float x1, float y1, float x2, float y2,
                             float r, float g, float b, float width) {
    HPDF_Page_SetRGBStroke(page_, r, g, b);
    HPDF_Page_SetLineWidth(page_, width);
    HPDF_Page_MoveTo(page_, x1, y1);
    HPDF_Page_LineTo(page_, x2, y2);
    HPDF_Page_Stroke(page_);
}

// --- Block element layout ---

void LayoutEngine::LayoutHeading(const Element& node, int level,
                                  const TextStyle& inherited, float indent) {
    int idx = std::clamp(level, 1, 6) - 1;

    cursor_y_ -= HEADING_MARGIN_TOP[idx];
    EnsureSpace(HEADING_SIZES[idx] * 1.4f);

    TextStyle style = inherited;
    style.font_size = HEADING_SIZES[idx];
    style.bold = true;

    std::vector<InlineSegment> segments;
    if (!node->TextContent().empty())
        segments.push_back({node->TextContent(), style});
    for (const auto& child : node->Children())
        CollectInlineSegments(child, style, segments);

    DrawWrappedSegments(segments, content_left_ + indent, content_width_ - indent, 1.3f);
    cursor_y_ -= HEADING_MARGIN_BOTTOM[idx];
}

void LayoutEngine::LayoutParagraph(const Element& node, const TextStyle& inherited, float indent) {
    std::vector<InlineSegment> segments;

    if (!node->TextContent().empty())
        segments.push_back({node->TextContent(), inherited});
    for (const auto& child : node->Children())
        CollectInlineSegments(child, inherited, segments);

    if (segments.empty()) return;

    DrawWrappedSegments(segments, content_left_ + indent, content_width_ - indent);
    cursor_y_ -= PARAGRAPH_MARGIN_BOTTOM;
}

void LayoutEngine::LayoutCodeBlock(const Element& node, const TextStyle& inherited, float indent) {
    float x     = content_left_ + indent;
    float max_w = content_width_ - indent;

    // Gather code text — either from node itself or a child <code>
    std::string code_text;
    if (!node->TextContent().empty()) {
        code_text = node->TextContent();
    }
    for (const auto& child : node->Children()) {
        if (child->Tag() == "code" && !child->TextContent().empty())
            code_text = child->TextContent();
    }
    if (code_text.empty()) return;

    float mono_size  = inherited.font_size * 0.9f;
    float line_h     = mono_size * 1.3f;

    // Split into lines
    std::vector<std::string> lines;
    std::istringstream iss(code_text);
    std::string line;
    while (std::getline(iss, line)) lines.push_back(line);

    float block_h = static_cast<float>(lines.size()) * line_h + CODE_BLOCK_PADDING * 2;
    EnsureSpace(block_h);

    // Grey background
    DrawFilledRect(x, cursor_y_ - block_h, max_w, block_h, 0.95f, 0.95f, 0.95f);

    cursor_y_ -= CODE_BLOCK_PADDING;
    for (const auto& l : lines) {
        cursor_y_ -= line_h;
        if (!l.empty())
            DrawTextRun(l, x + CODE_BLOCK_PADDING, mono_size, false, false, true, 0, 0, 0);
    }

    cursor_y_ -= CODE_BLOCK_PADDING + PARAGRAPH_MARGIN_BOTTOM;
}

void LayoutEngine::LayoutBlockquote(const Element& node, const TextStyle& inherited, float indent) {
    float new_indent = indent + BLOCKQUOTE_INDENT;
    float bar_x      = content_left_ + indent + 4.0f;
    float saved_y    = cursor_y_;

    TextStyle style = inherited;
    style.italic = true;
    style.r = style.g = style.b = 0.33f;

    if (!node->TextContent().empty()) {
        std::vector<InlineSegment> segs = {{node->TextContent(), style}};
        DrawWrappedSegments(segs, content_left_ + new_indent, content_width_ - new_indent);
    }
    for (const auto& child : node->Children())
        LayoutNode(child, style, new_indent);

    // Left bar spanning the full height of the blockquote content
    DrawLine(bar_x, saved_y, bar_x, cursor_y_, 0.7f, 0.7f, 0.7f, BLOCKQUOTE_BAR_WIDTH);

    cursor_y_ -= PARAGRAPH_MARGIN_BOTTOM;
}

void LayoutEngine::LayoutList(const Element& node, bool ordered,
                               const TextStyle& inherited, float indent) {
    int item_num = 1;
    for (const auto& child : node->Children()) {
        if (child->Tag() == "li") {
            std::string marker = ordered
                ? std::to_string(item_num++) + "."
                : std::string("\xe2\x80\xa2"); // bullet: •
            LayoutListItem(child, marker, inherited, indent);
        }
    }
    cursor_y_ -= PARAGRAPH_MARGIN_BOTTOM;
}

void LayoutEngine::LayoutListItem(const Element& node, const std::string& marker,
                                   const TextStyle& inherited, float indent) {
    float marker_x = content_left_ + indent;
    float text_x   = content_left_ + indent + LIST_INDENT;
    float text_w   = content_width_ - indent - LIST_INDENT;
    float line_h   = inherited.font_size * 1.4f;

    EnsureSpace(line_h);
    float saved_y = cursor_y_;

    // Draw marker at the position of the first text line
    cursor_y_ -= line_h;
    DrawTextRun(marker, marker_x, inherited.font_size, false, false, false,
                inherited.r, inherited.g, inherited.b);
    cursor_y_ = saved_y;

    // Collect inline content
    std::vector<InlineSegment> segments;
    if (!node->TextContent().empty())
        segments.push_back({node->TextContent(), inherited});

    for (const auto& child : node->Children()) {
        const auto& ctag = child->Tag();
        if (IsInlineTag(ctag) || ctag.empty() ||
            (!IsBlockTag(ctag) && child->Children().empty())) {
            CollectInlineSegments(child, inherited, segments);
        } else {
            // Flush inline segments before a nested block
            if (!segments.empty()) {
                DrawWrappedSegments(segments, text_x, text_w);
                segments.clear();
            }
            LayoutNode(child, inherited, indent + LIST_INDENT);
        }
    }

    if (!segments.empty())
        DrawWrappedSegments(segments, text_x, text_w);
}

void LayoutEngine::LayoutHr(float indent) {
    cursor_y_ -= 10.0f;
    EnsureSpace(1.0f);
    DrawLine(content_left_ + indent, cursor_y_, content_right_, cursor_y_,
             0.7f, 0.7f, 0.7f, 0.5f);
    cursor_y_ -= 10.0f;
}

void LayoutEngine::DrawRect(float x, float y, float w, float h,
                             float r, float g, float b, float width) {
    HPDF_Page_SetRGBStroke(page_, r, g, b);
    HPDF_Page_SetLineWidth(page_, width);
    HPDF_Page_Rectangle(page_, x, y, w, h);
    HPDF_Page_Stroke(page_);
}

// --- Tables ---

static constexpr float TABLE_CELL_PAD  = 4.0f;
static constexpr float TABLE_MARGIN_BOTTOM = 10.0f;

std::vector<ParsedRow> LayoutEngine::ParseTable(const Element& node, const TextStyle& inherited) {
    std::vector<ParsedRow> rows;

    auto collect_rows = [&](const Element& container, bool is_header) {
        for (const auto& child : container->Children()) {
            if (child->Tag() != "tr") continue;
            ParsedRow row;
            row.is_header = is_header;
            for (const auto& cell_node : child->Children()) {
                bool cell_hdr = is_header || cell_node->Tag() == "th";
                ParsedCell cell;
                cell.is_header = cell_hdr;

                TextStyle cell_style = inherited;
                if (cell_hdr) cell_style.bold = true;

                if (!cell_node->TextContent().empty())
                    cell.segments.push_back({cell_node->TextContent(), cell_style});
                for (const auto& inline_child : cell_node->Children())
                    CollectInlineSegments(inline_child, cell_style, cell.segments);

                row.cells.push_back(std::move(cell));
            }
            rows.push_back(std::move(row));
        }
    };

    // Check for thead/tbody children first
    bool has_sections = false;
    for (const auto& child : node->Children()) {
        if (child->Tag() == "thead") { collect_rows(child, true);  has_sections = true; }
        if (child->Tag() == "tbody") { collect_rows(child, false); has_sections = true; }
    }

    // Direct tr children (no thead/tbody)
    if (!has_sections)
        collect_rows(node, false);

    return rows;
}

float LayoutEngine::MeasureWrappedHeight(const std::vector<InlineSegment>& segments,
                                          float max_width, float line_height_factor) {
    if (segments.empty()) return 0;

    struct WordToken { float width; TextStyle style; };
    std::vector<WordToken> tokens;
    for (const auto& seg : segments) {
        auto words = SplitWords(seg.text);
        for (auto& w : words) {
            float width = fonts_.TextWidth(page_, w, seg.style.font_size,
                                           seg.style.bold, seg.style.italic, seg.style.mono);
            tokens.push_back({width, seg.style});
        }
    }

    if (tokens.empty()) return 0;

    float line_x = 0;
    int line_count = 1;
    float max_font = tokens[0].style.font_size;

    for (const auto& tok : tokens) {
        float space_w = 0;
        if (line_x > 0)
            space_w = fonts_.TextWidth(page_, " ", tok.style.font_size,
                                       tok.style.bold, tok.style.italic, tok.style.mono);
        if (line_x > 0 && line_x + space_w + tok.width > max_width) {
            line_count++;
            line_x = tok.width;
        } else {
            line_x += (line_x > 0 ? space_w : 0) + tok.width;
        }
        max_font = std::max(max_font, tok.style.font_size);
    }

    return static_cast<float>(line_count) * max_font * line_height_factor;
}

std::vector<float> LayoutEngine::MeasureColumns(const std::vector<ParsedRow>& rows,
                                                 float available_width) {
    if (rows.empty()) return {};

    // Determine column count
    size_t num_cols = 0;
    for (const auto& row : rows) num_cols = std::max(num_cols, row.cells.size());
    if (num_cols == 0) return {};

    // Measure preferred width per column (max single-line text width + padding)
    std::vector<float> preferred(num_cols, 0);
    for (const auto& row : rows) {
        for (size_t c = 0; c < row.cells.size(); c++) {
            float text_w = 0;
            for (const auto& seg : row.cells[c].segments) {
                auto words = SplitWords(seg.text);
                for (const auto& w : words) {
                    float ww = fonts_.TextWidth(page_, w, seg.style.font_size,
                                                seg.style.bold, seg.style.italic, seg.style.mono);
                    float sp = fonts_.TextWidth(page_, " ", seg.style.font_size,
                                                seg.style.bold, seg.style.italic, seg.style.mono);
                    text_w += (text_w > 0 ? sp : 0) + ww;
                }
            }
            preferred[c] = std::max(preferred[c], text_w + TABLE_CELL_PAD * 2);
        }
    }

    // Distribute available width proportionally
    float total_pref = 0;
    for (float p : preferred) total_pref += p;

    std::vector<float> widths(num_cols);
    if (total_pref <= available_width) {
        // All columns fit — expand proportionally
        float scale = available_width / std::max(total_pref, 1.0f);
        for (size_t c = 0; c < num_cols; c++) widths[c] = preferred[c] * scale;
    } else {
        // Shrink proportionally
        float scale = available_width / std::max(total_pref, 1.0f);
        for (size_t c = 0; c < num_cols; c++) widths[c] = preferred[c] * scale;
    }

    return widths;
}

void LayoutEngine::DrawTableRow(const ParsedRow& row, const std::vector<float>& col_widths,
                                 float x, const TextStyle& inherited) {
    float cell_pad = TABLE_CELL_PAD;

    // First, measure the row height (max cell content height)
    float row_height = inherited.font_size * 1.4f; // minimum
    for (size_t c = 0; c < row.cells.size() && c < col_widths.size(); c++) {
        float cell_w = col_widths[c] - cell_pad * 2;
        float h = MeasureWrappedHeight(row.cells[c].segments, cell_w);
        row_height = std::max(row_height, h);
    }
    row_height += cell_pad * 2;

    EnsureSpace(row_height);

    float row_top = cursor_y_;
    float row_bottom = cursor_y_ - row_height;

    // Draw header background
    if (row.is_header) {
        float total_w = 0;
        for (auto w : col_widths) total_w += w;
        DrawFilledRect(x, row_bottom, total_w, row_height, 0.92f, 0.92f, 0.92f);
    }

    // Draw cells
    float cell_x = x;
    for (size_t c = 0; c < col_widths.size(); c++) {
        float col_w = col_widths[c];

        // Draw cell border
        DrawRect(cell_x, row_bottom, col_w, row_height, 0.6f, 0.6f, 0.6f, 0.5f);

        // Draw cell text
        if (c < row.cells.size() && !row.cells[c].segments.empty()) {
            float saved_cursor = cursor_y_;
            cursor_y_ = row_top - cell_pad;

            // Draw wrapped text within cell
            float text_x = cell_x + cell_pad;
            float text_w = col_w - cell_pad * 2;

            for (const auto& seg : row.cells[c].segments) {
                auto words = SplitWords(seg.text);
                float line_x_pos = 0;

                for (size_t wi = 0; wi < words.size(); wi++) {
                    float ww = fonts_.TextWidth(page_, words[wi], seg.style.font_size,
                                                seg.style.bold, seg.style.italic, seg.style.mono);
                    float sp = 0;
                    if (line_x_pos > 0)
                        sp = fonts_.TextWidth(page_, " ", seg.style.font_size,
                                              seg.style.bold, seg.style.italic, seg.style.mono);

                    if (line_x_pos > 0 && line_x_pos + sp + ww > text_w) {
                        // Wrap
                        cursor_y_ -= seg.style.font_size * 1.4f;
                        line_x_pos = 0;
                        sp = 0;
                    }

                    float draw_x = text_x + line_x_pos + (line_x_pos > 0 ? sp : 0);
                    if (wi == 0 || line_x_pos == 0) {
                        cursor_y_ -= seg.style.font_size * 1.4f;
                        if (wi > 0) cursor_y_ += seg.style.font_size * 1.4f; // undo for wrapping
                    }

                    DrawTextRun(words[wi], draw_x,
                               seg.style.font_size, seg.style.bold, seg.style.italic,
                               seg.style.mono, seg.style.r, seg.style.g, seg.style.b);

                    line_x_pos = (line_x_pos > 0 ? line_x_pos + sp : 0) + ww;
                }
            }

            cursor_y_ = saved_cursor;
        }

        cell_x += col_w;
    }

    cursor_y_ -= row_height;
}

void LayoutEngine::LayoutTable(const Element& node, const TextStyle& inherited, float indent) {
    auto rows = ParseTable(node, inherited);
    if (rows.empty()) return;

    float x = content_left_ + indent;
    float available_width = content_width_ - indent;
    auto col_widths = MeasureColumns(rows, available_width);
    if (col_widths.empty()) return;

    // Find header rows for re-rendering on page break
    std::vector<size_t> header_indices;
    for (size_t i = 0; i < rows.size(); i++) {
        if (rows[i].is_header) header_indices.push_back(i);
    }

    for (size_t i = 0; i < rows.size(); i++) {
        float min_row_h = inherited.font_size * 1.4f + TABLE_CELL_PAD * 2;

        // Check if we need a page break
        if (page_ && cursor_y_ - min_row_h < page_bottom_) {
            NewPage();
            // Re-render header rows on new page
            for (size_t hi : header_indices) {
                DrawTableRow(rows[hi], col_widths, x, inherited);
            }
        }

        DrawTableRow(rows[i], col_widths, x, inherited);
    }

    cursor_y_ -= TABLE_MARGIN_BOTTOM;
}

// --- Images ---

void LayoutEngine::LayoutImage(const Element& node, float indent) {
    std::string src = node->GetAttribute("src");
    if (src.empty()) return;

    // Determine image type and load
    HPDF_Image image = nullptr;
    std::string lower_src = src;
    std::transform(lower_src.begin(), lower_src.end(), lower_src.begin(), ::tolower);

    try {
        if (lower_src.ends_with(".jpg") || lower_src.ends_with(".jpeg")) {
            image = HPDF_LoadJpegImageFromFile(doc_, src.c_str());
        }
#ifdef LIBHPDF_HAVE_LIBPNG
        else if (lower_src.ends_with(".png")) {
            image = HPDF_LoadPngImageFromFile(doc_, src.c_str());
        }
#endif
    } catch (...) {
        // Image loading failed — skip
        return;
    }

    if (!image) return;

    float img_w = static_cast<float>(HPDF_Image_GetWidth(image));
    float img_h = static_cast<float>(HPDF_Image_GetHeight(image));
    float max_w = content_width_ - indent;

    // Scale to fit width
    if (img_w > max_w) {
        float scale = max_w / img_w;
        img_w *= scale;
        img_h *= scale;
    }

    // Max height: 80% of page content area
    float max_h = (opts_.page_size.height - opts_.margins.top - opts_.margins.bottom) * 0.8f;
    if (img_h > max_h) {
        float scale = max_h / img_h;
        img_w *= scale;
        img_h *= scale;
    }

    EnsureSpace(img_h);
    cursor_y_ -= img_h;

    HPDF_Page_DrawImage(page_, image, content_left_ + indent, cursor_y_, img_w, img_h);
    cursor_y_ -= PARAGRAPH_MARGIN_BOTTOM;
}

// --- Headers / Footers / Page numbers (second pass) ---

void LayoutEngine::Finalize() {
    int total = page_count_;

    for (int i = 0; i < total; i++) {
        HPDF_Page pg = pages_[static_cast<size_t>(i)];
        int page_num = i + 1;

        // Header callback
        if (opts_.header) {
            auto header_elem = opts_.header(page_num, total);
            if (header_elem) {
                // Render header text at top margin area
                std::vector<InlineSegment> segs;
                TextStyle hdr_style;
                hdr_style.font_size = opts_.fonts.default_size * 0.85f;
                hdr_style.r = hdr_style.g = hdr_style.b = 0.4f;
                CollectInlineSegments(header_elem, hdr_style, segs);

                float hdr_y = opts_.page_size.height - opts_.margins.top / 2;
                HPDF_Page saved_page = page_;
                float saved_cursor = cursor_y_;
                page_ = pg;
                cursor_y_ = hdr_y;

                for (const auto& seg : segs) {
                    DrawTextRun(seg.text, content_left_,
                               seg.style.font_size, seg.style.bold, seg.style.italic,
                               seg.style.mono, seg.style.r, seg.style.g, seg.style.b);
                }

                page_ = saved_page;
                cursor_y_ = saved_cursor;
            }
        }

        // Footer callback
        if (opts_.footer) {
            auto footer_elem = opts_.footer(page_num, total);
            if (footer_elem) {
                std::vector<InlineSegment> segs;
                TextStyle ftr_style;
                ftr_style.font_size = opts_.fonts.default_size * 0.85f;
                ftr_style.r = ftr_style.g = ftr_style.b = 0.4f;
                CollectInlineSegments(footer_elem, ftr_style, segs);

                float ftr_y = opts_.margins.bottom / 2;
                HPDF_Page saved_page = page_;
                float saved_cursor = cursor_y_;
                page_ = pg;
                cursor_y_ = ftr_y;

                for (const auto& seg : segs) {
                    DrawTextRun(seg.text, content_left_,
                               seg.style.font_size, seg.style.bold, seg.style.italic,
                               seg.style.mono, seg.style.r, seg.style.g, seg.style.b);
                }

                page_ = saved_page;
                cursor_y_ = saved_cursor;
            }
        }

        // Auto page numbers (centered at bottom)
        if (opts_.auto_page_numbers) {
            std::string num_text = opts_.page_number_format;
            // Replace {page} and {total}
            {
                auto pos = num_text.find("{page}");
                if (pos != std::string::npos)
                    num_text.replace(pos, 6, std::to_string(page_num));
            }
            {
                auto pos = num_text.find("{total}");
                if (pos != std::string::npos)
                    num_text.replace(pos, 7, std::to_string(total));
            }

            HPDF_Font font = fonts_.Regular();
            float fsize = opts_.fonts.default_size * 0.8f;
            HPDF_Page_SetFontAndSize(pg, font, fsize);
            float text_w = HPDF_Page_TextWidth(pg, num_text.c_str());
            float center_x = (opts_.page_size.width - text_w) / 2;
            float num_y = opts_.margins.bottom / 2;

            HPDF_Page_SetRGBFill(pg, 0.4f, 0.4f, 0.4f);
            HPDF_Page_BeginText(pg);
            HPDF_Page_MoveTextPos(pg, center_x, num_y);
            HPDF_Page_ShowText(pg, num_text.c_str());
            HPDF_Page_EndText(pg);
        }
    }
}

} // namespace fwui::pdf
