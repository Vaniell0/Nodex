# WebSocket

[← Главная](index.md) · [server](server.md) · [hot-reload](hot-reload.md)

## Реализация

Nodex включает чистую реализацию RFC 6455 на Ruby stdlib (без gem-зависимостей).

### Модули

| Файл | Назначение |
|------|-----------|
| `ruby/lib/nodex/websocket.rb` | RFC 6455: handshake, read/write frames |
| `ruby/lib/nodex/interactive_hub.rb` | Обработка сообщений по типу |

### Handshake

```ruby
Nodex::WebSocket.handshake(client, headers)
```

Выполняет HTTP → WebSocket upgrade:
1. Проверяет `Sec-WebSocket-Key`
2. Вычисляет `Sec-WebSocket-Accept` (SHA1 + Base64)
3. Отправляет `101 Switching Protocols`

### Фреймы

```ruby
Nodex::WebSocket.read_frame(client)   # => [opcode, payload]
Nodex::WebSocket.send_text(client, msg)
Nodex::WebSocket.send_close(client)
Nodex::WebSocket.send_ping(client)
Nodex::WebSocket.send_pong(client, data)
```

Поддерживаемые opcodes: text (0x1), close (0x8), ping (0x9), pong (0xA).

## InteractiveHub

Thread-safe менеджер WS-клиентов с обработчиками по типу сообщения:

```ruby
hub = Nodex::InteractiveHub.new

hub.on('contact_submit') do |msg, client|
  name = msg['name'] || 'друг'
  { type: 'contact_response', success: true,
    message: "Спасибо, #{name}!" }
end

hub.broadcast(JSON.generate({ type: 'visitor_count', count: 3 }))
```

## Протокол сообщений

Все сообщения — JSON. Поле `type` определяет обработчик.

### Client → Server

| type | Поля | Описание |
|------|------|----------|
| `contact_submit` | `name`, `email`, `message` | Отправка формы |

### Server → Client

| type | Поля | Описание |
|------|------|----------|
| `contact_response` | `success`, `message` | Ответ на форму |
| `visitor_count` | `count` | Кол-во подключённых клиентов |
| `reload` | `file` | Hot-reload: перезагрузить страницу |
| `css_reload` | — | Hot-reload: обновить только CSS |

## JS клиент

```javascript
var ws = new WebSocket('ws://localhost:10101/__nodex_ws');

// Отправка
ws.send(JSON.stringify({
  type: 'contact_submit',
  name: 'Иван',
  email: 'ivan@example.com',
  message: 'Привет!'
}));

// Приём
ws.onmessage = function(event) {
  var msg = JSON.parse(event.data);
  if (msg.type === 'contact_response') { ... }
};
```

JS клиент пытает WS первым, fallback на HTTP fetch:

```javascript
var sent = wsSend({ type: 'contact_submit', ... });
if (!sent) {
  fetch('/api/contact', { method: 'POST', body: JSON.stringify(data) });
}
```

Реконнект при обрыве: `setTimeout(connectWS, 3000)`.
