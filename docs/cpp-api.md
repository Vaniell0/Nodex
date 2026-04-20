# C++ API

Пространство имён: `nodex`. Единая точка входа: `#include <nodex/nodex.hpp>`.

---

## Node / Element

```cpp
using Element  = std::shared_ptr<Node>;
using Elements = std::vector<Element>;
using Attrs    = std::map<std::string, std::string>;
```

`Element` --- основной тип библиотеки. Все фабричные функции возвращают `Element`. Класс `Node` наследуется от `std::enable_shared_from_this<Node>`.

### Жизненный цикл

```
create -> mutate -> render -> cache -> invalidate
```

1. **create** --- фабричная функция (`div()`, `h1()`, ...) создаёт узел.
2. **mutate** --- цепочка вызовов `Set*` / `Add*` / `Remove*` модифицирует узел. Все мутаторы возвращают `Element` (fluent API).
3. **render** --- рендерер (`HtmlRenderer`, `JsonRenderer`, `HtmxRenderer`) обходит дерево.
4. **cache** --- результат рендера сохраняется в `html_cache_` через `SetHtmlCache()`.
5. **invalidate** --- `InvalidateCache()` сбрасывает кеш узла и всех его предков (bubble-up).

### Конструкторы

| Сигнатура | Описание |
|-----------|----------|
| `Node(string tag)` | Пустой узел с тегом |
| `Node(string tag, Elements children)` | Узел с дочерними элементами |
| `Node(string tag, string text_content)` | Листовой узел с текстом |

### Методы

#### Тег

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `Tag()` | `const string&` | Получить имя тега |
| `SetTag(tag)` | `Element` | Изменить тег |

#### Текстовое содержимое

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `TextContent()` | `const string&` | Получить текст листового узла |
| `SetTextContent(content)` | `Element` | Задать текст |

#### Атрибуты

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `SetAttribute(key, value)` | `Element` | Установить атрибут |
| `RemoveAttribute(key)` | `Element` | Удалить атрибут |
| `GetAttribute(key)` | `string` | Получить значение атрибута |
| `HasAttribute(key)` | `bool` | Проверить наличие атрибута |
| `Attributes()` | `const Attrs&` | Все атрибуты (map) |

#### ID

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `SetID(id)` | `Element` | Установить `id` |
| `GetID()` | `string` | Получить `id` |

#### CSS-классы

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `SetClass(cls)` | `Element` | Заменить все классы одним |
| `AddClass(cls)` | `Element` | Добавить класс |
| `RemoveClass(cls)` | `Element` | Удалить класс |
| `HasClass(cls)` | `bool` | Проверить наличие класса |
| `ClassString()` | `string` | Классы через пробел |
| `Classes()` | `const vector<string>&` | Вектор классов |

#### Inline-стили

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `SetStyle(property, value)` | `Element` | Установить CSS-свойство |
| `RemoveStyle(property)` | `Element` | Удалить CSS-свойство |
| `GetStyle(property)` | `string` | Получить значение свойства |
| `SetStyleString(full_style)` | `Element` | Задать строку стилей целиком |
| `StyleString()` | `string` | Стили в виде строки |
| `Styles()` | `const map<string,string>&` | Все стили (map) |

#### Дочерние узлы

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `AppendChild(child)` | `Element` | Добавить в конец |
| `PrependChild(child)` | `Element` | Добавить в начало |
| `RemoveChild(index)` | `Element` | Удалить по индексу |
| `InsertChild(index, child)` | `Element` | Вставить по индексу |
| `Children()` | `const Elements&` | Все дочерние элементы |
| `ChildCount()` | `size_t` | Количество дочерних |

#### Родитель

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `Parent()` | `weak_ptr<Node>` | Слабая ссылка на родителя |

#### Кеш рендера

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `HtmlCache()` | `const string&` | Закешированный HTML |
| `SetHtmlCache(html)` | `void` | Записать в кеш (mutable) |
| `InvalidateCache()` | `void` | Сбросить кеш поддерева (bubble-up) |

#### Прочее

| Метод | Возвращает | Описание |
|-------|------------|----------|
| `IsSelfClosing()` | `bool` | Самозакрывающийся тег (`<br>`, `<img>`, ...) |
| `ClearStyles()` | `Element` | Удалить все стили |
| `ClearClasses()` | `Element` | Удалить все классы |
| `ClearAttributes()` | `Element` | Удалить все атрибуты |
| `Clone()` | `Element` | Глубокая копия поддерева |
| `IsRaw()` | `bool` | Узел содержит сырой HTML |
| `SetRaw(bool)` | `Element` | Включить/выключить режим сырого HTML |
| `EscapeHTML(text)` | `string` | Экранирование `<>&"` (статический) |
| `ToJSON()` | `json` | Сериализация узла в JSON |
| `FromJSON(j)` | `Element` | Десериализация из JSON (статический) |

### Пример

```cpp
#include <nodex/nodex.hpp>
using namespace nodex;

auto card = div({
    h1("Title"),
    p("Content")
});
card->SetID("my-card")
    ->AddClass("card")
    ->SetStyle("padding", "16px");

HtmlRenderer renderer;
std::string html = renderer.Render(card);
```

---

## Elements (elements.hpp)

Более 70 фабричных функций. Каждая возвращает `Element`. Большинство принимает необязательный `Attrs` для произвольных атрибутов.

### Текст

| Функция | Описание |
|---------|----------|
| `text(content [, attrs])` | Текстовый узел `<span>` |
| `paragraph(content [, attrs])` / `paragraph(children)` | `<p>` |
| `heading(level, content [, attrs])` | `<h1>`...`<h6>` по уровню |
| `h1(content)` ... `h6(content)` | Сокращения для `heading()` |
| `code(content)` | `<code>` |
| `pre(content)` | `<pre>` |
| `blockquote(content)` / `blockquote(children)` | `<blockquote>` |

### Контейнеры

Все контейнеры принимают `Elements children = {}` и необязательный `Attrs`.

| Функция | HTML-тег |
|---------|----------|
| `div` | `<div>` |
| `section` | `<section>` |
| `article` | `<article>` |
| `nav` | `<nav>` |
| `header` | `<header>` |
| `footer` | `<footer>` |
| `main_elem` | `<main>` |
| `aside` | `<aside>` |
| `span(children)` / `span(content [, attrs])` | `<span>` |

### Разметка (Layout)

| Функция | Описание |
|---------|----------|
| `hbox(children [, attrs])` | Flex-контейнер `flex-direction: row` |
| `vbox(children [, attrs])` | Flex-контейнер `flex-direction: column` |
| `grid(children, columns [, attrs])` | CSS Grid с заданным числом колонок |

### Списки

| Функция | Описание |
|---------|----------|
| `ul(items [, attrs])` | `<ul>` |
| `ol(items [, attrs])` | `<ol>` |
| `li(content)` / `li(children)` | `<li>` |

### Таблицы

| Функция | Описание |
|---------|----------|
| `table(rows [, attrs])` | `<table>` |
| `thead(rows)` | `<thead>` |
| `tbody(rows)` | `<tbody>` |
| `tr(cells)` | `<tr>` |
| `th(content)` / `th(children)` | `<th>` |
| `td(content)` / `td(children)` | `<td>` |

### Формы

| Функция | Сигнатура |
|---------|-----------|
| `form` | `form(children [, attrs])` |
| `input` | `input(type [, attrs])` |
| `textarea` | `textarea(content [, attrs])` |
| `select` | `select(options [, attrs])` |
| `option` | `option(label, value)` |
| `button` | `button(label [, attrs])` |
| `label` | `label(content [, attrs])` |

### Медиа

| Функция | Описание |
|---------|----------|
| `img(src [, alt])` / `img(src, attrs)` | `<img>` |
| `video(src [, attrs])` / `video(sources [, attrs])` | `<video>` |
| `audio(src [, attrs])` / `audio(sources [, attrs])` | `<audio>` |
| `canvas([attrs])` | `<canvas>` |
| `source(src, type)` | `<source>` |
| `picture(sources, fallback_img)` | `<picture>` |
| `figure(content, caption)` / `figure(children, caption)` | `<figure>` + `<figcaption>` |
| `iframe(src [, attrs])` | `<iframe>` |
| `svg(content [, attrs])` | `<svg>` (сырой SVG) |

### Ссылки

| Функция | Описание |
|---------|----------|
| `a(content, href [, target])` | `<a>` с текстом |
| `a(child, href [, target])` | `<a>` с дочерним элементом |

По умолчанию `target = "_self"`.

### Семантические inline-элементы

| Функция | HTML-тег |
|---------|----------|
| `strong(content)` | `<strong>` |
| `em(content)` | `<em>` |
| `mark(content)` | `<mark>` |
| `small(content)` | `<small>` |
| `sub(content)` | `<sub>` |
| `sup(content)` | `<sup>` |
| `br()` | `<br>` |
| `hr()` | `<hr>` |

### Интерактивные элементы

| Функция | Описание |
|---------|----------|
| `details(children, summary_text)` / `details(children, summary_elem)` | `<details>` |
| `summary(content)` | `<summary>` |
| `dialog(children [, attrs])` | `<dialog>` |
| `template_elem(children)` | `<template>` |

### Данные и семантика

| Функция | Описание |
|---------|----------|
| `time_elem(content, datetime)` | `<time datetime="...">` |
| `abbr(content, title)` | `<abbr title="...">` |
| `progress(value [, max=100])` | `<progress>` |
| `meter(value [, min=0, max=100])` | `<meter>` |
| `datalist(id, options)` | `<datalist>` |
| `output_elem([attrs])` | `<output>` |

### Структура документа

| Функция | Описание |
|---------|----------|
| `html_elem(children [, attrs])` | `<html>` |
| `head_elem(children)` | `<head>` |
| `body_elem(children [, attrs])` | `<body>` |
| `title_elem(text)` | `<title>` |
| `meta(attrs)` | `<meta>` |
| `link_elem(attrs)` | `<link>` |
| `script(src)` | `<script src="...">` |
| `script_inline(code)` | `<script>...код...</script>` |
| `style_elem(css)` | `<style>` |
| `document(title, head_extra, body_children [, body_attrs])` | Полный HTML-документ с `<!DOCTYPE html>` |

### Файловые помощники

| Функция | Описание |
|---------|----------|
| `stylesheet(href [, attrs])` | `<link rel="stylesheet" href="...">` |
| `style_file(path)` | `<style>` с содержимым файла |
| `script_file(path)` | `<script>` с содержимым файла |
| `html_file(path)` | `raw()` с содержимым HTML-файла |
| `google_font(family)` | `<link>` для Google Fonts |

### Сырой HTML

| Функция | Описание |
|---------|----------|
| `raw(html)` | Вставка HTML без экранирования |

### Прочее

| Функция | Описание |
|---------|----------|
| `separator()` | Совместимость (`<hr>`) |

### Пример

```cpp
using namespace nodex;

auto page = document("Dashboard", {
    stylesheet("/css/app.css"),
    google_font("Inter")
}, {
    header({ nav({ a("Home", "/"), a("About", "/about") }) }),
    main_elem({
        h1("Dashboard"),
        grid({
            div({ h3("Users"), p("1,024") }),
            div({ h3("Revenue"), p("$48K") }),
            div({ h3("Orders"), p("312") })
        }, 3),
        table({
            thead({ tr({ th("Name"), th("Status") }) }),
            tbody({
                tr({ td("Alice"), td("Active") }),
                tr({ td("Bob"),   td("Pending") })
            })
        })
    }),
    footer({ p("(c) 2025 Nodex") })
});
```

---

## Decorators (decorators.hpp)

Декораторы --- функциональные объекты, модифицирующие `Element`. Применяются через оператор `|`.

### Структура

```cpp
struct Decorator {
    std::function<Element(Element)> apply;
    Element operator()(Element elem) const;
};
```

### Операторы

| Оператор | Описание |
|----------|----------|
| `element \| Decorator()` | Применить декоратор, вернуть новый `Element` |
| `element \|= Decorator()` | Применить декоратор in-place |
| `elements \| Decorator()` | Применить ко всем элементам вектора |
| `Decorator() \| Decorator()` | Композиция декораторов |

```cpp
// Композиция: создать составной декоратор
auto danger = Bold() | Color("red") | FontSize(18);
auto title = h1("Error") | danger;
```

### Стиль текста (in-place)

| Декоратор | Описание |
|-----------|----------|
| `Bold()` | `font-weight: bold` |
| `Italic()` | `font-style: italic` |
| `Underline()` | `text-decoration: underline` |
| `Strikethrough()` | `text-decoration: line-through` |
| `Dim()` | `opacity: 0.5` |
| `Color(color)` | `color` |
| `BgColor(color)` | `background-color` |
| `FontSize(size)` / `FontSize(px)` | `font-size` (строка или px) |
| `FontFamily(family)` | `font-family` |
| `Opacity(value)` | `opacity` (float 0..1) |

### Выравнивание (in-place)

| Декоратор | Описание |
|-----------|----------|
| `Center()` | `text-align: center` |
| `AlignLeft()` | `text-align: left` |
| `AlignCenter()` | `text-align: center` |
| `AlignRight()` | `text-align: right` |
| `AlignTop()` | `vertical-align: top` |
| `AlignMiddle()` | `vertical-align: middle` |
| `AlignBottom()` | `vertical-align: bottom` |

### Блочная модель (in-place)

| Декоратор | Описание |
|-----------|----------|
| `Margin(all)` | Отступ со всех сторон (px) |
| `Margin(v, h)` | Вертикальный и горизонтальный отступ |
| `Margin(top, right, bottom, left)` | Отступ по сторонам |
| `Padding(all)` | Внутренний отступ (px) |
| `Padding(v, h)` | Вертикальный и горизонтальный |
| `Padding(top, right, bottom, left)` | По сторонам |
| `Border(thickness, color, style)` | `border` (по умолчанию `1px black solid`) |
| `BorderRadius(radius)` / `BorderRadius(px)` | `border-radius` |
| `Width(w)` | `width` |
| `Height(h)` | `height` |
| `FlexGrow(value)` | `flex-grow` (по умолчанию 1) |

### Структурные (оборачивают элемент)

| Декоратор | Описание |
|-----------|----------|
| `Hyperlink(url [, target])` | Оборачивает в `<a>` (по умолчанию `_blank`) |

### Атрибуты

| Декоратор | Описание |
|-----------|----------|
| `SetAttr(key, value)` | Произвольный атрибут |
| `SetStyle(style_string)` | Строка стилей целиком |
| `SetClass(cls)` | Заменить класс |
| `AddClass(cls)` | Добавить класс |
| `SetID(id)` | Установить `id` |
| `Data(key, value)` | `data-*` атрибут |

### Визуальные эффекты

| Декоратор | Описание |
|-----------|----------|
| `Transform(transform)` | `transform` |
| `BoxShadow(shadow)` | `box-shadow` |
| `TextShadow(shadow)` | `text-shadow` |
| `Filter(filter)` | `filter` |
| `BackdropFilter(filter)` | `backdrop-filter` |
| `Transition(property [, duration, easing])` | `transition` (по умолчанию `0.3s ease`) |
| `TransitionAll([duration, easing])` | `transition: all ...` |

### Позиционирование

| Декоратор | Описание |
|-----------|----------|
| `Position(pos)` | `position` (`relative`, `absolute`, ...) |
| `ZIndex(z)` | `z-index` |
| `Top(val)` / `Right(val)` / `Bottom(val)` / `Left(val)` | Смещение |
| `Inset(val)` | `inset` |
| `Overflow(overflow)` | `overflow` |
| `OverflowX(overflow)` / `OverflowY(overflow)` | По оси |

### Разметка (Layout)

| Декоратор | Описание |
|-----------|----------|
| `Gap(gap)` / `Gap(px)` | `gap` |
| `RowGap(gap)` | `row-gap` |
| `ColumnGap(gap)` | `column-gap` |
| `JustifyContent(jc)` | `justify-content` |
| `AlignItems(ai)` | `align-items` |
| `AlignSelf(as)` | `align-self` |
| `FlexWrap([wrap])` | `flex-wrap` (по умолчанию `"wrap"`) |
| `FlexShrink(value)` | `flex-shrink` |
| `FlexBasis(basis)` | `flex-basis` |
| `GridColumn(col)` | `grid-column` |
| `GridRow(row)` | `grid-row` |

### Взаимодействие

| Декоратор | Описание |
|-----------|----------|
| `Cursor(cursor)` | `cursor` |
| `UserSelect(select)` | `user-select` |
| `PointerEvents(pe)` | `pointer-events` |

### CSS

| Декоратор | Описание |
|-----------|----------|
| `CSSVar(name, value)` | CSS-переменная (`--name: value`) |
| `Display(display)` | `display` |
| `Visibility(vis)` | `visibility` |

### Типографика

| Декоратор | Описание |
|-----------|----------|
| `LetterSpacing(spacing)` | `letter-spacing` |
| `LineHeight(height)` | `line-height` |
| `TextTransform(transform)` | `text-transform` |
| `WordBreak(wb)` | `word-break` |
| `WhiteSpace(ws)` | `white-space` |

### Размеры

| Декоратор | Описание |
|-----------|----------|
| `MinWidth(w)` | `min-width` |
| `MaxWidth(w)` | `max-width` |
| `MinHeight(h)` | `min-height` |
| `MaxHeight(h)` | `max-height` |

### HTMX

| Декоратор | HTML-атрибут |
|-----------|--------------|
| `HxGet(url)` | `hx-get` |
| `HxPost(url)` | `hx-post` |
| `HxPut(url)` | `hx-put` |
| `HxPatch(url)` | `hx-patch` |
| `HxDelete(url)` | `hx-delete` |
| `HxTarget(selector)` | `hx-target` |
| `HxSwap(strategy)` | `hx-swap` |
| `HxTrigger(trigger)` | `hx-trigger` |
| `HxPushUrl([url])` | `hx-push-url` (по умолчанию `"true"`) |
| `HxSelect(selector)` | `hx-select` |
| `HxVals(json_string)` | `hx-vals` |
| `HxConfirm(message)` | `hx-confirm` |
| `HxIndicator(selector)` | `hx-indicator` |
| `HxBoost([enable])` | `hx-boost` (по умолчанию `true`) |

### Дополнительные

| Декоратор | Описание |
|-----------|----------|
| `AspectRatio(ratio)` | `aspect-ratio` |
| `ObjectFit(fit)` | `object-fit` |
| `TextOverflow([overflow])` | `text-overflow` (по умолчанию `"ellipsis"`) |
| `Gradient(gradient)` | `background` (градиент) |
| `Outline(thickness, color, style)` | `outline` (по умолчанию `1px black solid`) |
| `OutlineOffset(offset)` | `outline-offset` |
| `Resize([resize])` | `resize` (по умолчанию `"both"`) |
| `ScrollBehavior([behavior])` | `scroll-behavior` (по умолчанию `"smooth"`) |

### Пример

```cpp
using namespace nodex;

auto btn = button("Click")
    | Bold()
    | Padding(12, 24)
    | Color("white")
    | BgColor("#007bff")
    | BorderRadius(8)
    | Cursor("pointer")
    | Transition("background-color", "0.2s")
    | HxPost("/api/click")
    | HxTarget("#result");

// Композиция для повторного использования
auto card_style = Padding(16) | Border(1, "#ddd") | BorderRadius(12) | BoxShadow("0 2px 8px rgba(0,0,0,0.1)");

auto card1 = div({ h3("Card 1"), p("Content") }) | card_style;
auto card2 = div({ h3("Card 2"), p("Content") }) | card_style;
```

---

## Renderer (renderer.hpp)

Три рендерера, наследующих абстрактный базовый класс:

```cpp
class Renderer {
public:
    virtual ~Renderer() = default;
    virtual std::string Render(const Element& root) const = 0;
};
```

### HtmlRenderer

Рендерит дерево в HTML-строку. Поддерживает кеш поддеревьев (`HtmlCache`).

#### Опции

| Поле | Тип | По умолчанию | Описание |
|------|-----|--------------|----------|
| `pretty` | `bool` | `false` | Форматированный вывод с отступами |
| `indent_size` | `int` | `2` | Размер отступа (пробелы) |
| `minify` | `bool` | `false` | Минификация (удаление лишних пробелов) |

#### Методы

| Метод | Описание |
|-------|----------|
| `Render(root)` | Рендер дерева в строку (использует кеш) |
| `RenderToString(root)` | Статический метод-обёртка |

```cpp
using namespace nodex;

// Компактный рендер (по умолчанию)
HtmlRenderer compact;
std::string html = compact.Render(root);

// Форматированный вывод
HtmlRenderer pretty({.pretty = true, .indent_size = 4});
std::string formatted = pretty.Render(root);

// Минификация
HtmlRenderer minified({.minify = true});
std::string small = minified.Render(root);

// Статический вызов
std::string quick = HtmlRenderer::RenderToString(root);
```

### JsonRenderer

Сериализует дерево элементов в JSON (AST).

#### Опции

| Поле | Тип | По умолчанию | Описание |
|------|-----|--------------|----------|
| `indent` | `int` | `-1` | `-1` --- компактный; `2`, `4` --- форматированный |

```cpp
using namespace nodex;

JsonRenderer compact;
std::string json = compact.Render(root);  // {"tag":"div",...}

JsonRenderer pretty({.indent = 2});
std::string formatted = pretty.Render(root);
```

### HtmxRenderer

Рендерит HTML-фрагменты для HTMX-ответов. Внутри использует `HtmlRenderer`.

#### Опции

| Поле | Тип | По умолчанию | Описание |
|------|-----|--------------|----------|
| `oob` | `bool` | `false` | Добавить `hx-swap-oob="true"` к корневому элементу |
| `swap_strategy` | `string` | `""` | Стратегия замены (`innerHTML`, `outerHTML`, ...) |

```cpp
using namespace nodex;

// Обычный фрагмент
HtmxRenderer htmx;
std::string fragment = htmx.Render(div({ p("Updated content") }));

// Out-of-band swap
HtmxRenderer oob({.oob = true});
auto notification = div({ p("Saved!") });
notification->SetID("notification");
std::string oob_html = oob.Render(notification);
// <div id="notification" hx-swap-oob="true"><p>Saved!</p></div>
```

---

## Registry (registry.hpp)

Потокобезопасный реестр фабрик компонентов и страниц.

### Типы

```cpp
using ComponentFactory = std::function<Element(const nlohmann::json& data)>;
using PageFactory      = std::function<Element(const nlohmann::json& data)>;
```

### Методы: компоненты

| Метод | Описание |
|-------|----------|
| `RegisterComponent(name, factory)` | Зарегистрировать фабрику компонента |
| `UnregisterComponent(name)` | Удалить регистрацию |
| `HasComponent(name)` | Проверить наличие |
| `CreateComponent(name [, data])` | Вызвать фабрику, получить `Element` |
| `ComponentNames()` | Список зарегистрированных имён |

### Методы: страницы

| Метод | Описание |
|-------|----------|
| `RegisterPage(route, factory)` | Зарегистрировать фабрику страницы |
| `UnregisterPage(route)` | Удалить регистрацию |
| `HasPage(route)` | Проверить наличие |
| `CreatePage(route [, data])` | Вызвать фабрику, получить `Element` |
| `PageRoutes()` | Список зарегистрированных маршрутов |

### Потокобезопасность

Реестр использует `std::shared_mutex`:
- **Чтение** (`Has*`, `Create*`, `*Names`, `*Routes`) --- `shared_lock` (параллельные чтения).
- **Запись** (`Register*`, `Unregister*`) --- `unique_lock` (эксклюзивная блокировка).

Фабрика выполняется **за пределами** блокировки: мьютекс удерживается только на время копирования `std::function`, после чего вызов происходит без блокировки.

### Пример

```cpp
using namespace nodex;

Registry registry;

// Регистрация компонента
registry.RegisterComponent("navbar", [](const json& data) {
    return nav({
        a("Home", "/"),
        a("About", "/about"),
        a("Contact", "/contact")
    });
});

// Регистрация страницы
registry.RegisterPage("/", [&registry](const json& data) {
    return document("Home", {}, {
        registry.CreateComponent("navbar", data),
        main_elem({
            h1("Welcome"),
            p(data.value("message", "Hello, World!"))
        })
    });
});

// Использование
nlohmann::json data = {{"message", "Welcome to Nodex"}};
auto page = registry.CreatePage("/", data);

HtmlRenderer renderer({.pretty = true});
std::string html = renderer.Render(page);

// Интроспекция
auto names = registry.ComponentNames();  // {"navbar"}
auto routes = registry.PageRoutes();     // {"/"}
```

---

## TemplateEngine (template_engine.hpp)

Обёртка над движком [Inja](https://github.com/pantor/inja) (Jinja2-совместимый синтаксис).

### Методы

| Метод | Описание |
|-------|----------|
| `SetTemplateDirectory(dir)` | Задать базовую директорию для файлов шаблонов |
| `Render(template_str, data)` | Рендер строки-шаблона с подстановкой данных |
| `RenderFile(template_path, data)` | Рендер файла-шаблона (относительно базовой директории) |

Все методы статические.

### Синтаксис шаблонов

| Конструкция | Описание |
|-------------|----------|
| `{{ var }}` | Подстановка переменной |
| `{% if cond %}...{% endif %}` | Условие |
| `{% for item in list %}...{% endfor %}` | Цикл |
| `{% include "file.html" %}` | Включение файла |

### Пример

```cpp
using namespace nodex;

// Базовая подстановка
TemplateEngine::SetTemplateDirectory("templates/");

auto html = TemplateEngine::Render(
    "Hello {{ name }}! You have {{ count }} messages.",
    {{"name", "Alice"}, {"count", 5}}
);
// "Hello Alice! You have 5 messages."

// Рендер из файла
auto page = TemplateEngine::RenderFile("page.html", {
    {"title", "Dashboard"},
    {"users", {
        {{"name", "Alice"}, {"role", "admin"}},
        {{"name", "Bob"},   {"role", "user"}}
    }}
});
```

Файл `templates/page.html`:

```html
<!DOCTYPE html>
<html>
<head><title>{{ title }}</title></head>
<body>
  <h1>{{ title }}</h1>
  {% if users %}
  <ul>
    {% for user in users %}
    <li>{{ user.name }} ({{ user.role }})</li>
    {% endfor %}
  </ul>
  {% endif %}
</body>
</html>
```
