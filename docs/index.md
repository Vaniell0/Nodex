# Nodex

**Ruby DSL для декларативной генерации HTML, DOCX, ODT** — zero dependencies, block DSL, pipe operator, native OMML math.

Строите документы и страницы как дерево компонентов. Один Node tree — несколько выходных форматов. Без gem-зависимостей — только Ruby stdlib.

## Быстрый старт

```ruby
require 'nodex'
include Nodex::DSL

page = div(class: "report") {
  h1("Quarterly Report").bold
  p "Revenue increased by 15%."
  table {
    tr { th "Metric"; th "Value" }
    tr { td "Revenue"; td "$1.38M" }
  }
  math_block("\\Delta = \\frac{Q4 - Q3}{Q3}")
}

page.to_html                                  # → HTML (KaTeX math)
page.to_docx("report.docx", preset: :gost)   # → DOCX (OMML math)
page.to_odt("report.odt")                    # → ODT
```

## Документация

### Ruby DSL (Apache 2.0)

- [getting-started](getting-started.md) — установка, сборка, запуск
- [ruby-dsl](ruby-dsl.md) — block DSL, элементы, pipe operator, named styles
- [documents](documents.md) — DOCX/ODT генерация, пресеты (GOST/academic/report/letter)
- [math](math.md) — формулы: LaTeX→OMML (DOCX), KaTeX (HTML), tex_* builders
- [pipe-operator](pipe-operator.md) — оператор `|` и 35+ декораторов
- [components](components.md) — Registry, компоненты, страницы
- [server](server.md) — HTTP сервер, middleware, session, SSE, HTMX
- [websocket](websocket.md) — RFC 6455, InteractiveHub
- [hot-reload](hot-reload.md) — FileWatcher, live-перезагрузка

### nodex-native (BSL 1.1)

- [nodex-native](nodex-native.md) — C extension: рендер, кеш, Inja шаблоны
- [docx-odt](docx-odt.md) — DOCX/ODT экспорт: ГОСТ пресет, колонтитулы
- [baked-templates](baked-templates.md) — компиляция шаблонов в чанки + слоты
- [packed-builder](packed-builder.md) — opcode stream рендер
- [performance](performance.md) — бенчмарки
- [use-cases](use-cases.md) — применение, аналоги

### C++ ядро (BSL 1.1)

- [cpp-api](cpp-api.md) — Node, Elements, Decorators, Renderer, Registry
- [build](build.md) — CMake, таргеты, зависимости

## Архитектура

```
Ruby DSL (ruby/lib/nodex.rb) — Apache 2.0
├── Node — единый класс (тег, атрибуты, стили, дети)
├── 50+ фабричных функций (div, h1, form, table, ...)
├── Pipe-оператор | с 35+ декораторами
├── DocxWriter — pure Ruby DOCX (OMML math, images, tables)
├── OdtWriter — pure Ruby ODT
├── OMML — LaTeX → Office Math Markup Language
├── Markdown (to_html + to_node, $math$)
├── Server (middleware, session, SSE, HTMX)
├── WebSocket (RFC 6455, heartbeat)
└── CLI: nodex new/build/serve

nodex-native (nodex-native/) — BSL 1.1
├── C extension (iterative render, per-thread buffers)
├── Render cache (@_html_cache, O(1))
├── Inja Template Engine
├── Baked templates + PackedBuilder
└── Thread Safety (mutex, per-thread буферы)

C++ ядро (include/, src/) — BSL 1.1
├── Node, Elements, Decorators, Renderer
├── Registry (компоненты + страницы)
└── Template Engine (inja)
```

## Лицензирование

| Компонент | Лицензия |
|-----------|----------|
| `ruby/` — Ruby DSL, Server | Apache 2.0 |
| `nodex-native/` — C extension | BSL 1.1 |
| `include/`, `src/` — C++ ядро | BSL 1.1 |

Ruby DSL работает полностью самостоятельно без C++ или nodex-native.

## Ссылки

- [GitHub](https://github.com/Vaniell0/Nodex)
