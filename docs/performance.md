# Performance

[← Главная](index.md) · [fwui-native](fwui-native.md) · [baked-templates](baked-templates.md) · [packed-builder](packed-builder.md)

## Бенчмарк

Дерево: 500 карточек, каждая: `div > h1 + p + a`, стили (bold, color, padding, margin), класс. 300 итераций, GC отключён.

```bash
cd fwui-native && rake compile && ruby test/bench_levels.rb
```

| Уровень | Метод | ms/render | vs Ruby |
|---------|-------|-----------|---------|
| L0 | Ruby `to_html` (baseline) | ~0.60 | 1.0x |
| L1 | C ext cold (build + render) | ~0.19 | 3.2x |
| L2 | Registry cache (frozen String) | ~0.003 | 200x |
| L3 | C ext cached (same tree) | <0.001 | >600x |
| L4 | Baked 500 cards (assemble) | ~0.50 | 1.2x |
| L5 | Baked 1 card | ~0.001 | 600x |
| L6 | PackedBuilder 500 cards | ~0.45 | 1.3x |

## Анализ

### L0 → L1: Ruby → C (3.2x)

Чистый выигрыш от C extension:
- Iterative render вместо рекурсии
- ROBJECT_IVPTR — O(1) доступ к ivars
- Один reusable буфер вместо String конкатенации
- 256-byte escape table без бранчей

### L1 → L3: Cold → Cached (>600x)

`@_html_cache` на Node. Если дерево не мутировалось — возвращаем строку за O(1). Идеально для статических компонентов в Registry.

### L5: Baked single card (~0.001ms)

Один baked template рендерится за микросекунды. Для списка из N карточек — рендерим N baked + оборачиваем в div. Основное время уходит на сборку, не на рендер отдельных карточек.

### L4 vs L6: Baked 500 vs PackedBuilder 500

Оба ~0.5ms — сопоставимы. Baked лучше когда шаблон фиксирован и параметров мало. PackedBuilder лучше когда логика сложная (условия, циклы, вычисления).

## Nil-init оптимизация

`Node#initialize` создаёт все 8 ivars как nil вместо Hash/Array:

```ruby
# До (0.2.0):
@attrs = {}; @styles = {}; @classes = []; @children = []

# После (1.0.0):
@attrs = nil; @styles = nil; @classes = nil; @children = nil
```

Результат: **~5500 меньше аллокаций** на дерево из 500 карточек. Hash/Array создаются лениво при первом использовании.

Это также включает ROBJECT_IVPTR в C extension — все 8 ivars гарантированно в фиксированных позициях.

## Subtree Cache (Partial Invalidation)

### Механизм

Каждый `Node` хранит ссылку `@parent` на родителя. При мутации (например `set_text`, `set_style`) вызывается `invalidate_cache!`, который:

1. Сбрасывает `@_html_cache` текущей ноды
2. Поднимается по цепочке `@parent` → сбрасывает кеш каждого предка
3. Останавливается при `@parent == nil` (корень) или если кеш уже `nil` (short-circuit)

Sibling-ноды и их поддеревья **не затрагиваются** — их кеш остаётся валидным.

### Dashboard бенчмарк

50 widgets, 500 тиков, 2 мутации/тик (bench_dashboard.rb):

| Widgets | Full rebuild (ms/tick) | Full re-render (ms/tick) | Partial (ms/tick) | Partial vs re-render |
|---------|----------------------|------------------------|-------------------|---------------------|
| 20 | 0.855 | 0.082 | 0.007 | 11.4x |
| 50 | 2.024 | 0.192 | 0.014 | 13.6x |
| 100 | 3.855 | 0.413 | 0.025 | 16.3x |

Чем больше виджетов — тем сильнее выигрыш от partial invalidation (больше поддеревьев переиспользуют кеш).

### Память (bench_memory.rb)

50 widgets, 500 тиков, 2 мутации/тик:

| Стратегия | ms/tick | Объектов | GC давление |
|-----------|---------|----------|-------------|
| Full rebuild (build+render) | 1.955 | 4 959 016 | 1.0x |
| Mutate + full cache wipe | 0.206 | 381 504 | 13.0x меньше |
| Partial invalidation | 0.032 | 7 002 | 708x меньше |

- **98.2% меньше GC давления** по сравнению с full cache wipe
- **~14 объектов/тик** — минимальная аллокация
- **0 GC runs** за 100 тиков partial invalidation
- **100% кеш покрытие:** все ноды кешируются, overhead ~0.5x от HTML

### Когда использовать

Partial invalidation оптимален для **дашбордов с частыми мелкими мутациями**: обновление 2-3 виджетов из 50-100 переиспользует >95% кешированного HTML. Идеально подходит для real-time мониторинга, live-метрик, и HTMX-фрагментов.

## Concurrent Rendering (v1.1)

С v1.1 все режимы рендеринга потокобезопасны:

- Per-thread буферы (`__thread`) — потоки не конкурируют за общий буфер
- Baked registry — `pthread_mutex` при `bake()`, lock-free при `render_baked()`
- Opcode stack в PackedBuilder — локальный на вызов

В многопоточных серверах (Puma, Falcon) каждый worker-поток рендерит независимо. Линейная масштабируемость до числа ядер.

## Рекомендации

| Сценарий | Метод | Почему |
|----------|-------|--------|
| Статическая страница | Registry cache | Рендер один раз → frozen String |
| Список из N карточек | Baked templates | Один шаблон, N рендеров с params |
| Динамическая форма | C ext cold | Полный Node API, 3x vs Ruby |
| Дашборд (частые обновления) | Partial invalidation | Subtree cache: 98% меньше GC, 13-16x vs full re-render |
| Повторный рендер | Node cache | Автоматический, O(1) |
| Только Ruby (без C ext) | Ruby `to_html` | Работает везде, zero dependencies |

## Запуск бенчмарка

```bash
cd fwui-native
rake compile
ruby test/bench_levels.rb
```

Выводит таблицу с ms/render и speedup для каждого уровня.
