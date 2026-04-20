# Use Cases и Roadmap

[← Главная](index.md) · [performance](performance.md) · [nodex-native](nodex-native.md)

## Текущие use cases

### Admin dashboards и monitoring panels

Основной сценарий. Дашборд из 50-100 виджетов, из которых обновляются 2-3 за тик. Subtree cache делает partial invalidation в 13-16x быстрее полного re-render при 98% меньше GC давления.

Что используют сейчас:

| Стек | RSS на процесс | Partial update |
|------|----------------|----------------|
| Next.js SSR | 150-300 MB | Нет (full re-render) |
| Express + EJS | 50-100 MB | Нет (full re-render) |
| Django + Gunicorn | 100-160 MB / воркер | Нет |
| Rails + Puma | 150-300 MB / воркер | Нет |
| Django + HTMX | 100-160 MB / воркер | Фрагменты, но без кеша поддеревьев |
| **Nodex Ruby Native** | **~18 MB** | **Subtree cache, 0.014 ms** |

### Web UI для роутеров и embedded

На embedded-устройствах стоят минимальные стеки:
- OpenWrt LuCI — Lua + uHTTPd (устройства с 8-32 MB RAM)
- MikroTik WebFig — vanilla JS, проприетарный протокол
- pfSense — PHP + nginx
- Типичный роутер — C HTTP-сервер + CGI

Nodex C++ API компилируется в нативный бинарник без runtime. Registry, pipe-декораторы, Inja шаблоны, SSG — всё доступно из C++. Для устройств с большей памятью подходит и Ruby версия (18 MB RSS).

### HTMX фрагменты

HTMX (Django + HTMX, Rails + Hotwire) набирает популярность как альтернатива SPA. Паттерн: сервер отдаёт HTML-фрагмент, HTMX вставляет его в DOM.

Nodex добавляет к этому паттерну subtree cache — фрагмент отдаётся из кеша если поддерево не менялось. Ни один из существующих стеков этого не делает: EJS, ERB, Jinja2 всегда рендерят шаблон целиком.

```ruby
# Сервер отдаёт фрагмент для HTMX swap
widget.set_text("#{new_value}")    # invalidate только эту ветку
widget.to_html                      # фрагмент из частично обновлённого кеша
```

### Email template generation

HTML email без браузера, без Node.js toolchain, без Puppeteer. Ruby DSL → HTML string → отправка через SMTP.

```ruby
email = Nodex.layout("Order Confirmation",
  body: [
    Nodex.h1("Order ##{order.id}").bold,
    Nodex.table(order.items.map { |item|
      Nodex.tr([Nodex.td(item.name), Nodex.td("$#{item.price}")])
    }),
  ]
)
send_email(to: user.email, html: email.to_html)
```

### Static site generation

```bash
nodex build   # pages/ → dist/
```

Ruby-скрипты как страницы, Inja шаблоны, рендер в статические HTML файлы.

## Roadmap

### HTMX-фрагменты с partial invalidation

Сейчас WebSocket сервер уже есть. Следующий шаг — автоматическая отправка только изменённых фрагментов через HTMX OOB swap:

```html
<!-- сервер отправляет только изменившиеся виджеты -->
<div id="widget-3" hx-swap-oob="true">...новый HTML...</div>
```

Дерево уже знает какие поддеревья изменились (bubble-up invalidation). Осталось связать это с WebSocket transport.

### HTML-отчёты и PDF-пайплайны

Nodex DSL → HTML → PDF (через WeasyPrint, wkhtmltopdf). Формирование отчётов, инвойсов, документации из Ruby-кода без raw HTML.

### Микросервис-рендерер

Отдельный процесс (18 MB), принимает JSON → отдаёт HTML. Вместо шаблонизатора в каждом сервисе — один Nodex рендерер за load balancer.

### C++ embedded web server

Nodex C++ уже имеет SSG генератор и embed генератор (constexpr pages). Цель — standalone HTTP-сервер для embedded-устройств: роутеры, IoT панели, промышленные контроллеры. Нативный бинарник, никакого runtime.

## Аналоги

| Проект | Язык | Subtree cache | Standalone сервер | Embedded |
|--------|------|---------------|-------------------|----------|
| Phlex | Ruby | Нет | Нет (Rails) | Нет |
| ViewComponent | Ruby | Нет | Нет (Rails) | Нет |
| Markaby | Ruby | Нет | Нет | Нет |
| Arbre | Ruby | Нет | Нет (ActiveAdmin) | Нет |
| templ | Go | Нет | Нет (библиотека) | Возможно |
| **Nodex** | **Ruby + C + C++** | **Да** | **Да** | **Да (C++)** |
