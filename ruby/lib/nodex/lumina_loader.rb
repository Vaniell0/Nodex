# frozen_string_literal: true

module Nodex
  module LuminaLoader
    module_function

    # Attempt to load Lumina, define stub if unavailable.
    # @param search_root [String, nil] Additional path to search (e.g., project root)
    def ensure_loaded(search_root: nil)
      return if defined?(::Lumina) && ::Lumina.available?

      require 'lumina'
    rescue LoadError
      _try_local(search_root)
    end

    def _try_local(root)
      if root
        lib = File.join(root, '..', 'Lumina', 'ruby', 'lib')
        $LOAD_PATH.unshift(lib) if Dir.exist?(lib)
        begin
          require 'lumina'
          return
        rescue LoadError
          # fall through to stub
        end
      end

      _define_stub unless defined?(::Lumina)
    end

    def _define_stub
      Object.const_set(:Lumina, Module.new {
        module_function
        def available? = false
        def version    = 'not installed'
        def styles     = []
        def render_svg(**) = nil
      })
    end

    private_class_method :_try_local, :_define_stub
  end
end
