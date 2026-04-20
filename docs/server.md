# Сервер

[← Главная](index.md) · [websocket](websocket.md) · [hot-reload](hot-reload.md) · [components](components.md)

## Архитектура

Ruby stdlib Socket сервер — zero dependencies, кроссплатформа.

Один бэкенд — Ruby stdlib Socket. Zero dependencies, кроссплатформа.

## Запуск

```bash
ruby examples/ruby/server.rb            # production
ruby examples/ruby/server.rb --dev      # dev mode

# Или через Nix:
nix run                                  # production
nix run .#dev                            # dev mode
```

Порт: `10101` (константа `PORT`).

## HTTP роуты

| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/` | Главная страница (из Registry) |
| GET | `/static/*` | Статические файлы (CSS, JS, изображения) |
| GET | `/project/:id` | Страница проекта (параметризованная) |
| POST | `/api/contact` | Отправка контактной формы |

Общий обработчик `handle_request(method, path, query, body, registry)`.

## Socket бэкенд

Чистый Ruby на stdlib:

```ruby
server = Socket.new(:INET, :STREAM, 0)
server.bind(Socket.sockaddr_in(PORT, '0.0.0.0'))
server.listen(128)
```

Thread-per-connection: каждый запрос обрабатывается в отдельном потоке.

WebSocket upgrade: при запросе на `/__nodex_ws` с заголовком `Upgrade: websocket` выполняется RFC 6455 handshake.

## Dev Mode

Активируется через `--dev` или `Nodex_DEV=1`:

- [FileWatcher](hot-reload.md) отслеживает `ruby/pages/` и `static/`
- [WebSocket](websocket.md) endpoint на `/__nodex_ws`
- JS скрипт hot-reload инжектится перед `</body>`
- Изменение `.rb` → полная перезагрузка страницы
- Изменение `.css` → CSS-only reload без перезагрузки

## MIME Types

```ruby
'.css'  => 'text/css; charset=utf-8'
'.js'   => 'application/javascript; charset=utf-8'
'.html' => 'text/html; charset=utf-8'
'.json' => 'application/json; charset=utf-8'
'.png'  => 'image/png'
'.svg'  => 'image/svg+xml'
```

## Безопасность

Статические файлы проверяются через `File.realpath` — traversal за пределы `STATIC_DIR` блокируется:

```ruby
canonical = File.realpath(file_path)
return 404 unless canonical.start_with?(static_canonical)
```
