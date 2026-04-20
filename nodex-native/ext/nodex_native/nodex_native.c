/*
 * nodex_native.c — C extension for Nodex HTML rendering.
 *
 * Three rendering modes:
 *   1. to_html_native — walks Nodex::Node tree, renders HTML
 *   2. Render cache   — @_html_cache ivar, O(1) return on cache hit
 *   3. Baked templates — pre-compiled string templates with slots
 *
 * Key optimizations:
 *   - ROBJECT_IVPTR for O(1) ivar access (vs rb_ivar_get shape walk)
 *   - Raw C char buffer with reuse (no malloc after warmup)
 *   - 256-byte lookup table for HTML escape
 *   - rb_hash_foreach for styles/attrs (zero temporary allocations)
 *   - Pure C void element check (switch on tag length)
 */

#include <ruby.h>
#include <ruby/encoding.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>

/* ── Cached IDs (shared with nodex_docx.cpp via extern) ─────────── */

ID id_tag, id_text, id_raw_html, id_attrs, id_styles;
ID id_classes, id_id, id_children;
ID id_html_cache;

VALUE sym_text_node;
rb_encoding *enc_utf8;

/* ── Direct ivar access (always via rb_ivar_get for GC safety) ── */

/* ── Reusable C buffer (per-thread for thread safety) ─────────── */

typedef struct {
    char *ptr;
    size_t len;
    size_t cap;
} cbuf_t;

static __thread char  *tl_buf_ptr = NULL;
static __thread size_t tl_buf_cap = 0;

static void cbuf_grow(cbuf_t *b, size_t need) {
    size_t req = b->len + need;
    size_t nc = b->cap;
    do { nc <<= 1; } while (nc < req);
    b->ptr = (char *)realloc(b->ptr, nc);
    b->cap = nc;
}

static inline void cbuf_cat(cbuf_t *b, const char *s, size_t n) {
    if (__builtin_expect(b->len + n > b->cap, 0))
        cbuf_grow(b, n);
    memcpy(b->ptr + b->len, s, n);
    b->len += n;
}

static inline void cbuf_char(cbuf_t *b, char c) {
    if (__builtin_expect(b->len >= b->cap, 0))
        cbuf_grow(b, 1);
    b->ptr[b->len++] = c;
}

#define CBUF_LIT(b, lit) cbuf_cat((b), (lit), sizeof(lit) - 1)

/* ── HTML escape ────────────────────────────────────────────────── */

static unsigned char esc_flag[256];
static const char *esc_repl[256];
static unsigned char esc_rlen[256];

static void init_escape_table(void) {
    memset(esc_flag, 0, sizeof(esc_flag));
    memset(esc_repl, 0, sizeof(esc_repl));
    memset(esc_rlen, 0, sizeof(esc_rlen));
    esc_flag['&']  = 1; esc_repl['&']  = "&amp;";  esc_rlen['&']  = 5;
    esc_flag['<']  = 1; esc_repl['<']  = "&lt;";   esc_rlen['<']  = 4;
    esc_flag['>']  = 1; esc_repl['>']  = "&gt;";   esc_rlen['>']  = 4;
    esc_flag['"']  = 1; esc_repl['"']  = "&quot;"; esc_rlen['"']  = 6;
    esc_flag['\''] = 1; esc_repl['\''] = "&#39;";  esc_rlen['\''] = 5;
}

static void cbuf_escaped(cbuf_t *b, const char *ptr, long len) {
    const char *end = ptr + len;
    while (ptr < end) {
        const char *safe = ptr;
        while (ptr < end && !esc_flag[(unsigned char)*ptr])
            ptr++;
        if (ptr > safe)
            cbuf_cat(b, safe, (size_t)(ptr - safe));
        if (ptr < end) {
            unsigned char c = (unsigned char)*ptr++;
            cbuf_cat(b, esc_repl[c], esc_rlen[c]);
        }
    }
}

static inline void cbuf_esc_rv(cbuf_t *b, VALUE str) {
    cbuf_escaped(b, RSTRING_PTR(str), RSTRING_LEN(str));
}

/* ── Opcode renderer (PackedBuilder) ──────────────────────────── */

#define MAX_DEPTH 64
#define MAX_CLS   8
#define MAX_STY  16
#define MAX_ATTR 16

typedef struct {
    const char *tag;     size_t tag_len;
    const char *id;      size_t id_len;
    const char *cls[MAX_CLS];   size_t cls_len[MAX_CLS];   int n_cls;
    const char *sk[MAX_STY];    size_t skl[MAX_STY];
    const char *sv[MAX_STY];    size_t svl[MAX_STY];       int n_sty;
    const char *ak[MAX_ATTR];   size_t akl[MAX_ATTR];
    const char *av[MAX_ATTR];   size_t avl[MAX_ATTR];      int n_attr;
    int flushed;
} elem_state_t;

static void flush_open_tag(cbuf_t *b, elem_state_t *e) {
    if (e->flushed) return;
    e->flushed = 1;

    cbuf_char(b, '<');
    cbuf_cat(b, e->tag, e->tag_len);

    if (e->id) {
        CBUF_LIT(b, " id=\"");
        cbuf_escaped(b, e->id, (long)e->id_len);
        cbuf_char(b, '"');
    }
    if (e->n_cls > 0) {
        CBUF_LIT(b, " class=\"");
        for (int i = 0; i < e->n_cls; i++) {
            if (i > 0) cbuf_char(b, ' ');
            cbuf_escaped(b, e->cls[i], (long)e->cls_len[i]);
        }
        cbuf_char(b, '"');
    }
    if (e->n_sty > 0) {
        CBUF_LIT(b, " style=\"");
        for (int i = 0; i < e->n_sty; i++) {
            if (i > 0) CBUF_LIT(b, "; ");
            cbuf_escaped(b, e->sk[i], (long)e->skl[i]);
            CBUF_LIT(b, ": ");
            cbuf_escaped(b, e->sv[i], (long)e->svl[i]);
        }
        cbuf_char(b, '"');
    }
    for (int i = 0; i < e->n_attr; i++) {
        cbuf_char(b, ' ');
        cbuf_cat(b, e->ak[i], e->akl[i]);
        CBUF_LIT(b, "=\"");
        cbuf_escaped(b, e->av[i], (long)e->avl[i]);
        cbuf_char(b, '"');
    }
    cbuf_char(b, '>');
}

static inline uint16_t read_u16(const uint8_t **pp) {
    uint16_t v;
    memcpy(&v, *pp, 2);
    *pp += 2;
    return v;
}

static VALUE native_render_opcodes(VALUE mod, VALUE opcodes_str) {
    Check_Type(opcodes_str, T_STRING);
    const uint8_t *p   = (const uint8_t *)RSTRING_PTR(opcodes_str);
    const uint8_t *end = p + RSTRING_LEN(opcodes_str);

    /* Per-call local stack — each render is independent */
    elem_state_t stack[MAX_DEPTH];
    int depth = 0;

    cbuf_t buf;
    if (tl_buf_ptr) {
        buf.ptr = tl_buf_ptr;
        buf.cap = tl_buf_cap;
    } else {
        buf.ptr = (char *)malloc(131072);
        buf.cap = 131072;
    }
    buf.len = 0;

    while (p < end) {
        uint8_t op = *p++;
        switch (op) {
        case 0x01: { /* OPEN */
            if (depth > 0) flush_open_tag(&buf, &stack[depth-1]);
            uint16_t tl = read_u16(&p);
            if (depth >= MAX_DEPTH) rb_raise(rb_eRuntimeError, "opcode nesting too deep");
            elem_state_t *e = &stack[depth++];
            memset(e, 0, sizeof(*e));
            e->tag = (const char*)p; e->tag_len = tl;
            p += tl;
            break;
        }
        case 0x02: { /* CLOSE */
            if (depth <= 0) rb_raise(rb_eRuntimeError, "opcode CLOSE without matching OPEN");
            elem_state_t *e = &stack[--depth];
            flush_open_tag(&buf, e);
            CBUF_LIT(&buf, "</");
            cbuf_cat(&buf, e->tag, e->tag_len);
            cbuf_char(&buf, '>');
            break;
        }
        case 0x03: { /* TEXT */
            if (depth > 0) flush_open_tag(&buf, &stack[depth-1]);
            uint16_t len = read_u16(&p);
            cbuf_escaped(&buf, (const char*)p, len);
            p += len;
            break;
        }
        case 0x04: { /* RAW */
            if (depth > 0) flush_open_tag(&buf, &stack[depth-1]);
            uint16_t len = read_u16(&p);
            cbuf_cat(&buf, (const char*)p, len);
            p += len;
            break;
        }
        case 0x05: { /* ATTR */
            uint16_t kl = read_u16(&p);
            const char *k = (const char*)p; p += kl;
            uint16_t vl = read_u16(&p);
            const char *v = (const char*)p; p += vl;
            if (depth > 0) {
                elem_state_t *e = &stack[depth-1];
                if (e->n_attr < MAX_ATTR) {
                    int i = e->n_attr++;
                    e->ak[i]=k; e->akl[i]=kl;
                    e->av[i]=v; e->avl[i]=vl;
                }
            }
            break;
        }
        case 0x06: { /* CLASS */
            uint16_t len = read_u16(&p);
            if (depth > 0) {
                elem_state_t *e = &stack[depth-1];
                if (e->n_cls < MAX_CLS) {
                    int i = e->n_cls++;
                    e->cls[i]=(const char*)p; e->cls_len[i]=len;
                }
            }
            p += len;
            break;
        }
        case 0x07: { /* SETID */
            uint16_t len = read_u16(&p);
            if (depth > 0) {
                elem_state_t *e = &stack[depth-1];
                e->id = (const char*)p; e->id_len = len;
            }
            p += len;
            break;
        }
        case 0x08: { /* STYLE */
            uint16_t kl = read_u16(&p);
            const char *k = (const char*)p; p += kl;
            uint16_t vl = read_u16(&p);
            const char *v = (const char*)p; p += vl;
            if (depth > 0) {
                elem_state_t *e = &stack[depth-1];
                if (e->n_sty < MAX_STY) {
                    int i = e->n_sty++;
                    e->sk[i]=k; e->skl[i]=kl;
                    e->sv[i]=v; e->svl[i]=vl;
                }
            }
            break;
        }
        case 0x09: { /* VCLOSE (void element) */
            if (depth <= 0) rb_raise(rb_eRuntimeError, "opcode VCLOSE without matching OPEN");
            elem_state_t *e = &stack[--depth];
            flush_open_tag(&buf, e);
            break;
        }
        case 0x0A: { /* DOCTYPE */
            if (depth > 0) flush_open_tag(&buf, &stack[depth-1]);
            CBUF_LIT(&buf, "<!DOCTYPE html>\n");
            break;
        }
        default:
            rb_raise(rb_eRuntimeError, "unknown opcode 0x%02x", op);
        }
    }

    VALUE result = rb_enc_str_new(buf.ptr, (long)buf.len, enc_utf8);
    tl_buf_ptr = buf.ptr;
    tl_buf_cap = buf.cap;
    return result;
}

/* ── Void elements — pure C ───────────────────────────────────── */

static inline int is_void_tag(const char *t, long n) {
    switch (n) {
    case 2: return (t[0]=='b'&&t[1]=='r') || (t[0]=='h'&&t[1]=='r');
    case 3: return !memcmp(t,"col",3)||!memcmp(t,"img",3)||!memcmp(t,"wbr",3);
    case 4: return !memcmp(t,"area",4)||!memcmp(t,"base",4)||
                   !memcmp(t,"link",4)||!memcmp(t,"meta",4);
    case 5: return !memcmp(t,"embed",5)||!memcmp(t,"input",5)||
                   !memcmp(t,"param",5)||!memcmp(t,"track",5);
    case 6: return !memcmp(t,"source",6);
    default: return 0;
    }
}

/* ── Hash callbacks ─────────────────────────────────────────────── */

struct style_ctx { cbuf_t *b; int first; };

static int style_cb(VALUE key, VALUE val, VALUE arg) {
    struct style_ctx *ctx = (struct style_ctx *)arg;
    cbuf_t *b = ctx->b;
    if (!ctx->first) CBUF_LIT(b, "; ");
    ctx->first = 0;
    cbuf_esc_rv(b, key);
    CBUF_LIT(b, ": ");
    cbuf_esc_rv(b, val);
    return ST_CONTINUE;
}

static int attr_cb(VALUE key, VALUE val, VALUE arg) {
    cbuf_t *b = (cbuf_t *)arg;
    cbuf_char(b, ' ');
    cbuf_cat(b, RSTRING_PTR(key), RSTRING_LEN(key));
    CBUF_LIT(b, "=\"");
    cbuf_esc_rv(b, val);
    cbuf_char(b, '"');
    return ST_CONTINUE;
}

/* ── Subtree cache helper ────────────────────────────────────────── */

static inline void _cache_subtree(VALUE node, cbuf_t *b, size_t start) {
    size_t len = b->len - start;
    VALUE html = rb_enc_str_new(b->ptr + start, (long)len, enc_utf8);
    rb_ivar_set(node, id_html_cache, html);
}

/* ── Iterative render (explicit stack, no recursion) ─────────────── */

#define MAX_RENDER_DEPTH 256

static void render_node(cbuf_t *b, VALUE root) {
    struct {
        VALUE children;
        VALUE node;          /* the node being rendered */
        const char *tag;
        long tag_len;
        long idx, count;
        size_t html_start;   /* buffer position at node entry */
    } stk[MAX_RENDER_DEPTH];
    int sp = 0;
    int entering = 1;
    VALUE cur = root;
    int node_count = 0;

    for (;;) {
        /* Yield to other threads periodically during large renders */
        if (++node_count % 512 == 0)
            rb_thread_check_ints();
        if (entering) {
            /* Subtree cache check — emit cached HTML directly */
            VALUE child_cache = rb_ivar_get(cur, id_html_cache);
            if (RB_TYPE_P(child_cache, T_STRING)) {
                cbuf_cat(b, RSTRING_PTR(child_cache), RSTRING_LEN(child_cache));
                entering = 0;
                continue;
            }

            size_t html_start = b->len;  /* record for caching later */

            VALUE tag, text, raw_html, node_id, classes, styles, attrs, children;

            tag      = rb_ivar_get(cur, id_tag);
            text     = rb_ivar_get(cur, id_text);
            raw_html = rb_ivar_get(cur, id_raw_html);
            attrs    = rb_ivar_get(cur, id_attrs);
            styles   = rb_ivar_get(cur, id_styles);
            classes  = rb_ivar_get(cur, id_classes);
            node_id  = rb_ivar_get(cur, id_id);
            children = rb_ivar_get(cur, id_children);

            /* Raw HTML — verbatim (trivially cheap, skip caching) */
            if (RTEST(raw_html)) {
                cbuf_cat(b, RSTRING_PTR(raw_html), RSTRING_LEN(raw_html));
                entering = 0;
                continue;
            }

            /* Text node — escape (trivially cheap, skip caching) */
            if (tag == sym_text_node) {
                if (RTEST(text))
                    cbuf_esc_rv(b, text);
                entering = 0;
                continue;
            }

            const char *tp = RSTRING_PTR(tag);
            long tl = RSTRING_LEN(tag);

            /* DOCTYPE */
            if (tl == 4 && memcmp(tp, "html", 4) == 0)
                CBUF_LIT(b, "<!DOCTYPE html>\n");

            /* <tag */
            cbuf_char(b, '<');
            cbuf_cat(b, tp, (size_t)tl);

            /* id="..." */
            if (RTEST(node_id)) {
                CBUF_LIT(b, " id=\"");
                cbuf_esc_rv(b, node_id);
                cbuf_char(b, '"');
            }

            /* class="cls1 cls2" */
            if (RB_TYPE_P(classes, T_ARRAY)) {
                long cnt = RARRAY_LEN(classes);
                if (cnt > 0) {
                    CBUF_LIT(b, " class=\"");
                    for (long i = 0; i < cnt; i++) {
                        if (i > 0) cbuf_char(b, ' ');
                        cbuf_esc_rv(b, RARRAY_AREF(classes, i));
                    }
                    cbuf_char(b, '"');
                }
            }

            /* style="k: v; k: v" */
            if (RB_TYPE_P(styles, T_HASH) && RHASH_SIZE(styles) > 0) {
                CBUF_LIT(b, " style=\"");
                struct style_ctx sctx = { b, 1 };
                rb_hash_foreach(styles, style_cb, (VALUE)&sctx);
                cbuf_char(b, '"');
            }

            /* attributes */
            if (RB_TYPE_P(attrs, T_HASH) && RHASH_SIZE(attrs) > 0)
                rb_hash_foreach(attrs, attr_cb, (VALUE)b);

            /* Void element */
            if (is_void_tag(tp, tl)) {
                cbuf_char(b, '>');
                _cache_subtree(cur, b, html_start);
                entering = 0;
                continue;
            }

            /* > + text */
            cbuf_char(b, '>');
            if (RTEST(text))
                cbuf_esc_rv(b, text);

            long child_count = NIL_P(children) ? 0 : RARRAY_LEN(children);
            if (child_count == 0) {
                CBUF_LIT(b, "</");
                cbuf_cat(b, tp, (size_t)tl);
                cbuf_char(b, '>');
                _cache_subtree(cur, b, html_start);
                entering = 0;
                continue;
            }

            /* Push frame for children */
            if (sp >= MAX_RENDER_DEPTH)
                rb_raise(rb_eRuntimeError, "render tree too deep (max %d)", MAX_RENDER_DEPTH);
            stk[sp].children = children;
            stk[sp].node = cur;
            stk[sp].tag = tp;
            stk[sp].tag_len = tl;
            stk[sp].idx = 0;
            stk[sp].count = child_count;
            stk[sp].html_start = html_start;
            sp++;

            cur = RARRAY_AREF(children, 0);
            /* entering stays 1 */
        } else {
            /* Advance to next child or pop */
            if (sp == 0) return;

            stk[sp - 1].idx++;
            if (stk[sp - 1].idx < stk[sp - 1].count) {
                cur = RARRAY_AREF(stk[sp - 1].children, stk[sp - 1].idx);
                entering = 1;
            } else {
                /* Close tag */
                sp--;
                CBUF_LIT(b, "</");
                cbuf_cat(b, stk[sp].tag, (size_t)stk[sp].tag_len);
                cbuf_char(b, '>');
                /* Cache this subtree */
                _cache_subtree(stk[sp].node, b, stk[sp].html_start);
                /* entering stays 0 — keep popping */
            }
        }
    }
}

/* ── Ruby entry point ───────────────────────────────────────────── */

static VALUE nodex_native_to_html(VALUE self) {
    /* Check render cache — O(1) return if cached */
    VALUE cached = rb_ivar_get(self, id_html_cache);
    if (RB_TYPE_P(cached, T_STRING))
        return cached;

    cbuf_t buf;

    /* Reuse per-thread buffer from previous call */
    if (tl_buf_ptr) {
        buf.ptr = tl_buf_ptr;
        buf.cap = tl_buf_cap;
    } else {
        buf.ptr = (char *)malloc(131072);
        buf.cap = 131072;
    }
    buf.len = 0;

    render_node(&buf, self);

    /* render_node already cached the root for non-leaf nodes */
    cached = rb_ivar_get(self, id_html_cache);
    if (RB_TYPE_P(cached, T_STRING)) {
        tl_buf_ptr = buf.ptr;
        tl_buf_cap = buf.cap;
        return cached;
    }

    /* Fallback for raw/text root nodes (not cached by render_node) */
    VALUE result = rb_enc_str_new(buf.ptr, (long)buf.len, enc_utf8);

    tl_buf_ptr = buf.ptr;
    tl_buf_cap = buf.cap;

    rb_ivar_set(self, id_html_cache, result);

    return result;
}

/* ── Baked templates (dynamic array + mutex) ──────────────────── */

typedef struct {
    VALUE name_sym;            /* Ruby symbol key */
    char  **chunks;            /* dynamic array [n_slots+1] */
    size_t *chunk_lens;        /* dynamic array [n_slots+1] */
    VALUE  *slot_syms;         /* dynamic array [n_slots] */
    int n_slots;
    int valid;
} baked_t;

static pthread_mutex_t baked_mutex = PTHREAD_MUTEX_INITIALIZER;
static baked_t *g_baked = NULL;
static int g_baked_count = 0;
static int g_baked_cap   = 0;

/* GC mark all baked template Ruby values (GC runs single-threaded, no lock needed) */
static void baked_mark(void *_unused) {
    (void)_unused;
    int count = g_baked_count;
    for (int i = 0; i < count; i++) {
        if (!g_baked[i].valid) continue;
        rb_gc_mark(g_baked[i].name_sym);
        for (int j = 0; j < g_baked[i].n_slots; j++)
            rb_gc_mark(g_baked[i].slot_syms[j]);
    }
}

/*
 * register_baked(name_sym, chunks_array, slot_names_array)
 *
 * chunks_array: Array of Strings — static HTML parts
 * slot_names_array: Array of Symbols — slot names (len = chunks.len - 1)
 */
static VALUE native_register_baked(VALUE mod, VALUE name_sym,
                                   VALUE chunks_ary, VALUE slots_ary)
{
    int n_chunks = (int)RARRAY_LEN(chunks_ary);
    int n_slots  = (int)RARRAY_LEN(slots_ary);

    if (n_chunks != n_slots + 1)
        rb_raise(rb_eArgError, "chunks.length must equal slots.length + 1");

    pthread_mutex_lock(&baked_mutex);

    /* Check if template name already exists — overwrite */
    baked_t *tmpl = NULL;
    for (int i = 0; i < g_baked_count; i++) {
        if (g_baked[i].valid && g_baked[i].name_sym == name_sym) {
            /* Free old dynamic arrays */
            for (int j = 0; j <= g_baked[i].n_slots; j++)
                free(g_baked[i].chunks[j]);
            free(g_baked[i].chunks);
            free(g_baked[i].chunk_lens);
            free(g_baked[i].slot_syms);
            tmpl = &g_baked[i];
            break;
        }
    }
    if (!tmpl) {
        /* Grow array if needed */
        if (g_baked_count >= g_baked_cap) {
            int new_cap = g_baked_cap == 0 ? 32 : g_baked_cap * 2;
            g_baked = (baked_t *)realloc(g_baked, (size_t)new_cap * sizeof(baked_t));
            g_baked_cap = new_cap;
        }
        tmpl = &g_baked[g_baked_count++];
    }

    tmpl->name_sym = name_sym;
    tmpl->n_slots = n_slots;
    tmpl->valid = 1;

    /* Allocate dynamic arrays for chunks and slots */
    tmpl->chunks     = (char **)malloc((size_t)(n_slots + 1) * sizeof(char *));
    tmpl->chunk_lens = (size_t *)malloc((size_t)(n_slots + 1) * sizeof(size_t));
    tmpl->slot_syms  = n_slots > 0
        ? (VALUE *)malloc((size_t)n_slots * sizeof(VALUE))
        : NULL;

    /* Copy static chunks into C-owned memory */
    for (int i = 0; i < n_chunks; i++) {
        VALUE s = RARRAY_AREF(chunks_ary, i);
        size_t len = (size_t)RSTRING_LEN(s);
        tmpl->chunks[i] = (char *)malloc(len);
        memcpy(tmpl->chunks[i], RSTRING_PTR(s), len);
        tmpl->chunk_lens[i] = len;
    }

    /* Store slot symbols */
    for (int i = 0; i < n_slots; i++)
        tmpl->slot_syms[i] = RARRAY_AREF(slots_ary, i);

    pthread_mutex_unlock(&baked_mutex);
    return Qtrue;
}

/*
 * render_baked(name_sym, params_hash) → String
 *
 * Renders a baked template by interleaving static chunks with
 * HTML-escaped parameter values. No Ruby objects created except result.
 */
static VALUE native_render_baked(VALUE mod, VALUE name_sym, VALUE params) {
    /* Find template (read-only after registration; atomic load for count) */
    baked_t *tmpl = NULL;
    int count = __atomic_load_n(&g_baked_count, __ATOMIC_ACQUIRE);
    for (int i = 0; i < count; i++) {
        if (g_baked[i].valid && g_baked[i].name_sym == name_sym) {
            tmpl = &g_baked[i];
            break;
        }
    }
    if (!tmpl)
        rb_raise(rb_eKeyError, "Baked template not found");

    cbuf_t buf;
    if (tl_buf_ptr) {
        buf.ptr = tl_buf_ptr;
        buf.cap = tl_buf_cap;
    } else {
        buf.ptr = (char *)malloc(131072);
        buf.cap = 131072;
    }
    buf.len = 0;

    /* Interleave chunks and escaped slot values */
    for (int i = 0; i <= tmpl->n_slots; i++) {
        /* Static chunk */
        cbuf_cat(&buf, tmpl->chunks[i], tmpl->chunk_lens[i]);

        /* Slot value (except after last chunk) */
        if (i < tmpl->n_slots) {
            VALUE val = rb_hash_aref(params, tmpl->slot_syms[i]);
            if (RB_TYPE_P(val, T_STRING)) {
                cbuf_esc_rv(&buf, val);
            } else if (RTEST(val)) {
                VALUE s = rb_funcall(val, rb_intern("to_s"), 0);
                cbuf_esc_rv(&buf, s);
            }
        }
    }

    VALUE result = rb_enc_str_new(buf.ptr, (long)buf.len, enc_utf8);
    tl_buf_ptr = buf.ptr;
    tl_buf_cap = buf.cap;
    return result;
}

/* ── Ivar layout detection ──────────────────────────────────────── */

static void detect_ivar_layout(VALUE cNode) {
    VALUE test = rb_funcall(cNode, rb_intern("new"), 1,
                            rb_str_new_cstr("__detect__"));
    if (!RB_TYPE_P(test, T_OBJECT)) return;

    VALUE *ivptr = ROBJECT_IVPTR(test);

    /* With nil-init optimization, @attrs/@styles/@classes/@children start as nil */
    if (RB_TYPE_P(ivptr[0], T_STRING) &&
        RSTRING_LEN(ivptr[0]) == 10 &&
        memcmp(RSTRING_PTR(ivptr[0]), "__detect__", 10) == 0 &&
        NIL_P(ivptr[1]) &&
        NIL_P(ivptr[2]) &&
        NIL_P(ivptr[3]) &&
        NIL_P(ivptr[4]) &&
        NIL_P(ivptr[5]) &&
        NIL_P(ivptr[6]) &&
        NIL_P(ivptr[7]))
    {
        direct_ok = 1;
    }
}

/* ── Inja bindings (nodex_inja.cpp) ──────────────────────────────── */

extern void Init_nodex_inja(void);

/* ── DOCX/ODT bindings (nodex_docx.cpp) ─────────────────────────── */

extern void Init_nodex_docx(void);

/* ── Init ───────────────────────────────────────────────────────── */

void Init_nodex_native(void) {
    init_escape_table();

    id_tag      = rb_intern("@tag");
    id_text     = rb_intern("@text");
    id_raw_html = rb_intern("@raw_html");
    id_attrs    = rb_intern("@attrs");
    id_styles   = rb_intern("@styles");
    id_classes  = rb_intern("@classes");
    id_id       = rb_intern("@id");
    id_children    = rb_intern("@children");
    id_html_cache  = rb_intern("@_html_cache");

    sym_text_node = ID2SYM(rb_intern("text_node"));
    rb_gc_register_address(&sym_text_node);

    enc_utf8 = rb_utf8_encoding();

    VALUE mNodex = rb_const_get(rb_cObject, rb_intern("Nodex"));
    VALUE cNode = rb_const_get(mNodex, rb_intern("Node"));

    detect_ivar_layout(cNode);

    rb_define_method(cNode, "to_html_native", nodex_native_to_html, 0);

    /* Baked templates module methods */
    VALUE mNative = rb_define_module_under(mNodex, "NativeBaked");
    rb_define_module_function(mNative, "register_baked", native_register_baked, 3);
    rb_define_module_function(mNative, "render_baked", native_render_baked, 2);
    rb_define_module_function(mNative, "render_opcodes", native_render_opcodes, 1);

    /* Register GC marker for baked template Ruby values */
    static const rb_data_type_t baked_gc_type = {
        .wrap_struct_name = "nodex_baked_gc",
        .function = { .dmark = baked_mark, .dfree = NULL, .dsize = NULL },
        .flags = RUBY_TYPED_FREE_IMMEDIATELY,
    };
    VALUE gc_guard = TypedData_Wrap_Struct(rb_cObject, &baked_gc_type, NULL);
    rb_gc_register_address(&gc_guard);

    /* Initialize Inja template bindings */
    Init_nodex_inja();

    /* Initialize DOCX/ODT export bindings */
    Init_nodex_docx();
}