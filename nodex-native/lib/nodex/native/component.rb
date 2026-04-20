# frozen_string_literal: true

module Nodex
  module UI
    class Component
      def self.bake(name, &block)
        children = block.call
        children = Array(children)
        template_node = Nodex.div(children)
        Nodex::Native.bake(name, template_node)
      end

      def self.render(name, **params)
        Nodex::Native.render_baked(name, **params)
      end

      def self.node(name, **params)
        Nodex::Native.baked_node(name, **params)
      end
    end
  end
end
