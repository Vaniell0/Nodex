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
```
include/nodex/          — C++20 заголовки (core, elements, decorators, registry, renderer)
src/                    — C++ реализация (8 файлов)
ruby/lib/nodex.rb       — Ruby DSL (Node, 50+ элементов, pipe operator, math)
ruby/lib/nodex/
  docx.rb               — Pure Ruby DOCX writer (OMML math, images, tables)
  odt.rb                — Pure Ruby ODT writer
  omml.rb               — LaTeX → OMML конвертер
  markdown.rb           — Markdown → Node tree
  server.rb             — HTTP сервер (middleware, session, SSE, HTMX)
  cli.rb                — CLI: build, serve, new
nodex-native/           — C extension для быстрого HTML-рендеринга
```

## C++ Targets
- `libnodex.a` — статическая библиотека
- `nodex-demo` — C++ демо
- `nodex-tests` — Catch2 тесты (опционально)

## Зависимости
- C++: fmt 11.1.4, nlohmann_json 3.11.3, inja 3.4.0, Catch2 3.7.1 (тесты)
- Ruby: zero dependencies (только stdlib + Zlib)
