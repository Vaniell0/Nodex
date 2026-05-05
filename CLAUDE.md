# Nodex — Declarative Document/UI Framework

## Что это
Фреймворк для генерации HTML, DOCX, ODT из Ruby DSL. C++20 ядро для быстрого HTML-рендеринга. Нативные OMML-формулы в Word.

## Сборка (C++)
```bash
nix develop
cmake -B build -DCMAKE_BUILD_TYPE=Release
ninja -C build
```

## Ruby (основной интерфейс)
```bash
nodex-ruby script.rb                  # генерация документов
nodex-ruby -e 'require "nodex"; ...'  # one-liner
```

## Структура
Два гема под одной лицензией (Apache-2.0):

```
nodex (core):
  include/nodex/        — C++20 заголовки (core, elements, decorators, registry, renderer)
  src/                  — C++ реализация (8 файлов)
  ruby/lib/nodex.rb     — Ruby DSL (Node, 50+ элементов, pipe operator)
  ruby/lib/nodex/
    markdown.rb         — Markdown → Node tree
    server.rb           — HTTP сервер (middleware, session, SSE, HTMX)
    cli.rb              — CLI: build, serve, new
  nodex-native/         — C extension для быстрого HTML-рендеринга

nodex-office (опциональный гем, depends on nodex):
  nodex-office/lib/nodex/office.rb       — entry point (Node#to_docx/to_odt/to_pdf)
  nodex-office/lib/nodex/office/docx.rb  — Pure Ruby DOCX writer (OMML, images, tables)
  nodex-office/lib/nodex/office/odt.rb   — Pure Ruby ODT writer
  nodex-office/lib/nodex/office/omml.rb  — LaTeX → OMML конвертер
```

**Использование office writers:**
```ruby
require "nodex"
require "nodex/office"     # подключает to_docx/to_odt/to_pdf
node.to_docx("report.docx", preset: :gost)
```

## C++ Targets
- `libnodex.a` — статическая библиотека
- `nodex-demo` — C++ демо
- `nodex-tests` — Catch2 тесты (опционально)

## Зависимости
- C++: fmt 11.1.4, nlohmann_json 3.11.3, inja 3.4.0, Catch2 3.7.1 (тесты)
- Ruby: zero dependencies (только stdlib + Zlib)
