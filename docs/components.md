# Компоненты и Registry

[← Главная](index.md) · [ruby-dsl](ruby-dsl.md) · [pipe-operator](pipe-operator.md) · [server](server.md)

## Registry

`Nodex::Registry` — центральный реестр компонентов и страниц. Компоненты — переиспользуемые блоки UI. Страницы — маршруты, которые возвращают полный HTML-документ.

```ruby
registry = Nodex::Registry.new
```

## Компоненты

```ruby
registry.register_component("navbar") do |data|
  nav([
    a("Главная", href: "/") | AddClass("nav-link"),
    a("О нас", href: "#about") | AddClass("nav-link"),
  ]) | Class("navbar")
end

navbar = registry.create_component("navbar", {})
puts navbar.to_html
```

```html
<nav class="navbar">
  <a class="nav-link" href="/" target="_self">Главная</a>
  <a class="nav-link" href="#about" target="_self">О нас</a>
</nav>
```

Блок получает `data` (Hash) — произвольные параметры при создании.

## Страницы

```ruby
registry.register_page("/") do |data|
  document("Главная",
    head: [stylesheet("/static/style.css")],
    body: [
      registry.create_component("navbar", data),
      h1("Hello"),
    ]
  )
end

# Проверка и создание
registry.has_page?("/")           # => true
page = registry.create_page("/")  # => Node
puts page.to_html
```

Параметризованные страницы:

```ruby
registry.register_page("/project") do |data|
  id = data[:id]
  document("Project #{id}",
    body: [h1("Project: #{id}")]
  )
end

page = registry.create_page("/project", { id: "nodex" })
```

## PageLoader — автозагрузка

`Nodex::PageLoader` автоматически загружает все `.rb` файлы из директории и вызывает `register(registry)`:

```ruby
loaded = Nodex::PageLoader.load_pages(registry, "ruby/pages/")
puts loaded  # => ["home"]
```

### Структура файла страницы

```ruby
# ruby/pages/home.rb
module Pages
  module Home
    extend Nodex::DSL
    module_function

    def register(registry)
      registry.register_component("header") do |_data|
        h1("Hello") | Bold() | Class("title")
      end

      registry.register_page("/") do |data|
        document("Home",
          body: [registry.create_component("header", data)]
        )
      end
    end
  end
end
```

Соглашения:
- Файл `ruby/pages/home.rb` → модуль `Pages::Home`
- Метод `register(registry)` вызывается автоматически
- `extend Nodex::DSL` даёт доступ к h1(), div(), Bold() без префикса

## Информация о реестре

```ruby
registry.page_routes      # => ["/", "/project"]
registry.component_names  # => ["navbar", "header", "about", ...]
registry.has_page?("/")   # => true
```

## UI::Component (v1.1)

Упрощённый API поверх baked templates:

```ruby
Nodex::UI::Component.bake(:card) { [Nodex.h1(Nodex.slot(:title)), Nodex.p(Nodex.slot(:body))] }
Nodex::UI::Component.render(:card, title: "Hello", body: "World")
Nodex::UI::Component.node(:card, title: "Hello", body: "World")  # → Nodex::Node
```

`bake` принимает блок, возвращающий массив Node. `render` возвращает HTML-строку. `node` возвращает `Nodex::Node` (через `Nodex.raw`), который можно встраивать в дерево.

## Hot-Reload

В dev mode при изменении `.rb` файла:

```ruby
load file                                    # перезагрузка файла
Pages.const_get(mod_name).register(registry) # перерегистрация
```

Подробнее: [hot-reload](hot-reload.md), [server](server.md)
