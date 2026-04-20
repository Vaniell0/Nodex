# nodex-native

[← Главная](index.md) · [baked-templates](baked-templates.md) · [packed-builder](packed-builder.md) · [performance](performance.md)

C extension для Ruby — подключается одной строкой, `Node#to_html` переключается на C-реализацию.

```ruby
require 'nodex/native'  # всё, рендер теперь через C
```

## Четыре режима рендеринга

| Режим | Описание | Скорость |
|-------|----------|----------|
| **C render** | Drop-in замена `to_html` | 2-4x vs Ruby |
| **Render cache** | `@_html_cache` — повторный вызов O(1), subtree granularity с bubble-up invalidation | >600x |
| **Baked templates** | Статические чанки + слоты, без обхода дерева | 600x (1 карточка) |
| **PackedBuilder** | Opcode stream → C → HTML, без Node-объектов | 1.3x |

## Inja Template Engine

nodex-native включает [Inja](https://github.com/pantor/inja) — Jinja2-совместимый шаблонизатор. Вызовы идут напрямую через C extension, без FFI overhead.

### Переменные

```ruby
Nodex::Native.render_template("Hello {{ name }}!", { name: "World" })
```

```
Hello World!
```

### Циклы

```ruby
tpl = <<~INJA
  <ul>
  {% for item in items %}<li>{{ item }}</li>
  {% endfor %}</ul>
INJA

Nodex::Native.render_template(tpl, { items: ["Ruby", "C++", "Inja"] })
```

```html
<ul>
  <li>Ruby</li>
  <li>C++</li>
  <li>Inja</li>
</ul>
```

### Условия

```ruby
tpl = "{% if logged_in %}Welcome, {{ user }}!{% else %}Please log in{% endif %}"

Nodex::Native.render_template(tpl, { logged_in: true, user: "Ivan" })
```

```
Welcome, Ivan!
```

### Карточки из данных

```ruby
tpl = <<~INJA
  {% for card in cards %}
  <div class="card">
    <h1>{{ card.title }}</h1>
    <p>{{ card.desc }}</p>
  </div>
  {% endfor %}
INJA

Nodex::Native.render_template(tpl, { cards: [
  { title: "Project A", desc: "Description A" },
  { title: "Project B", desc: "Description B" },
]})
```

```html
<div class="card">
  <h1>Project A</h1>
  <p>Description A</p>
</div>
<div class="card">
  <h1>Project B</h1>
  <p>Description B</p>
</div>
```

### Встроенные функции

Inja поддерживает функции: `length()`, `upper()`, `lower()`, `range()`, `sort()`, `first()`, `last()`, `join()`, `exists()`, `default()` и другие.

```ruby
Nodex::Native.render_template(
  "{{ length(items) }} items: {% for x in items %}{{ x }}{% if not loop.is_last %}, {% endif %}{% endfor %}",
  { items: ["one", "two", "three"] }
)
```

```
3 items: one, two, three
```

### Шаблоны из файлов

```ruby
# Установить базовую директорию (для {% include %})
Nodex::Native.set_template_directory("templates/")

# Рендер файла
Nodex::Native.render_template_file("page.html", {
  title: "Home",
  items: ["Ruby", "C++"],
})
```

### API

| Метод | Описание |
|-------|----------|
| `render_template(tpl, data)` | Рендер строки шаблона с данными (Hash) |
| `render_template_file(path, data)` | Рендер файла шаблона |
| `set_template_directory(dir)` | Базовая директория для `{% include %}` |
| `inja_available?` | Всегда `true` когда nodex-native загружен |

Данные: Ruby Hash автоматически конвертируется в JSON. Поддерживаются String, Integer, Float, Boolean, Array, вложенные Hash.

## Оптимизации C render

### Iterative render

Рекурсивный обход дерева заменён на итеративный с explicit stack в C (max 256 уровней):

```c
struct { VALUE children; long idx, count; } stk[256];
```

### ROBJECT_IVPTR

Прямой доступ к instance variables по смещению, O(1) вместо shape walk:

```c
VALUE *ivs = ROBJECT_IVPTR(node);
VALUE tag  = ivs[0];  // @tag
VALUE text = ivs[1];  // @text
```

Работает благодаря nil-init оптимизации — все ivars в `Node#initialize` создаются в фиксированном порядке.

### HTML escape table

256-byte lookup table для `& < > " '`. Один проход без бранчей.

### Reusable buffer

Один `malloc(128KB)` на процесс. После warmup аллокаций нет.

## Baked Templates

Компиляция Node-шаблона в статические чанки + слоты. Рендер — memcpy + escape, без обхода дерева.

```ruby
Nodex::Native.bake(:card, Nodex.div([
  Nodex.h1(Nodex.slot(:title)).bold,
  Nodex.p(Nodex.slot(:desc)),
]).add_class("card"))

Nodex::Native.render_baked(:card, title: "Project X", desc: "A cool project")
```

```html
<div class="card">
  <h1 style="font-weight: bold">Project X</h1>
  <p>A cool project</p>
</div>
```

Подробнее: [baked-templates](baked-templates.md)

## PackedBuilder

DSL без Node-объектов — Ruby пишет бинарные опкоды, C рендерит HTML напрямую.

```ruby
Nodex::Native.build {
  div {
    h1("Title").bold.color("blue")
    p("Content").padding("10px")
  }.add_class("container")
}
```

```html
<div class="container">
  <h1 style="font-weight: bold; color: blue">Title</h1>
  <p style="padding: 10px">Content</p>
</div>
```

Подробнее: [packed-builder](packed-builder.md)

## Cache invalidation (Subtree Cache)

Мутирующие методы автоматически сбрасывают `@_html_cache` через **bubble-up invalidation**:

```ruby
node = Nodex.h1("Hello").bold
node.to_html          # рендерит в C, кеширует
node.to_html          # возвращает кеш O(1)
node.color("red")     # кеш сброшен + все предки через @parent
node.to_html          # новый рендер
```

### Механизм

Каждый `Node` хранит `@parent` — ссылку на родительскую ноду. При мутации:

1. `invalidate_cache!` сбрасывает `@_html_cache` текущей ноды
2. Поднимается по цепочке `@parent`, сбрасывая кеш каждого предка
3. Short-circuit: останавливается если `@parent == nil` или кеш уже `nil`

**Sibling-ноды сохраняют свой кеш.** При re-render корня неизменённые поддеревья возвращают кешированный HTML за O(1).

```ruby
dashboard = Nodex.div([widget_a, widget_b, widget_c])
dashboard.to_html     # рендерит всё, кеширует каждое поддерево

widget_b.set_text("updated")  # сбрасывает: widget_b → dashboard
                               # widget_a и widget_c — кеш сохранён
dashboard.to_html     # переиспользует кеш widget_a и widget_c
```

Перехватываемые методы: `set_attr`, `set_style`, `add_class`, `set_class`, `set_id`, `set_text`, `append`, `prepend`, `styles`.

## Batch styles

```ruby
node.styles(color: "red", padding: "10px", font_size: "2em")
# эквивалентно:
node.color("red").padding("10px").font_size("2em")
# но один сброс кеша вместо трёх
```

## Thread Safety (v1.1)

C extension безопасен для многопоточного использования (Puma, Sidekiq):

- **Буферы рендеринга** — per-thread (`__thread`), каждый поток имеет свой буфер
- **Opcode stack** — локальный на вызов, не разделяется между потоками
- **Baked registry** — `pthread_mutex` при регистрации, lock-free при рендере
- **Inja template_dir** — `std::shared_mutex` (shared read, exclusive write)

Безопасно вызывать `to_html`, `render_baked`, `build`, `render_template` из любого потока.

## DOCX / ODT Export

Нативный экспорт Node tree в DOCX и ODT. Zero dependencies — ZIP + XML в C++:

```ruby
File.binwrite("report.docx", tree.to_docx)
File.binwrite("report.odt", tree.to_odt)
```

ГОСТ пресет для академических документов:

```ruby
Nodex::Doc.to_docx(tree, preset: :gost, page_numbers: true)
```

Разрывы страниц, колонтитулы, дефолтный шрифт/размер, абзацный отступ, межстрочный интервал.

Подробнее: [docx-odt](docx-odt.md)

## Установка

```bash
cd nodex-native
rake compile
ruby test/test_native.rb   # тесты рендера
ruby test/test_docx.rb     # тесты DOCX/ODT
```

Зависимости: Ruby >= 3.0, CRuby only (ROBJECT_IVPTR — MRI-специфичный). `to_html_ruby` остаётся доступным как fallback.
