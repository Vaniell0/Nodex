# frozen_string_literal: true

module Nodex
  # Loads page definition files from a directory.
  # Each file defines a Pages::ModuleName module with a .register(registry) method.
  module PageLoader
    module_function

    def load_pages(registry, pages_dir)
      loaded = []
      Dir.glob(File.join(pages_dir, '*.rb')).sort.each do |file|
        load file
        mod_name = File.basename(file, '.rb').split('_').map(&:capitalize).join
        if defined?(Pages) && Pages.const_defined?(mod_name)
          Pages.const_get(mod_name).register(registry)
          loaded << mod_name
        else
          $stderr.puts "Warning: #{file} did not define Pages::#{mod_name}"
        end
      end
      loaded
    end
  end
end
