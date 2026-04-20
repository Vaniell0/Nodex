#pragma once

#include <string>

namespace nodex {
namespace hot_reload {

/// JavaScript client for WebSocket hot-reload.
/// Connects to /__nodex_ws, handles "reload" and "css_reload" messages.
extern const char* JS_CLIENT;

/// Inject the hot-reload script into an HTML string (before </body>).
std::string InjectScript(const std::string& html, int port = 0);

} // namespace hot_reload
} // namespace nodex
