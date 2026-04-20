# frozen_string_literal: true

module Nodex
  # Simple mustache-style template renderer.
  # Replaces {{KEY}} placeholders with values from a hash.
  #
  # Usage:
  #   Nodex::Template.render("Hello {{name}}!", name: "World")
  #   Nodex::Template.render_file("views/index.html", title: "Home", body: html)
  #
  # Supports:
  #   {{KEY}}          — replaced with value.to_s
  #   {{KEY:default}}  — replaced with value or "default" if key missing
  #
  # Does NOT support loops, conditionals, or nesting.
  # For advanced templates, use the C++ inja engine via Nodex::Native.
  module Template
    module_function

    # Render a template string with variable substitutions.
    def render(template, **vars)
      vars_str = vars.transform_keys(&:to_s)

      template.gsub(/\{\{(\w+)(?::([^}]*))?\}\}/) do
        key = $1
        default = $2
        if vars_str.key?(key)
          vars_str[key].to_s
        elsif default
          default
        else
          "{{#{key}}}"
        end
      end
    end

    # Render a template file with variable substitutions.
    def render_file(path, **vars)
      raise ArgumentError, "Template not found: #{path}" unless File.exist?(path)

      render(File.read(path), **vars)
    end
  end
end
