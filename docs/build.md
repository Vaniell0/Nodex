# Система сборки

## Зависимости

| Библиотека | Версия | Обязательна | Назначение |
|------------|--------|-------------|-----------|
| fmt | 11.1.4 | Да | Форматирование строк |
| nlohmann_json | 3.11.3 | Да | JSON |
| inja | 3.4.0 | Да | Шаблонизатор (header-only) |
| Catch2 | 3.7.1 | Нет (BUILD_TESTS) | Тесты |

Все зависимости ищутся через `find_package()`. Если не найдены — скачиваются через CMake FetchContent.

## Сборка

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build
```

### С тестами

```bash
cmake -B build -G Ninja -DNodex_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
ninja -C build
ctest --test-dir build --output-on-failure
```

## Таргеты

| Таргет | Тип | Назначение |
|--------|-----|-----------|
| nodex | static lib | Ядро (Node, Renderer, Registry, Template) |
| nodex-demo | executable | Демонстрация C++ API |
| nodex-bench | executable | Бенчмарки рендеринга |
| nodex-bench-mem | executable | Бенчмарки памяти |
| nodex-tests | executable | Catch2 unit-тесты (BUILD_TESTS) |

## Install

```bash
cmake --install build --prefix /usr/local
```

Устанавливает:
- `lib/libnodex.a` — статическая библиотека
- `bin/nodex-demo` — демо
- `include/nodex/` — заголовки

## Nix

Проект включает `flake.nix`:

```bash
nix develop                    # dev shell
nix run .#ruby                 # ruby с Nodex
nix profile install .          # nodex-ruby глобально
```

## Платформы

| ОС | C++ ядро | Ruby DSL | Статус |
|----|----------|----------|--------|
| Linux | cmake + apt/nix | gem install | CI, основная |
| macOS | cmake + brew | gem install | CI |
| Windows | — | gem install (RubyInstaller) | Работает, не тестируется в CI |

Ruby DSL — чистый stdlib (Zlib, StringIO, Socket), без системных зависимостей. Работает везде где есть Ruby 3.0+.

C++ ядро собирается только на Linux/macOS. На Windows можно использовать Ruby DSL без C++ части.

## CI (GitHub Actions)

Каждый push в main запускает:
- **C++ (Linux, macOS):** cmake + ninja + 56 тестов
- **Ruby (Linux, macOS):** gem install → HTML/DOCX/ODT генерация
