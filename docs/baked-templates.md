# Baked Templates

[← Главная](index.md) · [nodex-native](nodex-native.md) · [packed-builder](packed-builder.md) · [performance](performance.md)

## Концепция

Baked template — Node-дерево, скомпилированное в массив статических HTML-чанков и список слотов. При рендере: конкатенация чанков + HTML-escape параметров. Без обхода дерева, без создания Node-объектов.

```
Компиляция (один раз):
  Node tree → to_html → split по маркерам → chunks[] + slot_names[]

Рендер (каждый раз):
  chunks[0] + escape(params[:title]) + chunks[1] + escape(params[:desc]) + chunks[2]
```

## API

### Компиляция

```ruby
Nodex::Native.bake(:card, Nodex.div([
  Nodex.h1(Nodex.slot(:title)).bold.color("#333"),
  Nodex.p(Nodex.slot(:desc)).padding("10px"),
  Nodex.a("Link", href: Nodex.slot(:link)),
]).add_class("card"))
```

`Nodex.slot(:name)` — маркер слота. При рендере Node-дерева он превращается в `__Nodex_SLOT_name__`, затем `bake()` разрезает HTML по маркерам.

### Рендер

```ruby
Nodex::Native.render_baked(:card,
  title: "Project X",
  desc: "A cool project",
  link: "/projects/x"
)
```

```html
<div class="card">
  <h1 style="font-weight: bold; color: #333">Project X</h1>
  <p style="padding: 10px">A cool project</p>
  <a href="/projects/x" target="_self">Link</a>
</div>
```

Параметры автоматически HTML-экранируются.

### Встраивание в дерево

```ruby
page = Nodex.div([
  Nodex::Native.baked_node(:card, title: "A", desc: "First", link: "/a"),
  Nodex::Native.baked_node(:card, title: "B", desc: "Second", link: "/b"),
])
puts page.to_html
```

```html
<div>
  <div class="card">
    <h1 style="font-weight: bold; color: #333">A</h1>
    <p style="padding: 10px">First</p>
    <a href="/a" target="_self">Link</a>
  </div>
  <div class="card">
    <h1 style="font-weight: bold; color: #333">B</h1>
    <p style="padding: 10px">Second</p>
    <a href="/b" target="_self">Link</a>
  </div>
</div>
```

`baked_node` рендерит шаблон и оборачивает в `Nodex.raw()`.

### Простой шаблон

```ruby
Nodex::Native.bake(:greeting, Nodex.div([
  Nodex.h1(Nodex.slot(:title)).bold,
  Nodex.p(Nodex.slot(:body)),
]).add_class("card"))

Nodex::Native.render_baked(:greeting, title: "Hello", body: "World")
```

```html
<div class="card">
  <h1 style="font-weight: bold">Hello</h1>
  <p>World</p>
</div>
```

## Внутреннее устройство

### Ruby сторона (`native.rb`)

```ruby
def self.bake(name, template_node)
  html = template_node.to_html_native
  parts = html.split(/__Nodex_SLOT_(\w+)__/, -1)
  chunks = parts.values_at(*(0...parts.size).step(2))
  slot_names = parts.values_at(*(1...parts.size).step(2)).map(&:to_sym)
  NativeBaked.register_baked(name.to_sym, chunks, slot_names)
end
```

### C сторона (`nodex_native.c`)

Статические чанки копируются в C-owned память (`malloc`). Слоты хранятся как Ruby Symbol с GC mark.

При рендере:
1. Поиск шаблона по Symbol (линейный, до 64 шаблонов)
2. Цикл: `memcpy(chunk)` + `cbuf_escaped(param_value)`
3. Результат — Ruby String UTF-8

## Ограничения

- Параметры — только строки (или что-то с `.to_s`)
- Слоты не поддерживают вложенные Node-деревья — только текст

> **v1.1:** Лимиты `MAX_BAKED` и `MAX_SLOTS` сняты — используется динамический массив.

## Когда использовать

| Сценарий | Baked? |
|----------|--------|
| Список из N одинаковых карточек | Да — компилируем карточку, рендерим N раз |
| Таблица с динамическими данными | Да — строка таблицы как baked template |
| Форма с условной логикой | Нет — используйте Node API |
| Статическая страница | Нет — используйте Registry cache |
