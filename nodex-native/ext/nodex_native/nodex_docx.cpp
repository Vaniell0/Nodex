/*
 * nodex_docx.cpp — DOCX and ODT export for nodex-native.
 *
 * Zero dependencies beyond C++17 stdlib. ZIP uses STORE (no compression).
 * Walks Nodex::Node tree and emits OOXML / ODF XML.
 *
 * Provides:
 *   Nodex::NativeDocx.render_docx(node) → String (binary ZIP)
 *   Nodex::NativeDocx.render_odt(node)  → String (binary ZIP)
 */

#include <ruby.h>
#include <ruby/encoding.h>

#include <string>
#include <vector>
#include <cstring>
#include <cstdint>
#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <sstream>

/* ── Shared symbols from nodex_native.c ─────────────────────────── */

extern "C" {
    extern ID id_tag, id_text, id_raw_html, id_attrs, id_styles;
    extern ID id_classes, id_id, id_children;
    extern VALUE sym_text_node;
    extern rb_encoding *enc_utf8;
}

/* ── CRC-32 (ISO 3309 polynomial) ─────────────────────────────── */

static uint32_t crc32_table[256];
static int crc32_ready = 0;

static void crc32_init() {
    if (crc32_ready) return;
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++)
            c = (c >> 1) ^ (c & 1 ? 0xEDB88320u : 0);
        crc32_table[i] = c;
    }
    crc32_ready = 1;
}

static uint32_t crc32_buf(const void *data, size_t len) {
    auto *p = static_cast<const uint8_t *>(data);
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++)
        crc = crc32_table[(crc ^ p[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

/* ── XmlWriter ─────────────────────────────────────────────────── */

class XmlWriter {
    std::string buf_;
public:
    XmlWriter() { buf_.reserve(8192); }

    XmlWriter& decl() {
        buf_ += "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n";
        return *this;
    }

    XmlWriter& open(const char *tag) {
        buf_ += '<';
        buf_ += tag;
        buf_ += '>';
        return *this;
    }

    XmlWriter& open_attr(const char *tag) {
        buf_ += '<';
        buf_ += tag;
        return *this;
    }

    XmlWriter& attr(const char *name, const char *val) {
        buf_ += ' ';
        buf_ += name;
        buf_ += "=\"";
        xml_escape(val);
        buf_ += '"';
        return *this;
    }

    XmlWriter& attr(const char *name, const std::string &val) {
        return attr(name, val.c_str());
    }

    XmlWriter& attr(const char *name, int val) {
        buf_ += ' ';
        buf_ += name;
        buf_ += "=\"";
        buf_ += std::to_string(val);
        buf_ += '"';
        return *this;
    }

    XmlWriter& end_open() {
        buf_ += '>';
        return *this;
    }

    XmlWriter& close(const char *tag) {
        buf_ += "</";
        buf_ += tag;
        buf_ += '>';
        return *this;
    }

    XmlWriter& self_close() {
        buf_ += "/>";
        return *this;
    }

    XmlWriter& text(const char *s) {
        xml_escape(s);
        return *this;
    }

    XmlWriter& text(const std::string &s) {
        xml_escape(s.c_str(), s.size());
        return *this;
    }

    XmlWriter& raw(const char *s) {
        buf_ += s;
        return *this;
    }

    XmlWriter& raw(const std::string &s) {
        buf_ += s;
        return *this;
    }

    const std::string& str() const { return buf_; }
    void clear() { buf_.clear(); }

private:
    void xml_escape(const char *s) {
        for (; *s; s++) {
            switch (*s) {
            case '&':  buf_ += "&amp;"; break;
            case '<':  buf_ += "&lt;"; break;
            case '>':  buf_ += "&gt;"; break;
            case '"':  buf_ += "&quot;"; break;
            case '\'': buf_ += "&apos;"; break;
            default:   buf_ += *s;
            }
        }
    }

    void xml_escape(const char *s, size_t len) {
        for (size_t i = 0; i < len; i++) {
            switch (s[i]) {
            case '&':  buf_ += "&amp;"; break;
            case '<':  buf_ += "&lt;"; break;
            case '>':  buf_ += "&gt;"; break;
            case '"':  buf_ += "&quot;"; break;
            case '\'': buf_ += "&apos;"; break;
            default:   buf_ += s[i];
            }
        }
    }
};

/* ── ZipWriter (STORE only, no compression) ────────────────────── */

class ZipWriter {
    struct Entry {
        std::string name;
        std::string data;
        uint32_t crc;
        uint32_t offset;
    };
    std::vector<Entry> entries_;
    std::string out_;

    void write_u16(uint16_t v) {
        out_ += static_cast<char>(v & 0xFF);
        out_ += static_cast<char>((v >> 8) & 0xFF);
    }
    void write_u32(uint32_t v) {
        out_ += static_cast<char>(v & 0xFF);
        out_ += static_cast<char>((v >> 8) & 0xFF);
        out_ += static_cast<char>((v >> 16) & 0xFF);
        out_ += static_cast<char>((v >> 24) & 0xFF);
    }

public:
    void add(const std::string &name, const std::string &data) {
        Entry e;
        e.name = name;
        e.data = data;
        e.crc = crc32_buf(data.data(), data.size());
        e.offset = 0;
        entries_.push_back(std::move(e));
    }

    std::string finish() {
        out_.clear();
        out_.reserve(65536);

        /* Local file headers + data */
        for (auto &e : entries_) {
            e.offset = static_cast<uint32_t>(out_.size());
            /* Local file header signature */
            write_u32(0x04034B50);
            write_u16(20);          /* version needed */
            write_u16(0);           /* flags */
            write_u16(0);           /* compression: STORE */
            write_u16(0);           /* mod time */
            write_u16(0);           /* mod date */
            write_u32(e.crc);
            write_u32(static_cast<uint32_t>(e.data.size())); /* compressed */
            write_u32(static_cast<uint32_t>(e.data.size())); /* uncompressed */
            write_u16(static_cast<uint16_t>(e.name.size()));
            write_u16(0);           /* extra field length */
            out_ += e.name;
            out_ += e.data;
        }

        /* Central directory */
        uint32_t cd_offset = static_cast<uint32_t>(out_.size());
        for (auto &e : entries_) {
            write_u32(0x02014B50);  /* central dir signature */
            write_u16(20);          /* version made by */
            write_u16(20);          /* version needed */
            write_u16(0);           /* flags */
            write_u16(0);           /* compression: STORE */
            write_u16(0);           /* mod time */
            write_u16(0);           /* mod date */
            write_u32(e.crc);
            write_u32(static_cast<uint32_t>(e.data.size()));
            write_u32(static_cast<uint32_t>(e.data.size()));
            write_u16(static_cast<uint16_t>(e.name.size()));
            write_u16(0);           /* extra field length */
            write_u16(0);           /* comment length */
            write_u16(0);           /* disk number start */
            write_u16(0);           /* internal attrs */
            write_u32(0);           /* external attrs */
            write_u32(e.offset);    /* local header offset */
            out_ += e.name;
        }

        uint32_t cd_size = static_cast<uint32_t>(out_.size()) - cd_offset;

        /* End of central directory */
        write_u32(0x06054B50);
        write_u16(0);               /* disk number */
        write_u16(0);               /* disk with CD */
        write_u16(static_cast<uint16_t>(entries_.size()));
        write_u16(static_cast<uint16_t>(entries_.size()));
        write_u32(cd_size);
        write_u32(cd_offset);
        write_u16(0);               /* comment length */

        return std::move(out_);
    }
};

/* ── Node reading helpers ──────────────────────────────────────── */

struct NodeData {
    VALUE tag;
    VALUE text;
    VALUE raw_html;
    VALUE attrs;
    VALUE styles;
    VALUE classes;
    VALUE node_id;
    VALUE children;
};

static NodeData read_node(VALUE node) {
    NodeData d;
    d.tag      = rb_ivar_get(node, id_tag);
    d.text     = rb_ivar_get(node, id_text);
    d.raw_html = rb_ivar_get(node, id_raw_html);
    d.attrs    = rb_ivar_get(node, id_attrs);
    d.styles   = rb_ivar_get(node, id_styles);
    d.classes  = rb_ivar_get(node, id_classes);
    d.node_id  = rb_ivar_get(node, id_id);
    d.children = rb_ivar_get(node, id_children);
    return d;
}

static std::string rb_str_to_std(VALUE v) {
    if (!RB_TYPE_P(v, T_STRING)) return {};
    return std::string(RSTRING_PTR(v), static_cast<size_t>(RSTRING_LEN(v)));
}

static std::string get_style(VALUE styles, const char *key) {
    if (!RB_TYPE_P(styles, T_HASH)) return {};
    VALUE v = rb_hash_aref(styles, rb_str_new_cstr(key));
    if (NIL_P(v)) return {};
    return rb_str_to_std(v);
}

static std::string get_attr(VALUE attrs, const char *key) {
    if (!RB_TYPE_P(attrs, T_HASH)) return {};
    VALUE v = rb_hash_aref(attrs, rb_str_new_cstr(key));
    if (NIL_P(v)) return {};
    return rb_str_to_std(v);
}

static std::string tag_str(VALUE tag) {
    if (tag == sym_text_node) return ":text_node";
    if (!RB_TYPE_P(tag, T_STRING)) return {};
    return std::string(RSTRING_PTR(tag), static_cast<size_t>(RSTRING_LEN(tag)));
}

/* ── Color parsing: "#RRGGBB" / "rgb(...)" / named → "RRGGBB" ── */

static const std::unordered_map<std::string, std::string> named_colors = {
    {"red","FF0000"},{"green","008000"},{"blue","0000FF"},{"white","FFFFFF"},
    {"black","000000"},{"yellow","FFFF00"},{"orange","FFA500"},{"purple","800080"},
    {"pink","FFC0CB"},{"gray","808080"},{"grey","808080"},{"cyan","00FFFF"},
    {"magenta","FF00FF"},{"brown","A52A2A"},{"navy","000080"},{"teal","008080"},
    {"maroon","800000"},{"olive","808000"},{"lime","00FF00"},{"aqua","00FFFF"},
    {"silver","C0C0C0"},{"fuchsia","FF00FF"},
};

static std::string parse_color_to_hex6(const std::string &c) {
    if (c.empty()) return {};
    if (c[0] == '#') {
        std::string h = c.substr(1);
        if (h.size() == 3) {
            std::string out;
            for (char ch : h) { out += ch; out += ch; }
            return out;
        }
        if (h.size() == 6) return h;
        return {};
    }
    /* named color */
    std::string lower = c;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    auto it = named_colors.find(lower);
    if (it != named_colors.end()) return it->second;
    return {};
}

/* ── CSS unit parsing ──────────────────────────────────────────── */

/* Parse "12px", "10pt", "1.5em" → twips (1 twip = 1/1440 inch) */
static int css_to_twips(const std::string &val) {
    if (val.empty()) return 0;
    double num = 0;
    try { num = std::stod(val); } catch (...) { return 0; }
    if (val.find("pt") != std::string::npos) return static_cast<int>(num * 20);
    if (val.find("px") != std::string::npos) return static_cast<int>(num * 15);
    if (val.find("em") != std::string::npos) return static_cast<int>(num * 240);
    if (val.find("cm") != std::string::npos) return static_cast<int>(num * 567);
    if (val.find("mm") != std::string::npos) return static_cast<int>(num * 56.7);
    if (val.find("in") != std::string::npos) return static_cast<int>(num * 1440);
    /* default: assume px */
    return static_cast<int>(num * 15);
}

/* Parse CSS value to EMU (English Metric Units, 1 inch = 914400 EMU) */
static int css_to_emu(const std::string &val) {
    if (val.empty()) return 0;
    double num = 0;
    try { num = std::stod(val); } catch (...) { return 0; }
    if (val.find("pt") != std::string::npos) return static_cast<int>(num * 12700);
    if (val.find("px") != std::string::npos) return static_cast<int>(num * 9525);
    if (val.find("cm") != std::string::npos) return static_cast<int>(num * 360000);
    if (val.find("mm") != std::string::npos) return static_cast<int>(num * 36000);
    if (val.find("in") != std::string::npos) return static_cast<int>(num * 914400);
    return static_cast<int>(num * 9525); /* default: px */
}

/* Parse CSS value to cm string (for ODT dimensions) */
static std::string css_to_cm(const std::string &val) {
    if (val.empty()) return {};
    double num = 0;
    try { num = std::stod(val); } catch (...) { return {}; }
    double cm;
    if (val.find("pt") != std::string::npos) cm = num / 72.0 * 2.54;
    else if (val.find("px") != std::string::npos) cm = num / 96.0 * 2.54;
    else if (val.find("cm") != std::string::npos) cm = num;
    else if (val.find("mm") != std::string::npos) cm = num / 10.0;
    else if (val.find("in") != std::string::npos) cm = num * 2.54;
    else cm = num / 96.0 * 2.54; /* default: px */
    std::ostringstream oss;
    oss << cm << "cm";
    return oss.str();
}

/* Parse to half-points (for w:sz) */
static int css_to_half_pt(const std::string &val) {
    if (val.empty()) return 0;
    double num = 0;
    try { num = std::stod(val); } catch (...) { return 0; }
    if (val.find("pt") != std::string::npos) return static_cast<int>(num * 2);
    if (val.find("px") != std::string::npos) return static_cast<int>(num * 1.5);
    if (val.find("em") != std::string::npos) return static_cast<int>(num * 24);
    /* default: assume pt */
    return static_cast<int>(num * 2);
}

/* ── Border parsing ────────────────────────────────────────────── */

struct BorderInfo {
    int size_eighths = 0; /* w:sz in 1/8 pt */
    std::string color;    /* RRGGBB or "auto" */
    std::string style;    /* "single", "double", "dashed", "dotted" */
};

/* Parse CSS border shorthand: "1px solid #333" */
static BorderInfo parse_border(const std::string &val) {
    BorderInfo b;
    if (val.empty() || val == "none" || val == "0") return b;

    /* Extract width */
    int tw = css_to_twips(val);
    b.size_eighths = std::max(tw / 3, 2); /* rough mapping to 1/8 pt */

    /* Extract style */
    if (val.find("dashed") != std::string::npos) b.style = "dashed";
    else if (val.find("dotted") != std::string::npos) b.style = "dotted";
    else if (val.find("double") != std::string::npos) b.style = "double";
    else b.style = "single";

    /* Extract color — look for #RRGGBB or color name */
    auto hash_pos = val.find('#');
    if (hash_pos != std::string::npos) {
        std::string rest = val.substr(hash_pos);
        /* isolate the hex portion */
        size_t end = rest.find_first_of(" \t;", 1);
        std::string hex = rest.substr(0, end);
        b.color = parse_color_to_hex6(hex);
    }
    if (b.color.empty()) b.color = "auto";
    return b;
}

/* ── Page configuration ────────────────────────────────────────── */

struct PageConfig {
    int width_twips  = 12240; /* 8.5 in (Letter) */
    int height_twips = 15840; /* 11 in (Letter) */
    int margin_top    = 1440; /* 1 in */
    int margin_bottom = 1440;
    int margin_left   = 1440;
    int margin_right  = 1440;
};

static PageConfig parse_page_config(VALUE opts) {
    PageConfig pc;
    if (NIL_P(opts) || !RB_TYPE_P(opts, T_HASH)) return pc;

    VALUE v;
    v = rb_hash_aref(opts, rb_str_new_cstr("page_width"));
    if (!NIL_P(v)) pc.width_twips = css_to_twips(rb_str_to_std(v));
    v = rb_hash_aref(opts, rb_str_new_cstr("page_height"));
    if (!NIL_P(v)) pc.height_twips = css_to_twips(rb_str_to_std(v));
    v = rb_hash_aref(opts, rb_str_new_cstr("margin_top"));
    if (!NIL_P(v)) pc.margin_top = css_to_twips(rb_str_to_std(v));
    v = rb_hash_aref(opts, rb_str_new_cstr("margin_bottom"));
    if (!NIL_P(v)) pc.margin_bottom = css_to_twips(rb_str_to_std(v));
    v = rb_hash_aref(opts, rb_str_new_cstr("margin_left"));
    if (!NIL_P(v)) pc.margin_left = css_to_twips(rb_str_to_std(v));
    v = rb_hash_aref(opts, rb_str_new_cstr("margin_right"));
    if (!NIL_P(v)) pc.margin_right = css_to_twips(rb_str_to_std(v));

    /* Presets */
    v = rb_hash_aref(opts, rb_str_new_cstr("page_size"));
    if (RB_TYPE_P(v, T_STRING)) {
        std::string size = rb_str_to_std(v);
        if (size == "A4") { pc.width_twips = 11906; pc.height_twips = 16838; }
        else if (size == "A3") { pc.width_twips = 16838; pc.height_twips = 23811; }
        else if (size == "Legal") { pc.width_twips = 12240; pc.height_twips = 20160; }
    }

    return pc;
}

/* ── Document-level configuration ──────────────────────────────── */

struct DocConfig {
    std::string default_font;        /* e.g. "Times New Roman" */
    std::string default_font_size;   /* half-points: "28" = 14pt */
    int line_spacing_twips = 0;      /* 360 = 1.5× (mult × 240) */
    int first_line_indent = 0;       /* twips: ~709 = 1.25cm */
    std::string header_text;
    std::string footer_text;
    std::string first_page_footer;
    bool page_numbers = false;
    std::string page_number_align;   /* "center" (default) or "right" */
};

static DocConfig parse_doc_config(VALUE opts) {
    DocConfig dc;
    if (NIL_P(opts) || !RB_TYPE_P(opts, T_HASH)) return dc;

    VALUE v;
    v = rb_hash_aref(opts, rb_str_new_cstr("default_font"));
    if (RB_TYPE_P(v, T_STRING)) dc.default_font = rb_str_to_std(v);

    v = rb_hash_aref(opts, rb_str_new_cstr("default_font_size"));
    if (RB_TYPE_P(v, T_STRING)) {
        int hp = css_to_half_pt(rb_str_to_std(v));
        if (hp > 0) dc.default_font_size = std::to_string(hp);
    }

    v = rb_hash_aref(opts, rb_str_new_cstr("line_spacing"));
    if (RB_TYPE_P(v, T_STRING)) {
        double mult = 0;
        try { mult = std::stod(rb_str_to_std(v)); } catch (...) {}
        if (mult > 0) dc.line_spacing_twips = static_cast<int>(mult * 240);
    }

    v = rb_hash_aref(opts, rb_str_new_cstr("first_line_indent"));
    if (RB_TYPE_P(v, T_STRING)) dc.first_line_indent = css_to_twips(rb_str_to_std(v));

    v = rb_hash_aref(opts, rb_str_new_cstr("header"));
    if (RB_TYPE_P(v, T_STRING)) dc.header_text = rb_str_to_std(v);

    v = rb_hash_aref(opts, rb_str_new_cstr("footer"));
    if (RB_TYPE_P(v, T_STRING)) dc.footer_text = rb_str_to_std(v);

    v = rb_hash_aref(opts, rb_str_new_cstr("first_page_footer"));
    if (RB_TYPE_P(v, T_STRING)) dc.first_page_footer = rb_str_to_std(v);

    v = rb_hash_aref(opts, rb_str_new_cstr("page_numbers"));
    if (v == Qtrue) dc.page_numbers = true;

    v = rb_hash_aref(opts, rb_str_new_cstr("page_number_align"));
    if (RB_TYPE_P(v, T_STRING)) dc.page_number_align = rb_str_to_std(v);
    if (dc.page_number_align.empty()) dc.page_number_align = "center";

    return dc;
}

/* ── Tag classification ────────────────────────────────────────── */

static bool is_heading(const std::string &tag) {
    return tag.size() == 2 && tag[0] == 'h' && tag[1] >= '1' && tag[1] <= '6';
}

static int heading_level(const std::string &tag) {
    return tag[1] - '0';
}

static bool is_container(const std::string &tag) {
    static const std::unordered_set<std::string> containers = {
        "div","section","article","main","aside","header","footer","nav",
        "figure","figcaption","details","summary","address","blockquote",
        "form","fieldset","dd","dt","dl"
    };
    return containers.count(tag) > 0;
}

static bool is_inline_format(const std::string &tag) {
    static const std::unordered_set<std::string> inlines = {
        "strong","b","em","i","u","s","del","strike","span","code",
        "sub","sup","small","mark","abbr","cite","dfn","kbd","samp","var","q"
    };
    return inlines.count(tag) > 0;
}

static bool is_skip_tag(const std::string &tag) {
    static const std::unordered_set<std::string> skips = {
        "script","style","svg","canvas","video","audio","iframe",
        "noscript","template","slot"
    };
    return skips.count(tag) > 0;
}

/* ── Shared structs (used by both DOCX and ODT renderers) ──────── */

/* Run properties collected from inline ancestors */
struct RunProps {
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strike = false;
    bool monospace = false;
    std::string color;      /* "RRGGBB" */
    std::string bg_color;   /* "RRGGBB" */
    std::string font_size;  /* half-points as string */
    std::string font_family;
    std::string letter_spacing; /* twips as string */
};

/* Paragraph properties from the block element */
struct ParaProps {
    std::string alignment;       /* left/center/right/justify */
    std::string spacing_before;  /* twips */
    std::string spacing_after;   /* twips */
    std::string line_spacing;    /* twips (line height) */
    std::string line_spacing_rule; /* "auto" for proportional spacing */
    std::string indent_left;     /* twips */
    std::string indent_right;    /* twips */
    std::string indent_first_line; /* twips */
    int heading_level = 0;       /* 1-6 or 0 */
    bool page_break_before = false;
    BorderInfo border;           /* uniform border from CSS `border` */
};

/* ── Shared: merge run props from tag + styles ─────────────────── */

static RunProps compute_run_props(const RunProps &parent, VALUE styles, const std::string &tag) {
    RunProps rp = parent;
    if (tag == "strong" || tag == "b") rp.bold = true;
    if (tag == "em" || tag == "i")     rp.italic = true;
    if (tag == "u")                    rp.underline = true;
    if (tag == "s" || tag == "del" || tag == "strike") rp.strike = true;
    if (tag == "code" || tag == "pre" || tag == "kbd" || tag == "samp") rp.monospace = true;

    std::string fw = get_style(styles, "font-weight");
    if (fw == "bold" || fw == "700" || fw == "800" || fw == "900") rp.bold = true;
    std::string fs = get_style(styles, "font-style");
    if (fs == "italic" || fs == "oblique") rp.italic = true;
    std::string td = get_style(styles, "text-decoration");
    if (td.find("underline") != std::string::npos) rp.underline = true;
    if (td.find("line-through") != std::string::npos) rp.strike = true;

    std::string color = get_style(styles, "color");
    std::string hex = parse_color_to_hex6(color);
    if (!hex.empty()) rp.color = hex;
    std::string bg = get_style(styles, "background-color");
    hex = parse_color_to_hex6(bg);
    if (!hex.empty()) rp.bg_color = hex;

    std::string fsize = get_style(styles, "font-size");
    if (!fsize.empty()) {
        int hp = css_to_half_pt(fsize);
        if (hp > 0) rp.font_size = std::to_string(hp);
    }
    std::string ff = get_style(styles, "font-family");
    if (!ff.empty()) rp.font_family = ff;
    std::string ls = get_style(styles, "letter-spacing");
    if (!ls.empty()) {
        int tw = css_to_twips(ls);
        if (tw != 0) rp.letter_spacing = std::to_string(tw);
    }
    return rp;
}

/* ══════════════════════════════════════════════════════════════════
 *  DOCX Renderer
 * ══════════════════════════════════════════════════════════════════ */

class DocxRenderer {
    XmlWriter body_;
    int rel_id_ = 1;
    std::vector<std::pair<std::string, std::string>> hyperlinks_; /* rId, url */
    std::vector<std::pair<std::string, std::string>> images_;     /* rId, path in zip */
    std::vector<std::string> image_data_;  /* binary data for embedded images */

    /* numbering state */
    int next_num_id_ = 1;
    struct NumDef { int num_id; bool ordered; };
    std::vector<NumDef> num_defs_;

    /* List nesting depth for numbering */
    struct ListCtx { int num_id; int level; bool ordered; };
    std::vector<ListCtx> list_stack_;

    /* Track state for inline content */
    bool in_paragraph_ = false;

    PageConfig page_config_;
    DocConfig doc_config_;

    std::string next_rel_id() {
        return "rId" + std::to_string(rel_id_++);
    }

public:
    std::string render(VALUE root, VALUE opts = Qnil) {
        rel_id_ = 10; /* reserve low IDs for standard rels */
        page_config_ = parse_page_config(opts);
        doc_config_ = parse_doc_config(opts);
        walk(root, RunProps{}, ParaProps{});

        ZipWriter zip;
        zip.add("[Content_Types].xml", content_types());
        zip.add("_rels/.rels", top_rels());
        zip.add("word/_rels/document.xml.rels", doc_rels());
        zip.add("word/document.xml", document_xml());
        zip.add("word/styles.xml", styles_xml());

        if (!num_defs_.empty())
            zip.add("word/numbering.xml", numbering_xml());

        /* Header/footer parts */
        if (has_header()) zip.add("word/header1.xml", header1_xml());
        if (has_footer()) zip.add("word/footer1.xml", footer1_xml());
        if (has_first_page_footer()) zip.add("word/footer2.xml", footer2_xml());

        /* Embedded images */
        for (size_t i = 0; i < images_.size(); i++)
            zip.add(images_[i].second, image_data_[i]);

        return zip.finish();
    }

private:
    /* ── Run properties → OOXML ────────────────────────────────── */

    void write_rpr(XmlWriter &w, const RunProps &rp) {
        bool has_props = rp.bold || rp.italic || rp.underline || rp.strike ||
                         rp.monospace || !rp.color.empty() || !rp.bg_color.empty() ||
                         !rp.font_size.empty() || !rp.font_family.empty() ||
                         !rp.letter_spacing.empty();
        if (!has_props) return;

        w.open("w:rPr");
        if (rp.monospace || !rp.font_family.empty()) {
            std::string font = rp.font_family.empty() ? "Courier New" : rp.font_family;
            w.open_attr("w:rFonts").attr("w:ascii", font).attr("w:hAnsi", font).self_close();
        }
        if (rp.bold)      w.raw("<w:b/>");
        if (rp.italic)    w.raw("<w:i/>");
        if (rp.underline) w.raw("<w:u w:val=\"single\"/>");
        if (rp.strike)    w.raw("<w:strike/>");
        if (!rp.color.empty())
            w.open_attr("w:color").attr("w:val", rp.color).self_close();
        if (!rp.bg_color.empty())
            w.open_attr("w:shd").attr("w:val", "clear")
             .attr("w:color", "auto").attr("w:fill", rp.bg_color).self_close();
        if (!rp.font_size.empty())
            w.open_attr("w:sz").attr("w:val", rp.font_size).self_close();
        if (!rp.letter_spacing.empty())
            w.open_attr("w:spacing").attr("w:val", rp.letter_spacing).self_close();
        w.close("w:rPr");
    }

    /* ── Paragraph properties → OOXML ─────────────────────────── */

    void write_ppr(XmlWriter &w, const ParaProps &pp, int list_num_id = 0, int list_level = -1) {
        bool has_props = pp.heading_level > 0 || !pp.alignment.empty() ||
                         !pp.spacing_before.empty() || !pp.spacing_after.empty() ||
                         !pp.line_spacing.empty() || !pp.indent_left.empty() ||
                         !pp.indent_right.empty() || !pp.indent_first_line.empty() ||
                         list_num_id > 0 || pp.border.size_eighths > 0;
        if (!has_props) return;

        w.open("w:pPr");
        if (pp.border.size_eighths > 0) {
            w.open("w:pBdr");
            const char *sides[] = {"w:top","w:left","w:bottom","w:right"};
            for (auto s : sides) {
                w.open_attr(s).attr("w:val", pp.border.style)
                 .attr("w:sz", pp.border.size_eighths)
                 .attr("w:space", 1)
                 .attr("w:color", pp.border.color).self_close();
            }
            w.close("w:pBdr");
        }
        if (list_num_id > 0) {
            w.open("w:numPr");
            w.open_attr("w:ilvl").attr("w:val", list_level >= 0 ? list_level : 0).self_close();
            w.open_attr("w:numId").attr("w:val", list_num_id).self_close();
            w.close("w:numPr");
        }
        if (pp.heading_level > 0) {
            std::string style = "Heading" + std::to_string(pp.heading_level);
            w.open_attr("w:pStyle").attr("w:val", style).self_close();
        }
        if (!pp.alignment.empty()) {
            std::string jc = pp.alignment;
            if (jc == "left") jc = "start";
            else if (jc == "right") jc = "end";
            else if (jc == "justify") jc = "both";
            w.open_attr("w:jc").attr("w:val", jc).self_close();
        }
        if (!pp.spacing_before.empty() || !pp.spacing_after.empty() || !pp.line_spacing.empty()) {
            w.open_attr("w:spacing");
            if (!pp.spacing_before.empty()) w.attr("w:before", pp.spacing_before);
            if (!pp.spacing_after.empty())  w.attr("w:after", pp.spacing_after);
            if (!pp.line_spacing.empty())   w.attr("w:line", pp.line_spacing);
            if (!pp.line_spacing_rule.empty()) w.attr("w:lineRule", pp.line_spacing_rule);
            w.self_close();
        }
        if (!pp.indent_left.empty() || !pp.indent_right.empty() || !pp.indent_first_line.empty()) {
            w.open_attr("w:ind");
            if (!pp.indent_left.empty())  w.attr("w:left", pp.indent_left);
            if (!pp.indent_right.empty()) w.attr("w:right", pp.indent_right);
            if (!pp.indent_first_line.empty()) w.attr("w:firstLine", pp.indent_first_line);
            w.self_close();
        }
        w.close("w:pPr");
    }

    /* ── Emit a text run ───────────────────────────────────────── */

    void emit_run(const std::string &text, const RunProps &rp) {
        body_.open("w:r");
        write_rpr(body_, rp);
        body_.open_attr("w:t").attr("xml:space", "preserve").end_open();
        body_.text(text);
        body_.close("w:t");
        body_.close("w:r");
    }

    /* ── Ensure we're inside a paragraph ───────────────────────── */

    void ensure_paragraph(const ParaProps &pp) {
        if (!in_paragraph_) {
            body_.open("w:p");
            write_ppr(body_, pp);
            in_paragraph_ = true;
        }
    }

    void close_paragraph() {
        if (in_paragraph_) {
            body_.close("w:p");
            in_paragraph_ = false;
        }
    }

    /* ── Table rendering ─────────────────────────────────────── */

    void walk_table(const NodeData &table_d, const RunProps &rp) {
        body_.open("w:tbl");

        /* Table properties: borders + auto width */
        body_.open("w:tblPr");
        body_.open("w:tblBorders");
        const char *border_types[] = {"w:top","w:left","w:bottom","w:right","w:insideH","w:insideV"};
        for (auto bt : border_types) {
            body_.open_attr(bt).attr("w:val","single").attr("w:sz",4)
                 .attr("w:space",0).attr("w:color","auto").self_close();
        }
        body_.close("w:tblBorders");
        body_.open_attr("w:tblW").attr("w:w",0).attr("w:type","auto").self_close();
        body_.close("w:tblPr");

        /* Walk rows — handle thead/tbody/tfoot transparently */
        if (RB_TYPE_P(table_d.children, T_ARRAY)) {
            long len = RARRAY_LEN(table_d.children);
            for (long i = 0; i < len; i++) {
                VALUE child = RARRAY_AREF(table_d.children, i);
                NodeData cd = read_node(child);
                std::string ctag = tag_str(cd.tag);
                if (ctag == "tr") {
                    walk_table_row(cd, rp);
                } else if (ctag == "thead" || ctag == "tbody" || ctag == "tfoot") {
                    if (RB_TYPE_P(cd.children, T_ARRAY)) {
                        long clen = RARRAY_LEN(cd.children);
                        for (long j = 0; j < clen; j++) {
                            VALUE row = RARRAY_AREF(cd.children, j);
                            NodeData rd = read_node(row);
                            if (tag_str(rd.tag) == "tr")
                                walk_table_row(rd, rp);
                        }
                    }
                }
            }
        }

        body_.close("w:tbl");
    }

    void walk_table_row(const NodeData &row_d, const RunProps &rp) {
        body_.open("w:tr");
        if (RB_TYPE_P(row_d.children, T_ARRAY)) {
            long len = RARRAY_LEN(row_d.children);
            for (long i = 0; i < len; i++) {
                VALUE child = RARRAY_AREF(row_d.children, i);
                NodeData cd = read_node(child);
                std::string ctag = tag_str(cd.tag);
                if (ctag == "td" || ctag == "th") {
                    walk_table_cell(cd, rp, ctag == "th");
                }
            }
        }
        body_.close("w:tr");
    }

    void walk_table_cell(const NodeData &cell_d, const RunProps &rp, bool is_header) {
        body_.open("w:tc");

        /* Cell properties */
        body_.open("w:tcPr");

        /* Width */
        std::string width = get_style(cell_d.styles, "width");
        if (!width.empty()) {
            int tw = css_to_twips(width);
            if (tw > 0)
                body_.open_attr("w:tcW").attr("w:w",tw).attr("w:type","dxa").self_close();
        }

        /* Colspan → gridSpan */
        std::string colspan = get_attr(cell_d.attrs, "colspan");
        if (!colspan.empty()) {
            int span = 1;
            try { span = std::stoi(colspan); } catch (...) {}
            if (span > 1)
                body_.open_attr("w:gridSpan").attr("w:val", span).self_close();
        }

        /* Rowspan → vMerge (start cell = restart, continuation cells handled by caller) */
        std::string rowspan = get_attr(cell_d.attrs, "rowspan");
        if (!rowspan.empty()) {
            int span = 1;
            try { span = std::stoi(rowspan); } catch (...) {}
            if (span > 1)
                body_.open_attr("w:vMerge").attr("w:val", "restart").self_close();
        }

        /* Cell borders */
        BorderInfo cell_border = parse_border(get_style(cell_d.styles, "border"));
        body_.open_attr("w:tcBorders").end_open();
        const char *border_types[] = {"w:top","w:left","w:bottom","w:right"};
        for (auto bt : border_types) {
            if (cell_border.size_eighths > 0) {
                body_.open_attr(bt).attr("w:val", cell_border.style)
                     .attr("w:sz", cell_border.size_eighths)
                     .attr("w:space",0).attr("w:color", cell_border.color).self_close();
            } else {
                body_.open_attr(bt).attr("w:val","single").attr("w:sz",4)
                     .attr("w:space",0).attr("w:color","auto").self_close();
            }
        }
        body_.close("w:tcBorders");

        body_.close("w:tcPr");

        /* Cell content — must contain at least one paragraph */
        RunProps cell_rp = compute_run_props(rp, cell_d.styles, is_header ? "th" : "td");
        if (is_header) cell_rp.bold = true;

        ParaProps cell_pp = make_para_props(cell_d.styles, is_header ? "th" : "td");

        bool had_content = false;
        bool saved_in_para = in_paragraph_;
        in_paragraph_ = false;

        if (RTEST(cell_d.text)) {
            ensure_paragraph(cell_pp);
            emit_run(rb_str_to_std(cell_d.text), cell_rp);
            had_content = true;
        }

        if (RB_TYPE_P(cell_d.children, T_ARRAY)) {
            long len = RARRAY_LEN(cell_d.children);
            for (long i = 0; i < len; i++) {
                walk(RARRAY_AREF(cell_d.children, i), cell_rp, cell_pp);
                had_content = true;
            }
        }

        close_paragraph();

        /* OOXML requires at least one w:p in every cell */
        if (!had_content)
            body_.raw("<w:p/>");

        body_.close("w:tc");
        in_paragraph_ = saved_in_para;
    }

    /* ── Image embedding ──────────────────────────────────────── */

    void emit_image(const std::string &src, VALUE attrs, VALUE styles) {
        /* Try to read file from disk */
        std::string data;
        FILE *f = fopen(src.c_str(), "rb");
        if (f) {
            char buf[8192];
            size_t n;
            while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
                data.append(buf, n);
            fclose(f);
        }

        if (data.empty()) return; /* skip if can't read */

        /* Determine extension */
        std::string ext = "png";
        if (src.size() > 4) {
            std::string tail = src.substr(src.size() - 4);
            std::transform(tail.begin(), tail.end(), tail.begin(), ::tolower);
            if (tail == ".jpg" || tail == "jpeg") ext = "jpeg";
            else if (tail == ".gif") ext = "gif";
            else if (tail == ".bmp") ext = "bmp";
        }

        std::string rid = next_rel_id();
        std::string zip_path = "word/media/image" + std::to_string(images_.size() + 1) + "." + ext;
        images_.push_back({rid, zip_path});
        image_data_.push_back(std::move(data));

        /* Default dimensions — EMU (1 inch = 914400 EMU) */
        int cx = 914400 * 4; /* 4 inches */
        int cy = 914400 * 3; /* 3 inches */

        /* HTML attrs: width="400" height="300" (pixels) */
        std::string w_str = get_attr(attrs, "width");
        std::string h_str = get_attr(attrs, "height");
        if (!w_str.empty()) {
            int v = css_to_emu(w_str);
            if (v > 0) cx = v;
        }
        if (!h_str.empty()) {
            int v = css_to_emu(h_str);
            if (v > 0) cy = v;
        }
        /* CSS styles override attrs: style="width: 200px; height: 150px" */
        std::string sw = get_style(styles, "width");
        std::string sh = get_style(styles, "height");
        if (!sw.empty()) { int v = css_to_emu(sw); if (v > 0) cx = v; }
        if (!sh.empty()) { int v = css_to_emu(sh); if (v > 0) cy = v; }

        /* w:drawing → wp:inline → a:graphic → pic:pic */
        body_.open("w:r");
        body_.open("w:drawing");
        body_.open_attr("wp:inline")
             .attr("distT",0).attr("distB",0).attr("distL",0).attr("distR",0)
             .end_open();
        body_.open_attr("wp:extent").attr("cx",cx).attr("cy",cy).self_close();
        body_.open("wp:docPr");
        body_.close("wp:docPr");
        body_.open("a:graphic");
        body_.open_attr("a:graphicData")
             .attr("uri","http://schemas.openxmlformats.org/drawingml/2006/picture")
             .end_open();
        body_.open("pic:pic");
        body_.open("pic:nvPicPr");
        body_.open("pic:cNvPr");
        body_.close("pic:cNvPr");
        body_.open("pic:cNvPicPr");
        body_.close("pic:cNvPicPr");
        body_.close("pic:nvPicPr");
        body_.open("pic:blipFill");
        body_.open_attr("a:blip").attr("r:embed",rid).self_close();
        body_.open("a:stretch");
        body_.raw("<a:fillRect/>");
        body_.close("a:stretch");
        body_.close("pic:blipFill");
        body_.open("pic:spPr");
        body_.open("a:xfrm");
        body_.open_attr("a:off").attr("x",0).attr("y",0).self_close();
        body_.open_attr("a:ext").attr("cx",cx).attr("cy",cy).self_close();
        body_.close("a:xfrm");
        body_.open_attr("a:prstGeom").attr("prst","rect").end_open();
        body_.raw("<a:avLst/>");
        body_.close("a:prstGeom");
        body_.close("pic:spPr");
        body_.close("pic:pic");
        body_.close("a:graphicData");
        body_.close("a:graphic");
        body_.close("wp:inline");
        body_.close("w:drawing");
        body_.close("w:r");
    }

    /* ── Collect paragraph props from styles ───────────────────── */

    ParaProps make_para_props(VALUE styles, const std::string &tag) {
        ParaProps pp;

        if (is_heading(tag))
            pp.heading_level = heading_level(tag);

        std::string ta = get_style(styles, "text-align");
        if (!ta.empty()) pp.alignment = ta;

        /* Margins → spacing before/after */
        std::string mt = get_style(styles, "margin-top");
        if (!mt.empty()) pp.spacing_before = std::to_string(css_to_twips(mt));
        std::string mb = get_style(styles, "margin-bottom");
        if (!mb.empty()) pp.spacing_after = std::to_string(css_to_twips(mb));
        std::string m = get_style(styles, "margin");
        if (!m.empty()) {
            int tw = css_to_twips(m);
            std::string s = std::to_string(tw);
            if (pp.spacing_before.empty()) pp.spacing_before = s;
            if (pp.spacing_after.empty())  pp.spacing_after = s;
        }

        /* Padding → indentation */
        std::string pl = get_style(styles, "padding-left");
        if (!pl.empty()) pp.indent_left = std::to_string(css_to_twips(pl));
        std::string pr = get_style(styles, "padding-right");
        if (!pr.empty()) pp.indent_right = std::to_string(css_to_twips(pr));
        std::string p = get_style(styles, "padding");
        if (!p.empty()) {
            int tw = css_to_twips(p);
            std::string s = std::to_string(tw);
            if (pp.indent_left.empty())  pp.indent_left = s;
            if (pp.indent_right.empty()) pp.indent_right = s;
        }

        /* Line height */
        std::string lh = get_style(styles, "line-height");
        if (!lh.empty()) pp.line_spacing = std::to_string(css_to_twips(lh));

        /* First-line indent */
        std::string ti = get_style(styles, "text-indent");
        if (!ti.empty()) {
            int tw = css_to_twips(ti);
            if (tw > 0) pp.indent_first_line = std::to_string(tw);
        }

        /* Page break before */
        std::string pbb = get_style(styles, "page-break-before");
        if (pbb == "always") pp.page_break_before = true;

        /* Border */
        std::string b = get_style(styles, "border");
        if (!b.empty()) pp.border = parse_border(b);

        return pp;
    }

    /* ── Main recursive walker ─────────────────────────────────── */

    void walk(VALUE node, const RunProps &rp, const ParaProps &pp) {
        NodeData d = read_node(node);

        /* Raw HTML — skip in document export */
        if (RTEST(d.raw_html)) return;

        std::string tag = tag_str(d.tag);

        /* Text node */
        if (tag == ":text_node") {
            if (RTEST(d.text)) {
                ensure_paragraph(pp);
                emit_run(rb_str_to_std(d.text), rp);
            }
            return;
        }

        /* Skip web-only tags */
        if (is_skip_tag(tag)) return;

        /* Merge run props from this element */
        RunProps child_rp = compute_run_props(rp, d.styles, tag);

        /* ── Page break ───────────────────────────────────────── */
        if (tag == "__page_break__") {
            close_paragraph();
            body_.raw("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>");
            return;
        }

        /* ── br ────────────────────────────────────────────────── */
        if (tag == "br") {
            ensure_paragraph(pp);
            body_.open("w:r");
            body_.raw("<w:br/>");
            body_.close("w:r");
            return;
        }

        /* ── hr ────────────────────────────────────────────────── */
        if (tag == "hr") {
            close_paragraph();
            body_.open("w:p");
            body_.open("w:pPr");
            body_.open("w:pBdr");
            body_.open_attr("w:bottom").attr("w:val", "single")
                 .attr("w:sz", 6).attr("w:space", 1)
                 .attr("w:color", "auto").self_close();
            body_.close("w:pBdr");
            body_.close("w:pPr");
            body_.close("w:p");
            return;
        }

        /* ── Heading or paragraph ──────────────────────────────── */
        if (is_heading(tag) || tag == "p" || tag == "pre") {
            close_paragraph();
            ParaProps child_pp = make_para_props(d.styles, tag);

            /* Apply doc_config defaults for 'p' paragraphs */
            if (tag == "p") {
                if (child_pp.indent_first_line.empty() && doc_config_.first_line_indent > 0)
                    child_pp.indent_first_line = std::to_string(doc_config_.first_line_indent);
                if (child_pp.line_spacing.empty() && doc_config_.line_spacing_twips > 0) {
                    child_pp.line_spacing = std::to_string(doc_config_.line_spacing_twips);
                    child_pp.line_spacing_rule = "auto";
                }
            }

            /* CSS page-break-before: always */
            if (child_pp.page_break_before)
                body_.raw("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>");

            body_.open("w:p");
            write_ppr(body_, child_pp);
            in_paragraph_ = true;

            /* Apply doc_config font defaults to run props */
            if (child_rp.font_family.empty() && !doc_config_.default_font.empty())
                child_rp.font_family = doc_config_.default_font;
            if (child_rp.font_size.empty() && !doc_config_.default_font_size.empty())
                child_rp.font_size = doc_config_.default_font_size;

            /* Emit text content */
            if (RTEST(d.text))
                emit_run(rb_str_to_std(d.text), child_rp);

            /* Walk children */
            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++)
                    walk(RARRAY_AREF(d.children, i), child_rp, child_pp);
            }

            close_paragraph();
            return;
        }

        /* ── Container elements (div, section, etc.) ───────────── */
        if (is_container(tag)) {
            close_paragraph();
            ParaProps child_pp = make_para_props(d.styles, tag);

            if (RTEST(d.text)) {
                ensure_paragraph(child_pp);
                emit_run(rb_str_to_std(d.text), child_rp);
                close_paragraph();
            }

            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++)
                    walk(RARRAY_AREF(d.children, i), child_rp, child_pp);
            }

            close_paragraph();
            return;
        }

        /* ── Inline formatting (strong, em, span, code, etc.) ── */
        if (is_inline_format(tag)) {
            if (RTEST(d.text)) {
                ensure_paragraph(pp);
                emit_run(rb_str_to_std(d.text), child_rp);
            }

            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++)
                    walk(RARRAY_AREF(d.children, i), child_rp, pp);
            }
            return;
        }

        /* ── Lists (ul/ol) ─────────────────────────────────────── */
        if (tag == "ul" || tag == "ol") {
            close_paragraph();
            bool ordered = (tag == "ol");

            int level = 0;
            int num_id;
            if (list_stack_.empty()) {
                /* New top-level list — create numbering definition */
                num_id = next_num_id_++;
                num_defs_.push_back({num_id, ordered});
            } else {
                /* Nested list — reuse parent num_id, bump level */
                num_id = list_stack_.back().num_id;
                level = list_stack_.back().level + 1;
            }

            list_stack_.push_back({num_id, level, ordered});
            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++)
                    walk(RARRAY_AREF(d.children, i), child_rp, pp);
            }
            list_stack_.pop_back();
            return;
        }

        /* ── List item ─────────────────────────────────────────── */
        if (tag == "li") {
            close_paragraph();
            ParaProps li_pp = make_para_props(d.styles, tag);

            int num_id = 0, level = 0;
            if (!list_stack_.empty()) {
                num_id = list_stack_.back().num_id;
                level = list_stack_.back().level;
            }

            body_.open("w:p");
            write_ppr(body_, li_pp, num_id, level);
            in_paragraph_ = true;

            if (RTEST(d.text))
                emit_run(rb_str_to_std(d.text), child_rp);

            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++) {
                    VALUE child = RARRAY_AREF(d.children, i);
                    NodeData cd = read_node(child);
                    std::string ctag = tag_str(cd.tag);
                    /* Nested list inside li — close paragraph first */
                    if (ctag == "ul" || ctag == "ol") {
                        close_paragraph();
                        walk(child, child_rp, li_pp);
                        /* Re-open paragraph if more siblings follow? No — OOXML lists are flat paragraphs */
                    } else {
                        walk(child, child_rp, li_pp);
                    }
                }
            }

            close_paragraph();
            return;
        }

        /* ── Table ──────────────────────────────────────────────── */
        if (tag == "table") {
            close_paragraph();
            walk_table(d, child_rp);
            return;
        }
        /* thead/tbody/tfoot — transparent wrappers */
        if (tag == "thead" || tag == "tbody" || tag == "tfoot") {
            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++)
                    walk(RARRAY_AREF(d.children, i), child_rp, pp);
            }
            return;
        }

        /* ── Hyperlinks ─────────────────────────────────────────── */
        if (tag == "a") {
            std::string href = get_attr(d.attrs, "href");
            ensure_paragraph(pp);

            /* Hyperlink run props: inherit parent + blue underline */
            RunProps link_rp = child_rp;
            if (link_rp.color.empty()) link_rp.color = "0563C1";
            link_rp.underline = true;

            if (!href.empty()) {
                std::string rid = next_rel_id();
                hyperlinks_.push_back({rid, href});
                body_.open_attr("w:hyperlink").attr("r:id", rid).end_open();
            }

            if (RTEST(d.text))
                emit_run(rb_str_to_std(d.text), link_rp);

            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++)
                    walk(RARRAY_AREF(d.children, i), link_rp, pp);
            }

            if (!href.empty())
                body_.close("w:hyperlink");
            return;
        }

        /* ── Images ────────────────────────────────────────────── */
        if (tag == "img") {
            std::string src = get_attr(d.attrs, "src");
            if (src.empty()) return;

            ensure_paragraph(pp);
            emit_image(src, d.attrs, d.styles);
            return;
        }

        /* ── Fallback: treat as container ──────────────────────── */
        if (RTEST(d.text)) {
            ensure_paragraph(pp);
            emit_run(rb_str_to_std(d.text), child_rp);
        }
        if (RB_TYPE_P(d.children, T_ARRAY)) {
            long len = RARRAY_LEN(d.children);
            for (long i = 0; i < len; i++)
                walk(RARRAY_AREF(d.children, i), child_rp, pp);
        }
    }

    /* ── Header/Footer helpers ───────────────────────────────── */

    bool has_header() { return !doc_config_.header_text.empty(); }
    bool has_footer() { return !doc_config_.footer_text.empty() || doc_config_.page_numbers; }
    bool has_first_page_footer() { return !doc_config_.first_page_footer.empty(); }

    std::string header1_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("w:hdr")
         .attr("xmlns:w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
         .end_open();
        w.open("w:p");
        w.open("w:pPr");
        w.open_attr("w:jc").attr("w:val", "center").self_close();
        w.close("w:pPr");
        w.open("w:r");
        w.open_attr("w:t").attr("xml:space", "preserve").end_open();
        w.text(doc_config_.header_text);
        w.close("w:t");
        w.close("w:r");
        w.close("w:p");
        w.close("w:hdr");
        return w.str();
    }

    std::string footer1_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("w:ftr")
         .attr("xmlns:w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
         .end_open();
        w.open("w:p");
        w.open("w:pPr");
        std::string align = doc_config_.page_number_align;
        if (align == "right") align = "end";
        w.open_attr("w:jc").attr("w:val", align).self_close();
        w.close("w:pPr");
        if (!doc_config_.footer_text.empty()) {
            w.open("w:r");
            w.open_attr("w:t").attr("xml:space", "preserve").end_open();
            w.text(doc_config_.footer_text);
            w.close("w:t");
            w.close("w:r");
        }
        if (doc_config_.page_numbers) {
            if (!doc_config_.footer_text.empty()) {
                /* separator space */
                w.open("w:r");
                w.open_attr("w:t").attr("xml:space", "preserve").end_open();
                w.text(" ");
                w.close("w:t");
                w.close("w:r");
            }
            w.raw("<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>");
            w.raw("<w:r><w:instrText xml:space=\"preserve\"> PAGE \\* MERGEFORMAT </w:instrText></w:r>");
            w.raw("<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>");
            w.raw("<w:r><w:t>1</w:t></w:r>");
            w.raw("<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>");
        }
        w.close("w:p");
        w.close("w:ftr");
        return w.str();
    }

    std::string footer2_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("w:ftr")
         .attr("xmlns:w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
         .end_open();
        w.open("w:p");
        w.open("w:pPr");
        w.open_attr("w:jc").attr("w:val", "center").self_close();
        w.close("w:pPr");
        w.open("w:r");
        w.open_attr("w:t").attr("xml:space", "preserve").end_open();
        w.text(doc_config_.first_page_footer);
        w.close("w:t");
        w.close("w:r");
        w.close("w:p");
        w.close("w:ftr");
        return w.str();
    }

    /* ── OOXML boilerplate files ───────────────────────────────── */

    std::string content_types() {
        XmlWriter w;
        w.decl();
        w.open_attr("Types")
         .attr("xmlns", "http://schemas.openxmlformats.org/package/2006/content-types")
         .end_open();
        w.open_attr("Default").attr("Extension", "rels")
         .attr("ContentType", "application/vnd.openxmlformats-package.relationships+xml")
         .self_close();
        w.open_attr("Default").attr("Extension", "xml")
         .attr("ContentType", "application/xml")
         .self_close();
        w.open_attr("Default").attr("Extension", "png")
         .attr("ContentType", "image/png")
         .self_close();
        w.open_attr("Default").attr("Extension", "jpeg")
         .attr("ContentType", "image/jpeg")
         .self_close();
        w.open_attr("Default").attr("Extension", "jpg")
         .attr("ContentType", "image/jpeg")
         .self_close();
        w.open_attr("Override").attr("PartName", "/word/document.xml")
         .attr("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml")
         .self_close();
        w.open_attr("Override").attr("PartName", "/word/styles.xml")
         .attr("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml")
         .self_close();
        if (!num_defs_.empty()) {
            w.open_attr("Override").attr("PartName", "/word/numbering.xml")
             .attr("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml")
             .self_close();
        }
        if (has_header()) {
            w.open_attr("Override").attr("PartName", "/word/header1.xml")
             .attr("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml")
             .self_close();
        }
        if (has_footer()) {
            w.open_attr("Override").attr("PartName", "/word/footer1.xml")
             .attr("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml")
             .self_close();
        }
        if (has_first_page_footer()) {
            w.open_attr("Override").attr("PartName", "/word/footer2.xml")
             .attr("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml")
             .self_close();
        }
        w.close("Types");
        return w.str();
    }

    std::string top_rels() {
        XmlWriter w;
        w.decl();
        w.open_attr("Relationships")
         .attr("xmlns", "http://schemas.openxmlformats.org/package/2006/relationships")
         .end_open();
        w.open_attr("Relationship").attr("Id", "rId1")
         .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument")
         .attr("Target", "word/document.xml").self_close();
        w.close("Relationships");
        return w.str();
    }

    std::string doc_rels() {
        XmlWriter w;
        w.decl();
        w.open_attr("Relationships")
         .attr("xmlns", "http://schemas.openxmlformats.org/package/2006/relationships")
         .end_open();
        w.open_attr("Relationship").attr("Id", "rId1")
         .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles")
         .attr("Target", "styles.xml").self_close();
        if (!num_defs_.empty()) {
            w.open_attr("Relationship").attr("Id", "rId2")
             .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering")
             .attr("Target", "numbering.xml").self_close();
        }
        if (has_header()) {
            w.open_attr("Relationship").attr("Id", "rId3")
             .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header")
             .attr("Target", "header1.xml").self_close();
        }
        if (has_footer()) {
            w.open_attr("Relationship").attr("Id", "rId4")
             .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer")
             .attr("Target", "footer1.xml").self_close();
        }
        if (has_first_page_footer()) {
            w.open_attr("Relationship").attr("Id", "rId5")
             .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer")
             .attr("Target", "footer2.xml").self_close();
        }
        for (auto &h : hyperlinks_) {
            w.open_attr("Relationship").attr("Id", h.first)
             .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink")
             .attr("Target", h.second)
             .attr("TargetMode", "External").self_close();
        }
        for (auto &img : images_) {
            w.open_attr("Relationship").attr("Id", img.first)
             .attr("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image")
             .attr("Target", img.second.substr(5)).self_close(); /* strip "word/" */
        }
        w.close("Relationships");
        return w.str();
    }

    std::string document_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("w:document")
         .attr("xmlns:w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
         .attr("xmlns:r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")
         .attr("xmlns:wp", "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing")
         .attr("xmlns:a", "http://schemas.openxmlformats.org/drawingml/2006/main")
         .attr("xmlns:pic", "http://schemas.openxmlformats.org/drawingml/2006/picture")
         .end_open();
        w.open("w:body");
        w.raw(body_.str());

        /* Section properties — page size, margins, headers/footers */
        w.open("w:sectPr");
        if (has_header())
            w.open_attr("w:headerReference").attr("w:type", "default").attr("r:id", "rId3").self_close();
        if (has_footer())
            w.open_attr("w:footerReference").attr("w:type", "default").attr("r:id", "rId4").self_close();
        if (has_first_page_footer())
            w.open_attr("w:footerReference").attr("w:type", "first").attr("r:id", "rId5").self_close();
        w.open_attr("w:pgSz")
         .attr("w:w", page_config_.width_twips)
         .attr("w:h", page_config_.height_twips)
         .self_close();
        w.open_attr("w:pgMar")
         .attr("w:top", page_config_.margin_top)
         .attr("w:bottom", page_config_.margin_bottom)
         .attr("w:left", page_config_.margin_left)
         .attr("w:right", page_config_.margin_right)
         .self_close();
        if (has_first_page_footer())
            w.raw("<w:titlePg/>");
        w.close("w:sectPr");

        w.close("w:body");
        w.close("w:document");
        return w.str();
    }

    std::string styles_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("w:styles")
         .attr("xmlns:w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
         .end_open();

        /* Default style */
        std::string def_font = doc_config_.default_font.empty() ? "Calibri" : doc_config_.default_font;
        int def_sz = doc_config_.default_font_size.empty() ? 22 : std::stoi(doc_config_.default_font_size);
        w.open_attr("w:docDefaults").end_open();
        w.open_attr("w:rPrDefault").end_open();
        w.open("w:rPr");
        w.open_attr("w:rFonts").attr("w:ascii", def_font).attr("w:hAnsi", def_font).self_close();
        w.open_attr("w:sz").attr("w:val", def_sz).self_close();
        w.close("w:rPr");
        w.close("w:rPrDefault");
        w.close("w:docDefaults");

        /* Heading styles 1-6 */
        const int heading_sizes[] = {0, 48, 36, 28, 24, 22, 20};
        for (int i = 1; i <= 6; i++) {
            std::string name = "Heading" + std::to_string(i);
            w.open_attr("w:style").attr("w:type", "paragraph").attr("w:styleId", name).end_open();
            w.open_attr("w:name").attr("w:val", std::string("heading ") + std::to_string(i)).self_close();
            w.open("w:pPr");
            w.open_attr("w:spacing").attr("w:before", 240).attr("w:after", 120).self_close();
            w.close("w:pPr");
            w.open("w:rPr");
            w.raw("<w:b/>");
            w.open_attr("w:sz").attr("w:val", heading_sizes[i]).self_close();
            w.close("w:rPr");
            w.close("w:style");
        }

        w.close("w:styles");
        return w.str();
    }

    std::string numbering_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("w:numbering")
         .attr("xmlns:w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
         .end_open();

        for (auto &nd : num_defs_) {
            std::string aid = std::to_string(nd.num_id);
            w.open_attr("w:abstractNum").attr("w:abstractNumId", aid).end_open();
            for (int lvl = 0; lvl < 9; lvl++) {
                w.open_attr("w:lvl").attr("w:ilvl", lvl).end_open();
                w.open_attr("w:start").attr("w:val", 1).self_close();
                if (nd.ordered) {
                    w.open_attr("w:numFmt").attr("w:val", "decimal").self_close();
                    w.open_attr("w:lvlText").attr("w:val", "%" + std::to_string(lvl+1) + ".").self_close();
                } else {
                    w.open_attr("w:numFmt").attr("w:val", "bullet").self_close();
                    std::string bullet = (lvl == 0) ? "\xE2\x80\xA2" : "\xE2\x97\xA6"; /* • or ◦ */
                    w.open_attr("w:lvlText").attr("w:val", bullet).self_close();
                }
                w.close("w:lvl");
            }
            w.close("w:abstractNum");

            w.open_attr("w:num").attr("w:numId", aid).end_open();
            w.open_attr("w:abstractNumId").attr("w:val", aid).self_close();
            w.close("w:num");
        }

        w.close("w:numbering");
        return w.str();
    }
};

/* ══════════════════════════════════════════════════════════════════
 *  ODT Renderer
 * ══════════════════════════════════════════════════════════════════ */

class OdtRenderer {
    XmlWriter body_;
    int style_id_ = 1;
    int image_id_ = 1;

    /* Automatic styles collected during walk (two-pass: walk then emit) */
    struct AutoStyle {
        std::string name;
        std::string family; /* "paragraph" or "text" */
        /* text props */
        bool bold = false, italic = false, underline = false, strike = false, monospace = false;
        std::string color, bg_color, font_size, font_family, letter_spacing;
        /* paragraph props */
        std::string alignment;
        std::string margin_top, margin_bottom, margin_left, margin_right;
        std::string line_height;
        std::string text_indent;
        bool page_break_before = false;
        int heading_level = 0;
    };
    std::vector<AutoStyle> auto_styles_;

    /* List tracking */
    struct OdtListCtx { bool ordered; int depth; };
    std::vector<OdtListCtx> list_stack_;

    /* Images */
    std::vector<std::pair<std::string, std::string>> images_; /* zip_path, data */

    bool in_paragraph_ = false;
    std::string current_para_style_;
    PageConfig page_config_;
    DocConfig doc_config_;

    std::string make_style_name(const char *prefix) {
        return std::string(prefix) + std::to_string(style_id_++);
    }

public:
    std::string render(VALUE root, VALUE opts = Qnil) {
        page_config_ = parse_page_config(opts);
        doc_config_ = parse_doc_config(opts);
        walk(root, RunProps{});

        ZipWriter zip;
        zip.add("mimetype", "application/vnd.oasis.opendocument.text");
        zip.add("META-INF/manifest.xml", manifest_xml());
        zip.add("content.xml", content_xml());
        zip.add("styles.xml", odt_styles_xml());

        for (auto &img : images_)
            zip.add(img.first, img.second);

        return zip.finish();
    }

private:
    /* ── Text style → ODF properties ─────────────────────────── */

    void write_text_props(XmlWriter &w, const RunProps &rp) {
        bool has = rp.bold || rp.italic || rp.underline || rp.strike ||
                   rp.monospace || !rp.color.empty() || !rp.bg_color.empty() ||
                   !rp.font_size.empty() || !rp.font_family.empty() ||
                   !rp.letter_spacing.empty();
        if (!has) return;

        w.open_attr("style:text-properties");
        if (rp.bold) w.attr("fo:font-weight", "bold");
        if (rp.italic) w.attr("fo:font-style", "italic");
        if (rp.underline) {
            w.attr("style:text-underline-style", "solid");
            w.attr("style:text-underline-width", "auto");
        }
        if (rp.strike) w.attr("style:text-line-through-style", "solid");
        if (rp.monospace || !rp.font_family.empty()) {
            std::string font = rp.font_family.empty() ? "Courier New" : rp.font_family;
            w.attr("style:font-name", font);
        }
        if (!rp.color.empty()) w.attr("fo:color", "#" + rp.color);
        if (!rp.bg_color.empty()) w.attr("fo:background-color", "#" + rp.bg_color);
        if (!rp.font_size.empty()) {
            /* font_size is in half-points, convert to pt */
            int hp = 0;
            try { hp = std::stoi(rp.font_size); } catch (...) {}
            if (hp > 0) {
                std::string pt = std::to_string(hp / 2) + "pt";
                w.attr("fo:font-size", pt);
            }
        }
        if (!rp.letter_spacing.empty()) {
            int tw = 0;
            try { tw = std::stoi(rp.letter_spacing); } catch (...) {}
            /* twips to cm: 1 twip = 1/1440 inch, 1 inch = 2.54 cm */
            double cm = tw / 1440.0 * 2.54;
            std::ostringstream oss;
            oss << cm << "cm";
            w.attr("fo:letter-spacing", oss.str());
        }
        w.self_close();
    }

    bool rp_has_format(const RunProps &rp) {
        return rp.bold || rp.italic || rp.underline || rp.strike ||
               rp.monospace || !rp.color.empty() || !rp.bg_color.empty() ||
               !rp.font_size.empty() || !rp.font_family.empty() ||
               !rp.letter_spacing.empty();
    }

    /* ── Emit text span ───────────────────────────────────────── */

    void emit_span(const std::string &text, const RunProps &rp) {
        if (rp_has_format(rp)) {
            std::string sn = make_style_name("T");
            AutoStyle as;
            as.name = sn;
            as.family = "text";
            as.bold = rp.bold; as.italic = rp.italic;
            as.underline = rp.underline; as.strike = rp.strike;
            as.monospace = rp.monospace;
            as.color = rp.color; as.bg_color = rp.bg_color;
            as.font_size = rp.font_size; as.font_family = rp.font_family;
            as.letter_spacing = rp.letter_spacing;
            auto_styles_.push_back(std::move(as));

            body_.open_attr("text:span").attr("text:style-name", sn).end_open();
            body_.text(text);
            body_.close("text:span");
        } else {
            body_.text(text);
        }
    }

    /* ── Paragraph management ─────────────────────────────────── */

    void open_paragraph(const std::string &style = {}, int heading_level = 0) {
        if (in_paragraph_) close_paragraph();
        if (heading_level > 0) {
            body_.open_attr("text:h")
                 .attr("text:outline-level", heading_level);
            if (!style.empty()) body_.attr("text:style-name", style);
            body_.end_open();
        } else {
            body_.open_attr("text:p");
            if (!style.empty()) body_.attr("text:style-name", style);
            body_.end_open();
        }
        in_paragraph_ = true;
        current_para_style_ = style;
    }

    void ensure_paragraph(const std::string &style = {}, int heading_level = 0) {
        if (!in_paragraph_)
            open_paragraph(style, heading_level);
    }

    void close_paragraph(int heading_level = 0) {
        if (in_paragraph_) {
            if (heading_level > 0)
                body_.close("text:h");
            else
                body_.close("text:p");
            in_paragraph_ = false;
        }
    }

    /* ── Make paragraph style ─────────────────────────────────── */

    std::string make_para_style(VALUE styles, const std::string &tag) {
        std::string align = get_style(styles, "text-align");
        std::string mt = get_style(styles, "margin-top");
        std::string mb = get_style(styles, "margin-bottom");
        std::string ml = get_style(styles, "margin-left");
        std::string mr = get_style(styles, "margin-right");
        std::string m = get_style(styles, "margin");
        std::string pl = get_style(styles, "padding-left");
        std::string pr_s = get_style(styles, "padding-right");
        std::string p = get_style(styles, "padding");
        std::string lh = get_style(styles, "line-height");
        std::string ti = get_style(styles, "text-indent");
        std::string pbb = get_style(styles, "page-break-before");

        /* Apply doc_config defaults for 'p' */
        std::string default_ti;
        std::string default_lh;
        if (tag == "p") {
            if (ti.empty() && doc_config_.first_line_indent > 0) {
                double cm = doc_config_.first_line_indent / 1440.0 * 2.54;
                std::ostringstream oss;
                oss << cm << "cm";
                default_ti = oss.str();
            }
            if (lh.empty() && doc_config_.line_spacing_twips > 0) {
                /* Convert twips (mult*240) to percentage: 360 → 150% */
                int pct = static_cast<int>(doc_config_.line_spacing_twips * 100.0 / 240.0);
                default_lh = std::to_string(pct) + "%";
            }
        }

        bool has_explicit_ti = !ti.empty();
        std::string ti_cm;
        if (!ti.empty()) {
            int tw = css_to_twips(ti);
            double cm = tw / 1440.0 * 2.54;
            std::ostringstream oss;
            oss << cm << "cm";
            ti_cm = oss.str();
        }

        bool has = !align.empty() || !mt.empty() || !mb.empty() || !ml.empty() ||
                   !mr.empty() || !m.empty() || !pl.empty() || !pr_s.empty() ||
                   !p.empty() || !lh.empty() || has_explicit_ti || !default_ti.empty() ||
                   !default_lh.empty() || pbb == "always";
        if (!has) return {};

        std::string sn = make_style_name("P");
        AutoStyle as;
        as.name = sn;
        as.family = "paragraph";
        as.alignment = align;

        /* margins — use specific or fallback to shorthand */
        auto twips_to_cm = [](const std::string &v) -> std::string {
            if (v.empty()) return {};
            int tw = css_to_twips(v);
            double cm = tw / 1440.0 * 2.54;
            std::ostringstream oss;
            oss << cm << "cm";
            return oss.str();
        };

        as.margin_top = twips_to_cm(mt.empty() ? m : mt);
        as.margin_bottom = twips_to_cm(mb.empty() ? m : mb);
        as.margin_left = twips_to_cm(!ml.empty() ? ml : (!pl.empty() ? pl : (!p.empty() ? p : m)));
        as.margin_right = twips_to_cm(!mr.empty() ? mr : (!pr_s.empty() ? pr_s : (!p.empty() ? p : m)));
        as.line_height = !lh.empty() ? lh : default_lh;
        as.text_indent = has_explicit_ti ? ti_cm : default_ti;
        as.page_break_before = (pbb == "always");

        auto_styles_.push_back(std::move(as));
        return sn;
    }

    /* ── Main recursive walker ─────────────────────────────────── */

    void walk(VALUE node, const RunProps &rp) {
        NodeData d = read_node(node);

        if (RTEST(d.raw_html)) return;

        std::string tag = tag_str(d.tag);

        /* Text node */
        if (tag == ":text_node") {
            if (RTEST(d.text)) {
                ensure_paragraph();
                emit_span(rb_str_to_std(d.text), rp);
            }
            return;
        }

        if (is_skip_tag(tag)) return;

        RunProps child_rp = compute_run_props(rp, d.styles, tag);

        /* ── Page break ──────────────────────────────────────── */
        if (tag == "__page_break__") {
            close_paragraph();
            /* Create a paragraph style with page break */
            std::string sn = make_style_name("P");
            AutoStyle as;
            as.name = sn;
            as.family = "paragraph";
            as.page_break_before = true;
            auto_styles_.push_back(std::move(as));
            body_.open_attr("text:p").attr("text:style-name", sn).end_open();
            body_.close("text:p");
            return;
        }

        /* ── br ───────────────────────────────────────────────── */
        if (tag == "br") {
            ensure_paragraph();
            body_.raw("<text:line-break/>");
            return;
        }

        /* ── hr ───────────────────────────────────────────────── */
        if (tag == "hr") {
            close_paragraph();
            /* Create a paragraph style with bottom border */
            std::string sn = make_style_name("P");
            AutoStyle as;
            as.name = sn;
            as.family = "paragraph";
            /* We'll handle hr via a dedicated empty paragraph; border via style */
            auto_styles_.push_back(std::move(as));
            body_.open_attr("text:p").attr("text:style-name", sn).end_open();
            body_.close("text:p");
            return;
        }

        /* ── Heading ──────────────────────────────────────────── */
        if (is_heading(tag)) {
            int level = heading_level(tag);
            close_paragraph();
            std::string sn = make_para_style(d.styles, tag);
            open_paragraph(sn, level);

            if (RTEST(d.text))
                emit_span(rb_str_to_std(d.text), child_rp);
            walk_children(d.children, child_rp);
            close_paragraph(level);
            return;
        }

        /* ── Paragraph / pre ──────────────────────────────────── */
        if (tag == "p" || tag == "pre") {
            close_paragraph();
            std::string sn = make_para_style(d.styles, tag);
            open_paragraph(sn);

            /* Apply doc_config font defaults */
            if (child_rp.font_family.empty() && !doc_config_.default_font.empty())
                child_rp.font_family = doc_config_.default_font;
            if (child_rp.font_size.empty() && !doc_config_.default_font_size.empty())
                child_rp.font_size = doc_config_.default_font_size;

            if (RTEST(d.text))
                emit_span(rb_str_to_std(d.text), child_rp);
            walk_children(d.children, child_rp);
            close_paragraph();
            return;
        }

        /* ── Container ────────────────────────────────────────── */
        if (is_container(tag)) {
            close_paragraph();
            if (RTEST(d.text)) {
                std::string sn = make_para_style(d.styles, tag);
                open_paragraph(sn);
                emit_span(rb_str_to_std(d.text), child_rp);
                close_paragraph();
            }
            walk_children(d.children, child_rp);
            close_paragraph();
            return;
        }

        /* ── Inline formatting ────────────────────────────────── */
        if (is_inline_format(tag)) {
            if (RTEST(d.text)) {
                ensure_paragraph();
                emit_span(rb_str_to_std(d.text), child_rp);
            }
            walk_children(d.children, child_rp);
            return;
        }

        /* ── Lists ────────────────────────────────────────────── */
        if (tag == "ul" || tag == "ol") {
            close_paragraph();
            bool ordered = (tag == "ol");
            int depth = list_stack_.empty() ? 0 : list_stack_.back().depth + 1;
            list_stack_.push_back({ordered, depth});

            body_.open("text:list");
            walk_children(d.children, child_rp);
            body_.close("text:list");

            list_stack_.pop_back();
            return;
        }

        if (tag == "li") {
            body_.open("text:list-item");
            in_paragraph_ = false;

            if (RTEST(d.text)) {
                open_paragraph();
                emit_span(rb_str_to_std(d.text), child_rp);
            }

            if (RB_TYPE_P(d.children, T_ARRAY)) {
                long len = RARRAY_LEN(d.children);
                for (long i = 0; i < len; i++) {
                    VALUE child = RARRAY_AREF(d.children, i);
                    NodeData cd = read_node(child);
                    std::string ctag = tag_str(cd.tag);
                    if (ctag == "ul" || ctag == "ol") {
                        close_paragraph();
                        walk(child, child_rp);
                    } else {
                        if (!in_paragraph_) open_paragraph();
                        walk(child, child_rp);
                    }
                }
            }

            close_paragraph();
            body_.close("text:list-item");
            return;
        }

        /* ── Table ────────────────────────────────────────────── */
        if (tag == "table") {
            close_paragraph();
            odt_walk_table(d, child_rp);
            return;
        }
        if (tag == "thead" || tag == "tbody" || tag == "tfoot") {
            walk_children(d.children, child_rp);
            return;
        }

        /* ── Hyperlink ────────────────────────────────────────── */
        if (tag == "a") {
            std::string href = get_attr(d.attrs, "href");
            ensure_paragraph();

            if (!href.empty())
                body_.open_attr("text:a").attr("xlink:href", href)
                     .attr("xlink:type", "simple").end_open();

            RunProps link_rp = child_rp;
            if (link_rp.color.empty()) link_rp.color = "0563C1";
            link_rp.underline = true;

            if (RTEST(d.text))
                emit_span(rb_str_to_std(d.text), link_rp);
            walk_children(d.children, link_rp);

            if (!href.empty())
                body_.close("text:a");
            return;
        }

        /* ── Image ────────────────────────────────────────────── */
        if (tag == "img") {
            std::string src = get_attr(d.attrs, "src");
            if (src.empty()) return;
            ensure_paragraph();
            odt_emit_image(src, d.attrs, d.styles);
            return;
        }

        /* ── Fallback ─────────────────────────────────────────── */
        if (RTEST(d.text)) {
            ensure_paragraph();
            emit_span(rb_str_to_std(d.text), child_rp);
        }
        walk_children(d.children, child_rp);
    }

    void walk_children(VALUE children, const RunProps &rp) {
        if (!RB_TYPE_P(children, T_ARRAY)) return;
        long len = RARRAY_LEN(children);
        for (long i = 0; i < len; i++)
            walk(RARRAY_AREF(children, i), rp);
    }

    /* ── Table rendering (ODF) ────────────────────────────────── */

    void odt_walk_table(const NodeData &table_d, const RunProps &rp) {
        body_.open("table:table");

        if (RB_TYPE_P(table_d.children, T_ARRAY)) {
            long len = RARRAY_LEN(table_d.children);
            for (long i = 0; i < len; i++) {
                VALUE child = RARRAY_AREF(table_d.children, i);
                NodeData cd = read_node(child);
                std::string ctag = tag_str(cd.tag);
                if (ctag == "tr") {
                    odt_walk_row(cd, rp);
                } else if (ctag == "thead" || ctag == "tbody" || ctag == "tfoot") {
                    if (RB_TYPE_P(cd.children, T_ARRAY)) {
                        long clen = RARRAY_LEN(cd.children);
                        for (long j = 0; j < clen; j++) {
                            VALUE row = RARRAY_AREF(cd.children, j);
                            NodeData rd = read_node(row);
                            if (tag_str(rd.tag) == "tr")
                                odt_walk_row(rd, rp);
                        }
                    }
                }
            }
        }

        body_.close("table:table");
    }

    void odt_walk_row(const NodeData &row_d, const RunProps &rp) {
        body_.open("table:table-row");
        if (RB_TYPE_P(row_d.children, T_ARRAY)) {
            long len = RARRAY_LEN(row_d.children);
            for (long i = 0; i < len; i++) {
                VALUE child = RARRAY_AREF(row_d.children, i);
                NodeData cd = read_node(child);
                std::string ctag = tag_str(cd.tag);
                if (ctag == "td" || ctag == "th")
                    odt_walk_cell(cd, rp, ctag == "th");
            }
        }
        body_.close("table:table-row");
    }

    void odt_walk_cell(const NodeData &cell_d, const RunProps &rp, bool is_header) {
        body_.open_attr("table:table-cell")
             .attr("table:style-name", "nodex_tc");

        /* Colspan / rowspan */
        std::string colspan = get_attr(cell_d.attrs, "colspan");
        if (!colspan.empty()) {
            int span = 1;
            try { span = std::stoi(colspan); } catch (...) {}
            if (span > 1) body_.attr("table:number-columns-spanned", span);
        }
        std::string rowspan = get_attr(cell_d.attrs, "rowspan");
        if (!rowspan.empty()) {
            int span = 1;
            try { span = std::stoi(rowspan); } catch (...) {}
            if (span > 1) body_.attr("table:number-rows-spanned", span);
        }
        body_.end_open();

        RunProps cell_rp = compute_run_props(rp, cell_d.styles, is_header ? "th" : "td");
        if (is_header) cell_rp.bold = true;

        bool saved = in_paragraph_;
        in_paragraph_ = false;

        bool had_content = false;
        if (RTEST(cell_d.text)) {
            open_paragraph();
            emit_span(rb_str_to_std(cell_d.text), cell_rp);
            had_content = true;
        }
        if (RB_TYPE_P(cell_d.children, T_ARRAY)) {
            long len = RARRAY_LEN(cell_d.children);
            for (long i = 0; i < len; i++) {
                walk(RARRAY_AREF(cell_d.children, i), cell_rp);
                had_content = true;
            }
        }
        close_paragraph();

        if (!had_content)
            body_.raw("<text:p/>");

        body_.close("table:table-cell");
        in_paragraph_ = saved;
    }

    /* ── Image (ODF) ──────────────────────────────────────────── */

    void odt_emit_image(const std::string &src, VALUE attrs, VALUE styles) {
        std::string data;
        FILE *f = fopen(src.c_str(), "rb");
        if (f) {
            char buf[8192];
            size_t n;
            while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
                data.append(buf, n);
            fclose(f);
        }
        if (data.empty()) return;

        std::string ext = "png";
        if (src.size() > 4) {
            std::string tail = src.substr(src.size() - 4);
            std::transform(tail.begin(), tail.end(), tail.begin(), ::tolower);
            if (tail == ".jpg" || tail == "jpeg") ext = "jpeg";
        }

        std::string zip_path = "Pictures/image" + std::to_string(image_id_++) + "." + ext;
        images_.push_back({zip_path, std::move(data)});

        /* Default 10cm x 7.5cm */
        std::string width = "10cm", height = "7.5cm";
        /* HTML attrs */
        std::string w_str = get_attr(attrs, "width");
        std::string h_str = get_attr(attrs, "height");
        if (!w_str.empty()) { std::string v = css_to_cm(w_str); if (!v.empty()) width = v; }
        if (!h_str.empty()) { std::string v = css_to_cm(h_str); if (!v.empty()) height = v; }
        /* CSS styles override attrs */
        std::string sw = get_style(styles, "width");
        std::string sh = get_style(styles, "height");
        if (!sw.empty()) { std::string v = css_to_cm(sw); if (!v.empty()) width = v; }
        if (!sh.empty()) { std::string v = css_to_cm(sh); if (!v.empty()) height = v; }

        body_.open_attr("draw:frame")
             .attr("svg:width", width).attr("svg:height", height)
             .end_open();
        body_.open_attr("draw:image")
             .attr("xlink:href", zip_path)
             .attr("xlink:type", "simple")
             .attr("xlink:show", "embed")
             .attr("xlink:actuate", "onLoad")
             .self_close();
        body_.close("draw:frame");
    }

    /* compute_run_props is a shared free function (see above) */

    /* ── ODF boilerplate ──────────────────────────────────────── */

    std::string manifest_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("manifest:manifest")
         .attr("xmlns:manifest", "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0")
         .attr("manifest:version", "1.2")
         .end_open();
        w.open_attr("manifest:file-entry")
         .attr("manifest:media-type", "application/vnd.oasis.opendocument.text")
         .attr("manifest:full-path", "/").self_close();
        w.open_attr("manifest:file-entry")
         .attr("manifest:media-type", "text/xml")
         .attr("manifest:full-path", "content.xml").self_close();
        w.open_attr("manifest:file-entry")
         .attr("manifest:media-type", "text/xml")
         .attr("manifest:full-path", "styles.xml").self_close();
        for (auto &img : images_) {
            std::string mt = "image/png";
            if (img.first.find(".jpeg") != std::string::npos || img.first.find(".jpg") != std::string::npos)
                mt = "image/jpeg";
            w.open_attr("manifest:file-entry")
             .attr("manifest:media-type", mt)
             .attr("manifest:full-path", img.first).self_close();
        }
        w.close("manifest:manifest");
        return w.str();
    }

    std::string content_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("office:document-content")
         .attr("xmlns:office", "urn:oasis:names:tc:opendocument:xmlns:office:1.0")
         .attr("xmlns:text", "urn:oasis:names:tc:opendocument:xmlns:text:1.0")
         .attr("xmlns:table", "urn:oasis:names:tc:opendocument:xmlns:table:1.0")
         .attr("xmlns:draw", "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0")
         .attr("xmlns:fo", "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0")
         .attr("xmlns:xlink", "http://www.w3.org/1999/xlink")
         .attr("xmlns:style", "urn:oasis:names:tc:opendocument:xmlns:style:1.0")
         .attr("xmlns:svg", "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0")
         .attr("office:version", "1.2")
         .end_open();

        /* Automatic styles */
        w.open("office:automatic-styles");

        /* Default table cell style with borders */
        w.raw("<style:style style:name=\"nodex_tc\" style:family=\"table-cell\">"
              "<style:table-cell-properties fo:border=\"0.5pt solid #000000\" fo:padding=\"0.049cm\"/>"
              "</style:style>");

        for (auto &as : auto_styles_) {
            w.open_attr("style:style")
             .attr("style:name", as.name)
             .attr("style:family", as.family)
             .end_open();

            if (as.family == "paragraph") {
                bool has_pp = !as.alignment.empty() || !as.margin_top.empty() ||
                              !as.margin_bottom.empty() || !as.margin_left.empty() ||
                              !as.margin_right.empty() || !as.line_height.empty() ||
                              !as.text_indent.empty() || as.page_break_before;
                if (has_pp) {
                    w.open_attr("style:paragraph-properties");
                    if (!as.alignment.empty()) w.attr("fo:text-align", as.alignment);
                    if (!as.margin_top.empty()) w.attr("fo:margin-top", as.margin_top);
                    if (!as.margin_bottom.empty()) w.attr("fo:margin-bottom", as.margin_bottom);
                    if (!as.margin_left.empty()) w.attr("fo:margin-left", as.margin_left);
                    if (!as.margin_right.empty()) w.attr("fo:margin-right", as.margin_right);
                    if (!as.line_height.empty()) w.attr("fo:line-height", as.line_height);
                    if (!as.text_indent.empty()) w.attr("fo:text-indent", as.text_indent);
                    if (as.page_break_before) w.attr("fo:break-before", "page");
                    w.self_close();
                }
            }

            if (as.family == "text") {
                RunProps rp;
                rp.bold = as.bold; rp.italic = as.italic;
                rp.underline = as.underline; rp.strike = as.strike;
                rp.monospace = as.monospace;
                rp.color = as.color; rp.bg_color = as.bg_color;
                rp.font_size = as.font_size; rp.font_family = as.font_family;
                rp.letter_spacing = as.letter_spacing;
                write_text_props(w, rp);
            }

            w.close("style:style");
        }
        w.close("office:automatic-styles");

        /* Body */
        w.open("office:body");
        w.open("office:text");
        w.raw(body_.str());
        w.close("office:text");
        w.close("office:body");

        w.close("office:document-content");
        return w.str();
    }

    std::string odt_styles_xml() {
        XmlWriter w;
        w.decl();
        w.open_attr("office:document-styles")
         .attr("xmlns:office", "urn:oasis:names:tc:opendocument:xmlns:office:1.0")
         .attr("xmlns:style", "urn:oasis:names:tc:opendocument:xmlns:style:1.0")
         .attr("xmlns:fo", "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0")
         .attr("xmlns:text", "urn:oasis:names:tc:opendocument:xmlns:text:1.0")
         .attr("office:version", "1.2")
         .end_open();

        w.open("office:styles");

        /* Default paragraph style */
        std::string odt_def_font = doc_config_.default_font.empty() ? "Calibri" : doc_config_.default_font;
        std::string odt_def_size = "11pt";
        if (!doc_config_.default_font_size.empty()) {
            int hp = std::stoi(doc_config_.default_font_size);
            odt_def_size = std::to_string(hp / 2) + "pt";
        }
        w.open_attr("style:default-style")
         .attr("style:family", "paragraph").end_open();
        w.open_attr("style:text-properties")
         .attr("style:font-name", odt_def_font)
         .attr("fo:font-size", odt_def_size).self_close();
        w.close("style:default-style");

        /* Heading styles */
        for (int i = 1; i <= 6; i++) {
            std::string name = "Heading_20_" + std::to_string(i);
            int pt_sizes[] = {0, 24, 18, 14, 12, 11, 10};
            w.open_attr("style:style")
             .attr("style:name", name)
             .attr("style:family", "paragraph")
             .attr("style:display-name", "Heading " + std::to_string(i))
             .end_open();
            w.open_attr("style:paragraph-properties")
             .attr("fo:margin-top", "0.4cm").attr("fo:margin-bottom", "0.2cm").self_close();
            w.open_attr("style:text-properties")
             .attr("fo:font-weight", "bold")
             .attr("fo:font-size", std::to_string(pt_sizes[i]) + "pt").self_close();
            w.close("style:style");
        }

        /* List styles */
        w.open_attr("text:list-style").attr("style:name", "L1").end_open();
        for (int i = 1; i <= 4; i++) {
            w.open_attr("text:list-level-style-bullet")
             .attr("text:level", i)
             .attr("text:bullet-char", i == 1 ? "\xE2\x80\xA2" : "\xE2\x97\xA6")
             .end_open();
            w.close("text:list-level-style-bullet");
        }
        w.close("text:list-style");

        w.close("office:styles");

        /* Page layout — automatic styles section */
        w.open("office:automatic-styles");
        auto twips_to_cm = [](int tw) -> std::string {
            double cm = tw / 1440.0 * 2.54;
            std::ostringstream oss;
            oss << cm << "cm";
            return oss.str();
        };
        w.open_attr("style:page-layout")
         .attr("style:name", "pm1").end_open();
        w.open_attr("style:page-layout-properties")
         .attr("fo:page-width", twips_to_cm(page_config_.width_twips))
         .attr("fo:page-height", twips_to_cm(page_config_.height_twips))
         .attr("fo:margin-top", twips_to_cm(page_config_.margin_top))
         .attr("fo:margin-bottom", twips_to_cm(page_config_.margin_bottom))
         .attr("fo:margin-left", twips_to_cm(page_config_.margin_left))
         .attr("fo:margin-right", twips_to_cm(page_config_.margin_right))
         .self_close();
        w.close("style:page-layout");
        w.close("office:automatic-styles");

        /* Master pages */
        w.open("office:master-styles");
        bool has_hf = !doc_config_.header_text.empty() || !doc_config_.footer_text.empty() ||
                       doc_config_.page_numbers || !doc_config_.first_page_footer.empty();
        if (has_hf) {
            w.open_attr("style:master-page")
             .attr("style:name", "Default")
             .attr("style:page-layout-name", "pm1")
             .end_open();
            if (!doc_config_.header_text.empty()) {
                w.open("style:header");
                w.open("text:p");
                w.text(doc_config_.header_text);
                w.close("text:p");
                w.close("style:header");
            }
            if (!doc_config_.footer_text.empty() || doc_config_.page_numbers) {
                w.open("style:footer");
                w.open("text:p");
                if (!doc_config_.footer_text.empty())
                    w.text(doc_config_.footer_text);
                if (doc_config_.page_numbers) {
                    if (!doc_config_.footer_text.empty())
                        w.text(" ");
                    w.raw("<text:page-number text:select-page=\"current\">1</text:page-number>");
                }
                w.close("text:p");
                w.close("style:footer");
            }
            if (!doc_config_.first_page_footer.empty()) {
                w.open("style:footer-first");
                w.open("text:p");
                w.text(doc_config_.first_page_footer);
                w.close("text:p");
                w.close("style:footer-first");
            }
            w.close("style:master-page");
        } else {
            w.open_attr("style:master-page")
             .attr("style:name", "Default")
             .attr("style:page-layout-name", "pm1")
             .self_close();
        }
        w.close("office:master-styles");

        w.close("office:document-styles");
        return w.str();
    }
};

/* ══════════════════════════════════════════════════════════════════
 *  Ruby bindings
 * ══════════════════════════════════════════════════════════════════ */

static VALUE native_render_docx(int argc, VALUE *argv, VALUE mod) {
    VALUE node, opts;
    rb_scan_args(argc, argv, "11", &node, &opts);
    DocxRenderer renderer;
    std::string zip_data = renderer.render(node, opts);
    return rb_enc_str_new(zip_data.data(), static_cast<long>(zip_data.size()),
                          rb_ascii8bit_encoding());
}

static VALUE native_render_odt(int argc, VALUE *argv, VALUE mod) {
    VALUE node, opts;
    rb_scan_args(argc, argv, "11", &node, &opts);
    OdtRenderer renderer;
    std::string zip_data = renderer.render(node, opts);
    return rb_enc_str_new(zip_data.data(), static_cast<long>(zip_data.size()),
                          rb_ascii8bit_encoding());
}

/* ══════════════════════════════════════════════════════════════════
 *  Init (called from Init_nodex_native)
 * ══════════════════════════════════════════════════════════════════ */

extern "C" void Init_nodex_docx(void) {
    crc32_init();

    VALUE mNodex = rb_const_get(rb_cObject, rb_intern("Nodex"));
    VALUE mDocx = rb_define_module_under(mNodex, "NativeDocx");

    rb_define_module_function(mDocx, "render_docx",
        reinterpret_cast<VALUE (*)(...)>(native_render_docx), -1);
    rb_define_module_function(mDocx, "render_odt",
        reinterpret_cast<VALUE (*)(...)>(native_render_odt), -1);
}
