# Getting Started

[← Главная](index.md)

## Установка

### Ruby Gem (рекомендуется)

```bash
gem install nodex                   # чистый Ruby (кроссплатформа)
gem install nodex-native            # опционально: C extension (~3x быстрее)
```

`nodex` — чистый Ruby, работает везде. Внешние зависимости не нужны.
`nodex-native` — компилируется из исходников при установке (нужен C/C++ компилятор).

### Nix

```bash
nix develop              # dev shell
nix run                  # запустить сервер
nix run .#dev            # dev mode с hot-reload
```

### Из исходников

```bash
git clone https://github.com/Vaniell0/nodex
cd nodex
ruby examples/ruby/server.rb   # работает сразу
```

## Минимальный пример

```ruby
require 'nodex'

puts Nodex.h1("Hello").bold.color("#4f46e5").to_html
```

```html
<h1 style="font-weight: bold; color: #4f46e5">Hello</h1>
```

Pipe-оператор:

```ruby
extend Nodex::DSL

puts (h1("Hello") | Bold() | Color("red") | Class("title")).to_html
```

```html
<h1 class="title" style="font-weight: bold; color: red">Hello</h1>
```

## Layout

Стандартная структура страницы — navbar + container + footer:

```ruby
extend Nodex::DSL

page = layout("My Site",
  head: [stylesheet("/static/style.css")],
  navbar: [
    a("Home", href: "/") | AddClass("nav-link"),
    a("About", href: "/about") | AddClass("nav-link"),
  ],
  body: [
    h1("Hello") | Bold() | Center(),
    p("World") | Color("#666"),
  ],
  footer: [p("Built with Nodex") | Center()]
)
```

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>My Site</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <nav class="navbar">
    <a class="nav-link" href="/" ...>Home</a>
    <a class="nav-link" href="/about" ...>About</a>
  </nav>
  <div class="container">
    <h1 style="font-weight: bold; ...">Hello</h1>
    <p style="color: #666">World</p>
  </div>
  <footer class="footer">
    <p style="...">Built with Nodex</p>
  </footer>
</body>
</html>
```

Для полного контроля используй `document()` напрямую — см. [ruby-dsl](ruby-dsl.md).

## CLI

```bash
nodex new mysite          # создать проект (pages/, static/, style.css)
nodex new page about      # сгенерировать страницу pages/about.rb
nodex build               # отрендерить pages/ → dist/
nodex serve               # запустить dev сервер с hot-reload
```

## Запуск сервера

```bash
ruby examples/ruby/server.rb            # http://localhost:10101
ruby examples/ruby/server.rb --dev      # hot-reload
```

В dev mode:
- `.rb` → full reload
- `.css` → CSS-only reload (без перезагрузки страницы)
- WebSocket: `ws://localhost:10101/__nodex_ws`

Подробнее: [server](server.md), [hot-reload](hot-reload.md)

## nodex-native (опционально)

C extension для ускорения рендера в 2-4x + Inja template engine:

```bash
cd nodex-native
rake compile
```

```ruby
require 'nodex/native'   # подключает C рендерер + Inja

# Рендер теперь через C — API не меняется
page = Nodex.div([Nodex.h1("Hello").bold])
puts page.to_html
```

```html
<div><h1 style="font-weight: bold">Hello</h1></div>
```

Inja шаблоны:

```ruby
Nodex::Native.render_template("Hello {{ name }}!", { name: "World" })
```

```
Hello World!
```

```ruby
Nodex::Native.render_template(
  "{% for x in items %}<li>{{ x }}</li>\n{% endfor %}",
  { items: ["Ruby", "C++", "Inja"] }
)
```

```html
<li>Ruby</li>
<li>C++</li>
<li>Inja</li>
```

Ruby DSL работает полностью без nodex-native.

Подробнее: [nodex-native](nodex-native.md), [performance](performance.md)

## Структура проекта

```
Nodex/
├── ruby/
│   ├── lib/nodex.rb     # DSL (Node, фабрики, pipe, layout)
│   ├── lib/nodex/       # Registry, PageLoader, WebSocket, CLI
│   └── pages/          # Страницы (автозагрузка)
├── examples/
│   ├── ruby/           # server.rb, demo.rb
│   └── cpp/            # C++ примеры
├── nodex-native/
│   ├── ext/            # C extension + Inja bindings
│   ├── lib/            # native.rb, packed_builder.rb
│   └── test/           # 107 тестов + бенчмарки
├── include/nodex/       # C++ API
├── src/                # C++ реализация
├── static/             # CSS
├── templates/          # Inja шаблоны
└── docs/               # документация
```

## Следующие шаги

- [ruby-dsl](ruby-dsl.md) — все элементы и методы
- [pipe-operator](pipe-operator.md) — оператор `|` для декорирования
- [components](components.md) — система компонентов и страниц
- [nodex-native](nodex-native.md) — C extension, Inja, baked templates, PackedBuilder
