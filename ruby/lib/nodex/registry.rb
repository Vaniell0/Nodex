# frozen_string_literal: true

module Nodex
  # Component and page registry — pure Ruby mirror of C++ nodex::Registry.
  #
  # Thread safety: all public methods are protected by a single Mutex.
  # Factories are called *outside* the lock to prevent deadlocks when a
  # factory itself calls back into the registry.
  #
  # Cache: LRU eviction kicks in at MAX_CACHE_SIZE entries per cache table.
  # On re-registration every cached entry for that key (including parameterised
  # variants like "key:hash") is cleared immediately.
  #
  # Usage:
  #   reg = Nodex::Registry.new
  #   reg.register_component("header") { |data| Nodex.h1("Hello") }
  #   reg.register_component("navbar", cache: true) { |data| Nodex.nav([...]) }
  #   reg.register_page("/") { |data| Nodex.document("Home", body: [...]) }
  #   reg.create_page("/")
  class Registry
    MAX_CACHE_SIZE = 512

    def initialize
      @mutex = Mutex.new
      @components = {}
      @pages = {}
      @component_cache = {}
      @page_cache = {}
    end

    private

    def cache_set(hash, key, value)
      # LRU eviction: Ruby Hash preserves insertion order; first entry is oldest.
      hash.delete(hash.keys.first) if hash.size >= MAX_CACHE_SIZE
      hash[key] = value
    end

    public

    # --- Component registration ---

    def register_component(name, cache: false, &factory)
      raise ArgumentError, "block required" unless block_given?
      key = name.to_s
      @mutex.synchronize do
        @components[key] = { factory: factory, cache: cache }
        @component_cache.delete_if { |k, _| k == key || k.start_with?("#{key}:") }
      end
      self
    end

    def unregister_component(name)
      key = name.to_s
      @mutex.synchronize do
        @components.delete(key)
        @component_cache.delete_if { |k, _| k == key || k.start_with?("#{key}:") }
      end
      self
    end

    def has_component?(name)
      @mutex.synchronize { @components.key?(name.to_s) }
    end

    def create_component(name, data = {})
      key = name.to_s
      entry, cache_key, cached = @mutex.synchronize do
        e = @components[key]
        raise KeyError, "Component not found: #{name}" unless e
        if e[:cache]
          ck = e[:cache] == true ? key : "#{key}:#{data.hash}"
          [e, ck, @component_cache[ck]]
        else
          [e, nil, nil]
        end
      end

      return Nodex.raw(cached) if cached

      node = entry[:factory].call(data)

      if cache_key
        html = node.to_html
        @mutex.synchronize { cache_set(@component_cache, cache_key, html.freeze) unless @component_cache[cache_key] }
      end
      node
    end

    # --- Page registration ---

    def register_page(route, cache: false, &factory)
      raise ArgumentError, "block required" unless block_given?
      key = route.to_s
      @mutex.synchronize do
        @pages[key] = { factory: factory, cache: cache }
        @page_cache.delete_if { |k, _| k == key || k.start_with?("#{key}:") }
      end
      self
    end

    def unregister_page(route)
      key = route.to_s
      @mutex.synchronize do
        @pages.delete(key)
        @page_cache.delete_if { |k, _| k == key || k.start_with?("#{key}:") }
      end
      self
    end

    def has_page?(route)
      @mutex.synchronize { @pages.key?(route.to_s) }
    end

    def create_page(route, data = {})
      key = route.to_s
      entry, cache_key, cached = @mutex.synchronize do
        e = @pages[key]
        raise KeyError, "Page not found: #{route}" unless e
        if e[:cache]
          ck = e[:cache] == true ? key : "#{key}:#{data.hash}"
          [e, ck, @page_cache[ck]]
        else
          [e, nil, nil]
        end
      end

      return Nodex.raw(cached) if cached

      node = entry[:factory].call(data)

      if cache_key
        html = node.to_html
        @mutex.synchronize { cache_set(@page_cache, cache_key, html.freeze) unless @page_cache[cache_key] }
      end
      node
    end

    # --- Cache management ---

    def invalidate_cache(name = nil)
      @mutex.synchronize do
        if name
          key = name.to_s
          @component_cache.delete_if { |k, _| k == key || k.start_with?("#{key}:") }
          @page_cache.delete_if { |k, _| k == key || k.start_with?("#{key}:") }
        else
          @component_cache.clear
          @page_cache.clear
        end
      end
      self
    end

    # --- Introspection ---

    def component_names
      @mutex.synchronize { @components.keys.sort }
    end

    def page_routes
      @mutex.synchronize { @pages.keys.sort }
    end

    def cache_stats
      @mutex.synchronize do
        {
          components: @component_cache.size,
          pages: @page_cache.size,
          component_keys: @component_cache.keys,
          page_keys: @page_cache.keys,
        }
      end
    end
  end
end
