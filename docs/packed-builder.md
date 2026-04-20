# PackedBuilder

[← Главная](index.md) · [nodex-native](nodex-native.md) · [baked-templates](baked-templates.md) · [performance](performance.md)

## Концепция

DSL, который пишет бинарный поток опкодов вместо создания Node-объектов. C extension интерпретирует опкоды и рендерит HTML напрямую. Ноль аллокаций Ruby-объектов на элемент.

```
Ruby DSL → Binary opcodes (String) → C renderer → HTML String
```

## API

```ruby
html = Nodex::Native.build {
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

Блок выполняется в контексте `PackedBuilder`. Методы (`div`, `h1`, `p`, `a`, ...) пишут опкоды в бинарный буфер. Стили и атрибуты применяются через `Proxy`.

## Элементы

### Контейнерные

```ruby
Nodex::Native.build {
  div {
    section {
      article {
        p("Deep nesting")
      }
    }
  }
}
```

```html
<div><section><article><p>Deep nesting</p></article></section></div>
```

Доступные контейнеры: `div`, `section`, `nav`, `header`, `footer`, `ul`, `table`, `form`, `article`, `aside`, `main`.

### Текстовые

```ruby
Nodex::Native.build {
  div {
    h1("Title").bold
    p("Paragraph").color("#666")
  }
}
```

```html
<div>
  <h1 style="font-weight: bold">Title</h1>
  <p style="color: #666">Paragraph</p>
</div>
```

### Void

```ruby
Nodex::Native.build {
  img(src: "/photo.png", alt: "Photo")
  br
  hr
  input(type: "text", name: "q")
  meta(charset: "UTF-8")
}
```

```html
<img src="/photo.png" alt="Photo">
<br>
<hr>
<input type="text" name="q">
<meta charset="UTF-8">
```

### Document

```ruby
Nodex::Native.build {
  document("My Page") {
    h1("Hello")
    p("World")
  }
}
```

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>My Page</title>
</head>
<body>
  <h1>Hello</h1>
  <p>World</p>
</body>
</html>
```

### Raw HTML и текст

```ruby
Nodex::Native.build {
  div {
    text("Escaped: <script>")
    raw("<b>Unescaped HTML</b>")
  }
}
```

```html
<div>Escaped: &lt;script&gt;<b>Unescaped HTML</b></div>
```

## Proxy — стили и атрибуты

Каждый элемент возвращает `Proxy` с chainable методами:

```ruby
Nodex::Native.build {
  div {
    h1("Title").bold.italic.color("blue").set_id("main-title")
    button("Load").hx_get("/api").hx_target("#content").hx_swap("innerHTML")
  }.add_class("container").set_id("app")
}
```

```html
<div class="container" id="app">
  <h1 id="main-title" style="font-weight: bold; font-style: italic; color: blue">Title</h1>
  <button hx-get="/api" hx-target="#content" hx-swap="innerHTML">Load</button>
</div>
```

Полный список Proxy-методов идентичен Node chainable API: типографика, цвета, layout, размеры, позиционирование, HTMX.

## Опкоды

| Код | Имя | Формат | Описание |
|-----|-----|--------|----------|
| `0x01` | OPEN | `tag_len:u16 + tag` | Открыть элемент |
| `0x02` | CLOSE | — | Закрыть элемент (`</tag>`) |
| `0x03` | TEXT | `len:u16 + text` | Текстовый узел (escaped) |
| `0x04` | RAW | `len:u16 + html` | Сырой HTML (verbatim) |
| `0x05` | ATTR | `kl:u16 + key + vl:u16 + val` | Атрибут |
| `0x06` | CLASS | `len:u16 + class` | CSS class |
| `0x07` | SETID | `len:u16 + id` | id |
| `0x08` | STYLE | `kl:u16 + prop + vl:u16 + val` | CSS style |
| `0x09` | VCLOSE | — | Закрыть void элемент |
| `0x0A` | DOCTYPE | — | `<!DOCTYPE html>\n` |

## Ограничения

- Максимальная глубина вложенности — 64 (`MAX_DEPTH`)
- Максимум 8 классов на элемент (`MAX_CLS`)
- Максимум 16 стилей на элемент (`MAX_STY`)
- Максимум 16 атрибутов на элемент (`MAX_ATTR`)
- Длина строки — до 65535 байт (uint16)
- CRuby only

## Когда использовать

| Сценарий | PackedBuilder? |
|----------|---------------|
| Большие списки с вычисляемым контентом | Да — нет Node-аллокаций |
| Дашборды с частыми обновлениями | Да — минимальный GC pressure |
| Шаблоны с фиксированной структурой | Нет — Baked Templates быстрее |
| Страницы с условной логикой | Да — обычный Ruby control flow |
| Интеграция с существующим Node API | Нет — PackedBuilder не создаёт Node |
