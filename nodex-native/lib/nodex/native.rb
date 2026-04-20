# frozen_string_literal: true

# Load the pure Ruby nodex gem first (runtime dependency)
require 'nodex'

# Load the compiled C extension
require 'nodex_native/nodex_native'

# Patch Nodex::Node: C version becomes the default to_html
# + cache invalidation on mutation methods
module Nodex
  class Node
    alias_method :to_html_ruby, :to_html
    alias_method :to_html, :to_html_native

    # Wrap mutators to invalidate render cache (bubble-up via invalidate_cache!)
    %i[set_attr set_style add_class set_class set_id set_text append prepend].each do |m|
      orig = instance_method(m)
      define_method(m) do |*args|
        invalidate_cache!
        orig.bind_call(self, *args)
      end
    end

    # Keyword-arg method needs separate wrapper
    orig_styles = instance_method(:styles)
    define_method(:styles) do |**kw|
      invalidate_cache!
      orig_styles.bind_call(self, **kw)
    end
  end

  require_relative 'native/packed_builder'
  require_relative 'native/component'
  require_relative 'native/docx'
  require_relative 'native/doc'

  # Baked templates: compile Node tree → static chunks + slots.
  # At render time: memcpy chunks + escape(params). No tree traversal.
  module Native
    SLOT_RE = /__Nodex_SLOT_(\w+)__/

    # Compile a template Node into a baked template.
    #   Nodex::Native.bake(:card, Nodex.div([Nodex.slot(:title)]))
    def self.bake(name, template_node)
      html = template_node.to_html_native
      parts = html.split(SLOT_RE, -1)
      # parts alternates: [chunk, slot_name, chunk, slot_name, ..., chunk]
      chunks = []
      slot_names = []
      parts.each_with_index do |part, i|
        if i.even?
          chunks << part
        else
          slot_names << part.to_sym
        end
      end

      NativeBaked.register_baked(name.to_sym, chunks, slot_names)
      name.to_sym
    end

    # Render a baked template with params.
    #   Nodex::Native.render_baked(:card, title: "Hello")
    # Returns HTML String.
    def self.render_baked(name, **params)
      NativeBaked.render_baked(name.to_sym, params)
    end

    # Render and wrap in a raw Node (for embedding in trees).
    def self.baked_node(name, **params)
      Nodex.raw(render_baked(name, **params))
    end

    # Build HTML via PackedBuilder opcode stream — no Node objects.
    #   Nodex::Native.build { div { h1("Title").bold } }
    def self.build(&block)
      b = PackedBuilder.new
      b.instance_eval(&block)
      NativeBaked.render_opcodes(b.to_opcodes)
    end

    # ── Inja template engine ──────────────────────────────────────

    # Render an Inja template string with data.
    #   Nodex::Native.render_template("Hello {{ name }}!", { name: "World" })
    #   # => "Hello World!"
    def self.render_template(template_str, data = {})
      NativeInja.render_template(template_str, data)
    end

    # Render an Inja template file with data.
    #   Nodex::Native.render_template_file("templates/page.html", { title: "Home" })
    def self.render_template_file(path, data = {})
      NativeInja.render_template_file(path, data)
    end

    # Set the base directory for template file resolution and {% include %}.
    #   Nodex::Native.set_template_directory("templates/")
    def self.set_template_directory(dir)
      NativeInja.set_template_directory(dir)
    end

    # Check if Inja is available (always true when nodex-native is loaded).
    def self.inja_available?
      NativeInja.inja_available?
    end
  end
end
