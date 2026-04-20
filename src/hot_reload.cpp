#include "nodex/hot_reload.hpp"

namespace nodex {
namespace hot_reload {

const char* JS_CLIENT = R"JS(
(function() {
  if (typeof WebSocket === 'undefined') return;
  var proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  var ws = new WebSocket(proto + '//' + location.host + '/__nodex_ws');
  var reconnectDelay = 1000;

  ws.onmessage = function(event) {
    var msg;
    try { msg = JSON.parse(event.data); } catch(e) { return; }

    if (msg.type === 'reload') {
      console.log('[Nodex] Hot reload:', msg.file || '');
      location.reload();
    } else if (msg.type === 'css_reload') {
      document.querySelectorAll('link[rel="stylesheet"]').forEach(function(link) {
        var href = link.href;
        link.href = href.split('?')[0] + '?_t=' + Date.now();
      });
      console.log('[Nodex] CSS reloaded');
    }
  };

  ws.onclose = function() {
    console.log('[Nodex] Disconnected. Reconnecting in', reconnectDelay, 'ms');
    setTimeout(function() {
      reconnectDelay = Math.min(reconnectDelay * 2, 10000);
      location.reload();
    }, reconnectDelay);
  };

  ws.onerror = function() { ws.close(); };
})();
)JS";

std::string InjectScript(const std::string& html, int /*port*/) {
    auto tag = std::string("<script>") + JS_CLIENT + "</script>";
    auto pos = html.rfind("</body>");
    if (pos != std::string::npos) {
        std::string result = html;
        result.insert(pos, tag);
        return result;
    }
    // No </body> found, append at end
    return html + tag;
}

} // namespace hot_reload
} // namespace nodex
