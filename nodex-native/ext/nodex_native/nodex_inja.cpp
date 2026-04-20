/*
 * nodex_inja.cpp — Inja template engine bindings for nodex-native.
 *
 * Provides:
 *   Nodex::Native.render_template(template_str, data_hash) → String
 *   Nodex::Native.render_template_file(path, data_hash)    → String
 *   Nodex::Native.set_template_directory(dir)
 *
 * Uses vendored inja.hpp (header-only) + nlohmann/json.hpp.
 */

#include <ruby.h>
#include <ruby/encoding.h>
#include <mutex>
#include <shared_mutex>

#include "vendor/nlohmann/json.hpp"
#include "vendor/inja.hpp"

using json = nlohmann::json;

static std::string g_template_dir;
static std::shared_mutex dir_mutex;
static rb_encoding *inja_enc_utf8;

/* ── Ruby Hash → nlohmann::json conversion ────────────────────────── */

static json rb_to_json(VALUE obj);

static int hash_to_json_cb(VALUE key, VALUE val, VALUE arg) {
    json *j = reinterpret_cast<json *>(arg);
    std::string k;

    if (RB_TYPE_P(key, T_SYMBOL)) {
        VALUE s = rb_sym2str(key);
        k = std::string(RSTRING_PTR(s), RSTRING_LEN(s));
    } else {
        VALUE s = rb_String(key);
        k = std::string(RSTRING_PTR(s), RSTRING_LEN(s));
    }

    (*j)[k] = rb_to_json(val);
    return ST_CONTINUE;
}

/* Wrapper to silence deprecated ANYARGS warning in C++ */
static int hash_foreach_wrapper(VALUE key, VALUE val, VALUE arg) {
    return hash_to_json_cb(key, val, arg);
}

static json rb_to_json(VALUE obj) {
    switch (TYPE(obj)) {
    case T_NIL:
        return nullptr;
    case T_TRUE:
        return true;
    case T_FALSE:
        return false;
    case T_FIXNUM:
        return FIX2LONG(obj);
    case T_FLOAT:
        return RFLOAT_VALUE(obj);
    case T_BIGNUM:
        return rb_big2dbl(obj);
    case T_STRING:
        return std::string(RSTRING_PTR(obj), RSTRING_LEN(obj));
    case T_SYMBOL: {
        VALUE s = rb_sym2str(obj);
        return std::string(RSTRING_PTR(s), RSTRING_LEN(s));
    }
    case T_ARRAY: {
        json arr = json::array();
        long len = RARRAY_LEN(obj);
        for (long i = 0; i < len; i++)
            arr.push_back(rb_to_json(RARRAY_AREF(obj, i)));
        return arr;
    }
    case T_HASH: {
        json h = json::object();
        rb_hash_foreach(obj, hash_foreach_wrapper,
                         reinterpret_cast<VALUE>(&h));
        return h;
    }
    default: {
        /* Fallback: call to_s */
        VALUE s = rb_funcall(obj, rb_intern("to_s"), 0);
        return std::string(RSTRING_PTR(s), RSTRING_LEN(s));
    }
    }
}

/* ── Template rendering ───────────────────────────────────────────── */

static VALUE inja_render_template(VALUE mod, VALUE tpl_str, VALUE data_hash) {
    Check_Type(tpl_str, T_STRING);
    Check_Type(data_hash, T_HASH);

    std::string tpl(RSTRING_PTR(tpl_str), RSTRING_LEN(tpl_str));
    json data = rb_to_json(data_hash);

    try {
        inja::Environment env;
        std::string result = env.render(tpl, data);
        return rb_enc_str_new(result.c_str(), static_cast<long>(result.size()),
                              inja_enc_utf8);
    } catch (const std::exception &e) {
        rb_raise(rb_eRuntimeError, "Inja render error: %s", e.what());
    }
    return Qnil; /* unreachable */
}

static VALUE inja_render_template_file(VALUE mod, VALUE path, VALUE data_hash) {
    Check_Type(path, T_STRING);
    Check_Type(data_hash, T_HASH);

    std::string file_path(RSTRING_PTR(path), RSTRING_LEN(path));
    json data = rb_to_json(data_hash);

    std::string dir_copy;
    {
        std::shared_lock<std::shared_mutex> lock(dir_mutex);
        dir_copy = g_template_dir;
    }

    try {
        if (!dir_copy.empty()) {
            inja::Environment env(dir_copy);
            std::string result = env.render_file(file_path, data);
            return rb_enc_str_new(result.c_str(),
                                  static_cast<long>(result.size()),
                                  inja_enc_utf8);
        }
        inja::Environment env;
        std::string result = env.render_file(file_path, data);
        return rb_enc_str_new(result.c_str(), static_cast<long>(result.size()),
                              inja_enc_utf8);
    } catch (const std::exception &e) {
        rb_raise(rb_eRuntimeError, "Inja render_file error: %s", e.what());
    }
    return Qnil;
}

static VALUE inja_set_template_directory(VALUE mod, VALUE dir) {
    Check_Type(dir, T_STRING);
    std::unique_lock<std::shared_mutex> lock(dir_mutex);
    g_template_dir = std::string(RSTRING_PTR(dir), RSTRING_LEN(dir));
    return Qtrue;
}

static VALUE inja_available_p(VALUE mod) {
    return Qtrue;
}

/* ── Init (called from Init_nodex_native in nodex_native.c) ─────────── */

extern "C" void Init_nodex_inja(void) {
    inja_enc_utf8 = rb_utf8_encoding();

    VALUE mNodex = rb_const_get(rb_cObject, rb_intern("Nodex"));
    VALUE mNative = rb_define_module_under(mNodex, "NativeInja");

    rb_define_module_function(mNative, "render_template",
                              reinterpret_cast<VALUE (*)(...)>(inja_render_template), 2);
    rb_define_module_function(mNative, "render_template_file",
                              reinterpret_cast<VALUE (*)(...)>(inja_render_template_file), 2);
    rb_define_module_function(mNative, "set_template_directory",
                              reinterpret_cast<VALUE (*)(...)>(inja_set_template_directory), 1);
    rb_define_module_function(mNative, "inja_available?",
                              reinterpret_cast<VALUE (*)(...)>(inja_available_p), 0);
}
