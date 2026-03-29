# FWUI

**Ruby DSL для декларативной генерации HTML** — zero dependencies, chainable API, HTMX из коробки.

Строите HTML как дерево компонентов с pipe-оператором `|`, реестром страниц и живой перезагрузкой. Без gem-зависимостей — только Ruby stdlib.

## Быстрый старт

```ruby
require 'fwui'
extend FWUI::DSL

puts (h1("Hello") | Bold() | Color("#4f46e5")).to_html
```

```html
<h1 style="font-weight: bold; color: #4f46e5">Hello</h1>
```

Полная страница одной строкой:

```ruby
page = layout("My Site",
  navbar: [a("Home", href: "/")],
  body: [h1("Hello") | Bold(), p("World") | Color("#666")]
)
```

```html
<!DOCTYPE html>
<html lang="en">
<head>...</head>
<body>
  <nav class="navbar"><a href="/" ...>Home</a></nav>
  <div class="container">
    <h1 style="font-weight: bold">Hello</h1>
    <p style="color: #666">World</p>
  </div>
</body>
</html>
```

## Документация

### Ruby DSL (Apache 2.0)

- [getting-started](getting-started.md) — установка, сборка, запуск сервера
- [ruby-dsl](ruby-dsl.md) — элементы, контейнеры, chainable методы, документы
- [pipe-operator](pipe-operator.md) — оператор `|` и 35+ фабрик-декораторов
- [components](components.md) — Registry, компоненты, страницы, автозагрузка
- [server](server.md) — stdlib Socket сервер, HTTP + WebSocket
- [websocket](websocket.md) — RFC 6455 реализация, InteractiveHub, протокол
- [hot-reload](hot-reload.md) — FileWatcher, live-перезагрузка при разработке

### fwui-native (BSL 1.1)

- [fwui-native](fwui-native.md) — C extension: рендер, кеш, Inja шаблоны
- [baked-templates](baked-templates.md) — компиляция шаблонов в статические чанки + слоты
- [packed-builder](packed-builder.md) — opcode stream: рендер без Node-объектов
- [performance](performance.md) — бенчмарки, рекомендации по выбору режима
- [use-cases](use-cases.md) — применение, аналоги, roadmap

### C++ ядро (BSL 1.1)

- [cpp-api](cpp-api.md) — Node, Elements, Decorators, Renderer, Registry, TemplateEngine
- [ssg](ssg.md) — генератор статических сайтов (`fwui-ssg`)
- [embedded](embedded.md) — embedded pages: constexpr HTML в бинарнике (`fwui-embed`)
- [build](build.md) — CMake, таргеты, зависимости, CI


## Архитектура

```
Ruby DSL (ruby/lib/fwui.rb) — Apache 2.0
├── Node — единый класс (тег, атрибуты, стили, дети)
├── 50+ фабричных функций (div, h1, form, table, ...)
├── Pipe-оператор | с 35+ декораторами
├── layout() — navbar + container + footer одной строкой
├── Registry + PageLoader (компоненты, страницы)
├── CLI: fwui new, fwui new page, fwui build, fwui serve
├── Сервер (stdlib Socket)
├── WebSocket (RFC 6455, InteractiveHub)
├── Hot-Reload (FileWatcher, CSS-only)
└── DSL mixin (extend FWUI::DSL)

fwui-native (fwui-native/) — BSL 1.1
├── C extension (iterative render, ROBJECT_IVPTR)
├── Render cache (@_html_cache, O(1))
├── Inja Template Engine (Jinja2-совместимый)
├── Baked templates (статические чанки + слоты)
├── PackedBuilder (opcode stream → C → HTML)
├── UI::Component (упрощённый API поверх baked)
└── Thread Safety (per-thread буферы, mutex)

C++ ядро (include/, src/) — BSL 1.1
├── Node, Elements, Decorators, Renderer
├── Registry (компоненты + страницы)
├── Inja Template Engine
└── SSG + Embed генераторы
```

## Лицензирование

| Компонент | Лицензия |
|-----------|----------|
| `ruby/` — Ruby DSL, Registry, Server | Apache 2.0 |
| `fwui-native/` — C extension + Inja | BSL 1.1 |
| `include/`, `src/` — C++ ядро | BSL 1.1 |

Ruby DSL работает полностью самостоятельно без C++ или fwui-native.

## Ссылки

- [GitHub](https://github.com/Vaniell0/fwui)
- [Ruby Gem](https://github.com/Vaniell0/fwui/releases)
