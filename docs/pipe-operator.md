# Pipe-оператор `|`

[← Главная](index.md) · [ruby-dsl](ruby-dsl.md) · [components](components.md)

## Концепция

Вдохновлён C++ FTXUI, где элементы декорируются через `|`:

```cpp
// C++ FTXUI
text("hello") | bold | color(Color::Red);
```

В Nodex Ruby DSL:

```ruby
h1("Hello") | Bold() | Color("red") | Class("title")
```

```html
<h1 class="title" style="font-weight: bold; color: red">Hello</h1>
```

## Как работает

`Node#|` диспатчит по типу аргумента:

```ruby
def |(decorator)
  case decorator
  when Symbol then send(decorator)       # | :bold
  when Proc   then decorator.call(self)  # | Bold()
  when Array  then send(decorator[0], *decorator[1..])
  else self
  end
end
```

Фабрики-декораторы (`Bold()`, `Color()`, ...) возвращают `Proc`:

```ruby
def Bold() = ->(n) { n.bold }
def Color(c) = ->(n) { n.color(c) }
```

## Все декораторы

### Типографика

| Фабрика | Эквивалент |
|---------|-----------|
| `Bold()` | `.bold` |
| `Italic()` | `.italic` |
| `Underline()` | `.underline` |
| `Strikethrough()` | `.strikethrough` |
| `FontSize(s)` | `.font_size(s)` |
| `FontFamily(f)` | `.font_family(f)` |

### Цвета

| Фабрика | Эквивалент |
|---------|-----------|
| `Color(c)` | `.color(c)` |
| `BgColor(c)` | `.bg_color(c)` |

### Layout

| Фабрика | Эквивалент |
|---------|-----------|
| `Center()` | `.center` |
| `Padding(v)` | `.padding(v)` |
| `Margin(v)` | `.margin(v)` |
| `Width(w)` | `.width(w)` |
| `Height(h)` | `.height(h)` |
| `Gap(g)` | `.gap(g)` |
| `FlexWrap(w)` | `.flex_wrap(w)` |
| `FlexGrow(v)` | `.flex_grow(v)` |
| `Display(d)` | `.display(d)` |

### Визуальные

| Фабрика | Эквивалент |
|---------|-----------|
| `Border(b)` | `.border(b)` |
| `BorderRadius(r)` | `.border_radius(r)` |
| `Opacity(v)` | `.opacity(v)` |
| `BoxShadow(s)` | `.box_shadow(s)` |
| `Transform(t)` | `.transform(t)` |
| `Cursor(c)` | `.cursor(c)` |
| `Position(p)` | `.position(p)` |

### Transitions

```ruby
button("Hover me") | Transition("all", duration: "0.3s", easing: "ease")
```

```html
<button style="transition: all 0.3s ease">Hover me</button>
```

### Атрибуты

| Фабрика | Описание |
|---------|----------|
| `Class(cls)` | Установить class (заменяет) |
| `AddClass(cls)` | Добавить class |
| `Id(id)` | Установить id |
| `Style(prop, val)` | Установить inline style |
| `Attr(key, val)` | Произвольный атрибут |
| `Data(key, val)` | `data-*` атрибут |

### HTMX

| Фабрика | Атрибут |
|---------|---------|
| `HxGet(url)` | `hx-get` |
| `HxPost(url)` | `hx-post` |
| `HxTarget(sel)` | `hx-target` |
| `HxSwap(s)` | `hx-swap` |
| `HxTrigger(t)` | `hx-trigger` |

## Примеры

### Навигация

```ruby
nav([
  a("Home", href: "/") | AddClass("nav-link"),
  a("About", href: "/about") | AddClass("nav-link"),
]) | Class("navbar")
```

```html
<nav class="navbar">
  <a class="nav-link" href="/" target="_self">Home</a>
  <a class="nav-link" href="/about" target="_self">About</a>
</nav>
```

### Карточка

```ruby
div([
  h1("Project X").bold.color("#333"),
  p("A cool project").padding("10px"),
  a("View", href: "/projects/1") | AddClass("btn"),
]) | Class("card") | Border("1px solid #e5e7eb") | BorderRadius(8) | Padding("16px")
```

```html
<div class="card"
     style="border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px">
  <h1 style="font-weight: bold; color: #333">Project X</h1>
  <p style="padding: 10px">A cool project</p>
  <a class="btn" href="/projects/1" target="_self">View</a>
</div>
```

### HTMX кнопка

```ruby
button("Load More") | HxGet("/api/items") | HxTarget("#list") | HxSwap("beforeend")
```

```html
<button hx-get="/api/items" hx-target="#list" hx-swap="beforeend">Load More</button>
```

### Форма с HTMX

```ruby
form([
  input_elem("email", name: "email", placeholder: "you@example.com"),
  button("Subscribe") | HxPost("/api/subscribe") | HxTarget("#result"),
]) | Id("subscribe-form")
```

```html
<form id="subscribe-form">
  <input type="email" name="email" placeholder="you@example.com">
  <button hx-post="/api/subscribe" hx-target="#result">Subscribe</button>
</form>
```
