# DOCX / ODT Export

[← Главная](index.md) · [nodex-native](nodex-native.md) · [pdf](pdf.md)

Нативный экспорт Node tree в DOCX (Microsoft Word) и ODT (LibreOffice). Zero dependencies — ZIP + XML генерируются в C++. Без промежуточного HTML, без subprocess.

## Базовое использование

```ruby
require 'nodex'
require 'nodex/native'

doc = Nodex.div([
  Nodex.h1("Отчёт"),
  Nodex.p("Сгенерировано Nodex."),
])

# DOCX
File.binwrite("report.docx", doc.to_docx)

# ODT
File.binwrite("report.odt", doc.to_odt)
```

## API

### Node методы

```ruby
node.to_docx              # → String (binary DOCX ZIP)
node.to_docx(opts)        # → с опциями (Hash)
node.to_odt               # → String (binary ODT ZIP)
node.to_odt(opts)         # → с опциями (Hash)
```

### Native методы

```ruby
Nodex::Native.to_docx(node)
Nodex::Native.to_docx(node, "page_size" => "A4")
Nodex::Native.to_odt(node)
Nodex::Native.to_odt(node, "page_size" => "A4")
```

### Nodex::Doc — документ-ориентированный API

```ruby
Nodex::Doc.to_docx(node, preset: :gost)
Nodex::Doc.to_docx(node, preset: :gost, header: "Мой отчёт")
Nodex::Doc.to_odt(node, preset: :gost, page_numbers: true)
```

`preset:` загружает набор опций, keyword-аргументы мержатся поверх.

## Опции

### Страница

| Ключ | Тип | Описание | По умолчанию |
|------|-----|----------|-------------|
| `page_size` | `"A4"`, `"A3"`, `"Legal"` | Размер страницы | Letter (8.5×11") |
| `page_width` | CSS (`"210mm"`) | Ширина (перебивает preset) | — |
| `page_height` | CSS (`"297mm"`) | Высота | — |
| `margin_top` | CSS (`"20mm"`, `"1in"`) | Верхний отступ | 1in |
| `margin_bottom` | CSS | Нижний отступ | 1in |
| `margin_left` | CSS | Левый отступ | 1in |
| `margin_right` | CSS | Правый отступ | 1in |

### Шрифт и типографика

| Ключ | Тип | Описание | По умолчанию |
|------|-----|----------|-------------|
| `default_font` | String | Шрифт документа | Calibri |
| `default_font_size` | CSS (`"14pt"`) | Размер шрифта | 11pt |
| `line_spacing` | число (`"1.5"`) | Межстрочный интервал (множитель) | — |
| `first_line_indent` | CSS (`"1.25cm"`) | Абзацный отступ (красная строка) | — |

Значения `default_font` и `default_font_size` применяются к параграфам (`p`) если на элементе нет явного `.font_family()` / `.font_size()`. Также обновляют `w:docDefaults` (DOCX) и `style:default-style` (ODT).

`line_spacing` и `first_line_indent` применяются только к тегу `p` (не к заголовкам).

### Колонтитулы

| Ключ | Тип | Описание |
|------|-----|----------|
| `header` | String | Текст верхнего колонтитула |
| `footer` | String | Текст нижнего колонтитула |
| `page_numbers` | `true` | Добавить нумерацию страниц в footer |
| `page_number_align` | `"center"`, `"right"` | Выравнивание номера (default: center) |
| `first_page_footer` | String | Отдельный footer для титульной страницы |

```ruby
Nodex.p("Содержимое").to_docx({
  "header" => "Курсовая работа",
  "footer" => "Иванов И.И.",
  "page_numbers" => true,
  "page_number_align" => "center",
  "first_page_footer" => "Севастополь, 2026",
})
```

В DOCX номер страницы реализован через field code `PAGE \* MERGEFORMAT`. В ODT — через `<text:page-number>`.

При наличии `first_page_footer` DOCX включает `<w:titlePg/>` — первая страница использует отдельный footer.

## Пресеты

### GOST

Стандартное оформление для академических документов (курсовые, дипломы, рефераты):

```ruby
Nodex::Doc::GOST
# => {
#   "page_size" => "A4",
#   "margin_top" => "20mm", "margin_bottom" => "20mm",
#   "margin_left" => "30mm", "margin_right" => "15mm",
#   "default_font" => "Times New Roman",
#   "default_font_size" => "14pt",
#   "line_spacing" => "1.5",
#   "first_line_indent" => "1.25cm",
# }
```

```ruby
doc = Nodex.div([
  Nodex.h1("Введение"),
  Nodex.p("Текст введения..."),
  Nodex.page_break,
  Nodex.h1("Глава 1"),
  Nodex.p("Текст главы..."),
])

# ГОСТ с колонтитулами
File.binwrite("coursework.docx", Nodex::Doc.to_docx(doc,
  preset: :gost,
  header: "Курсовая работа",
  page_numbers: true,
  first_page_footer: "Севастополь, 2026",
))
```

## Разрывы страниц

### Фабрика

```ruby
Nodex.page_break          # в основном DSL
Nodex::Doc.page_break     # через Doc namespace
```

Оба возвращают `Node` с тегом `__page_break__`, который рендерится как:
- DOCX: `<w:br w:type="page"/>`
- ODT: `fo:break-before="page"` на пустом параграфе

### CSS page-break-before

```ruby
Nodex.p("Новая страница").set_style("page-break-before", "always")
```

Также работает для заголовков и других блочных элементов.

## Поддерживаемые элементы

| Элемент | DOCX | ODT |
|---------|------|-----|
| `h1`-`h6` | Heading1-6 стили, bold, размеры | `text:h` + outline-level |
| `p` | `w:p` с text runs | `text:p` |
| `strong`/`b` | `w:b` | `fo:font-weight="bold"` |
| `em`/`i` | `w:i` | `fo:font-style="italic"` |
| `u` | `w:u val="single"` | `style:text-underline-style` |
| `code` | Courier New | Courier New |
| `pre` | Courier New, preformatted | Courier New |
| `ul`/`ol` + `li` | `w:numPr` (bullet/decimal) | `text:list` |
| `table`/`tr`/`td`/`th` | `w:tbl` с borders | `table:table` |
| `a` | `w:hyperlink` + relationship | `text:a` + xlink |
| `img` | `w:drawing` + embedded в ZIP | `draw:frame` + embedded |
| `br` | `w:br` | `text:line-break` |
| `hr` | `w:pBdr` bottom border | Пустой параграф |
| `div`/`section`/`article` | Прозрачные контейнеры | Прозрачные контейнеры |

### Inline стили

| CSS | DOCX | ODT |
|-----|------|-----|
| `font-weight: bold` | `w:b` | `fo:font-weight="bold"` |
| `font-style: italic` | `w:i` | `fo:font-style="italic"` |
| `text-decoration: underline` | `w:u` | `style:text-underline-style` |
| `text-decoration: line-through` | `w:strike` | `style:text-line-through-style` |
| `color` | `w:color` | `fo:color` |
| `background-color` | `w:shd` | `fo:background-color` |
| `font-size` | `w:sz` (half-points) | `fo:font-size` (pt) |
| `font-family` | `w:rFonts` | `style:font-name` |
| `text-align` | `w:jc` (start/center/end/both) | `fo:text-align` |
| `text-indent` | `w:ind w:firstLine` | `fo:text-indent` |
| `margin` | `w:spacing before/after` | `fo:margin-*` |
| `padding` | `w:ind left/right` | `fo:margin-left/right` |
| `border` | `w:pBdr` | — |
| `page-break-before: always` | `w:br type="page"` | `fo:break-before="page"` |

### Таблицы: colspan / rowspan

```ruby
Nodex.node("td", text: "Wide", colspan: "2")    # colspan → w:gridSpan / table:number-columns-spanned
Nodex.node("td", text: "Tall", rowspan: "3")    # rowspan → w:vMerge / table:number-rows-spanned
```

## Архитектура

```
Node tree
  ├── DocxRenderer (nodex_docx.cpp)
  │     ├── walk() — рекурсивный обход, RunProps inheritance
  │     ├── write_ppr() / write_rpr() — paragraph / run props → OOXML
  │     ├── walk_table() — таблицы с thead/tbody
  │     ├── emit_image() — embedding в ZIP
  │     ├── header1_xml() / footer1_xml() / footer2_xml() — колонтитулы
  │     ├── document_xml() — w:body + w:sectPr
  │     ├── styles_xml() — docDefaults + Heading1-6
  │     └── ZipWriter — STORE-only ZIP (no compression)
  │
  └── OdtRenderer (nodex_docx.cpp)
        ├── walk() — рекурсивный обход
        ├── AutoStyle — собранные стили → office:automatic-styles
        ├── content_xml() — office:body
        ├── odt_styles_xml() — default-style + headings + master-page + header/footer
        └── ZipWriter — STORE-only ZIP
```

Zero dependencies — CRC-32, ZIP, XML генерируются в C++17 stdlib.
