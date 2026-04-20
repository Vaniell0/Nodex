# frozen_string_literal: true

require 'fileutils'

module Nodex
  module CLI
    module_function

    def run(args)
      command = args.shift

      case command
      when 'build'   then build(args)
      when 'serve'   then serve(args)
      when 'new'     then new_resource(args)
      when 'version', '-v', '--version'
        puts "nodex #{Nodex::VERSION}"
      else
        help
      end
    end

    # ── build ────────────────────────────────────────────────────

    def build(args)
      project_root = Dir.pwd

      pages_dir = File.join(project_root, 'ruby', 'pages')
      pages_dir = File.join(project_root, 'pages') unless Dir.exist?(pages_dir)

      static_dir = File.join(project_root, 'static')
      dist_dir = args.shift || File.join(project_root, 'dist')

      unless Dir.exist?(pages_dir)
        abort "Error: pages directory not found (tried pages/ and ruby/pages/)"
      end

      # Load pages
      registry = Nodex::Registry.new
      loaded = Nodex::PageLoader.load_pages(registry, pages_dir)

      if loaded.empty?
        abort "Error: no pages found in #{pages_dir}"
      end

      # Prepare dist
      FileUtils.rm_rf(dist_dir)
      FileUtils.mkdir_p(dist_dir)

      # Render each page
      rendered = 0
      registry.page_routes.each do |route|
        page = registry.create_page(route)
        html = page.to_html

        # Route → filename: "/" → "index.html", "/projects" → "projects/index.html"
        if route == '/'
          file_path = File.join(dist_dir, 'index.html')
        else
          clean = route.sub(%r{^/}, '').sub(%r{/$}, '')
          file_path = File.join(dist_dir, clean, 'index.html')
        end

        FileUtils.mkdir_p(File.dirname(file_path))
        File.write(file_path, html)
        rendered += 1
        puts "  #{route} → #{file_path.sub(project_root + '/', '')}"
      end

      # Copy static files
      if Dir.exist?(static_dir)
        static_dest = File.join(dist_dir, 'static')
        FileUtils.cp_r(static_dir, static_dest)
        static_count = Dir.glob(File.join(static_dir, '**', '*')).count { |f| File.file?(f) }
        puts "  static/ → #{static_count} files copied"
      end

      puts "\nBuild complete: #{rendered} pages → #{dist_dir}/"
    end

    # ── serve ────────────────────────────────────────────────────

    def serve(args)
      server_path = find_server
      abort "Error: server.rb not found" unless server_path

      # Default to dev mode
      args << '--dev' unless args.include?('--dev') || args.include?('--prod')
      args.delete('--prod')

      exec('ruby', server_path, *args)
    end

    # ── new ──────────────────────────────────────────────────────

    def new_resource(args)
      sub = args.first
      case sub
      when 'page'      then args.shift; new_page(args)
      when 'component' then args.shift; new_component(args)
      else new_project(args)
      end
    end

    def new_page(args)
      name = args.shift
      abort "Usage: nodex new page <name>" unless name

      pages_dir = File.join(Dir.pwd, 'pages')
      pages_dir = File.join(Dir.pwd, 'ruby', 'pages') unless Dir.exist?(pages_dir)
      FileUtils.mkdir_p(pages_dir) unless Dir.exist?(pages_dir)

      snake = name.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase.gsub(/[^a-z0-9_]/, '_')
      camel = snake.split('_').map(&:capitalize).join
      route = "/#{snake.tr('_', '-')}"
      file_path = File.join(pages_dir, "#{snake}.rb")

      if File.exist?(file_path)
        abort "Error: #{file_path} already exists"
      end

      File.write(file_path, <<~RUBY)
        # frozen_string_literal: true

        module Pages
          module #{camel}
            extend Nodex::DSL
            module_function

            def register(registry)
              registry.register_page("#{route}") do |data|
                layout("#{camel}",
                  head: [stylesheet("/static/style.css")],
                  navbar: [
                    a("Home", href: "/", class: "nav-link"),
                    a("#{camel}", href: "#{route}", class: "nav-link active"),
                  ],
                  body: [
                    section(class: "hero") {
                      h1("#{camel}").bold
                      p "Edit this page in pages/#{snake}.rb"
                    },
                  ],
                  footer: [p("Built with Nodex").center]
                )
              end
            end
          end
        end
      RUBY

      puts "  #{file_path}"
      puts "  route: #{route}"
    end

    def new_component(args)
      name = args.shift
      abort "Usage: nodex new component <name>" unless name

      components_dir = File.join(Dir.pwd, 'components')
      components_dir = File.join(Dir.pwd, 'ruby', 'components') if Dir.exist?(File.join(Dir.pwd, 'ruby'))
      FileUtils.mkdir_p(components_dir)

      snake = name.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase.gsub(/[^a-z0-9_]/, '_')
      camel = snake.split('_').map(&:capitalize).join
      file_path = File.join(components_dir, "#{snake}.rb")

      if File.exist?(file_path)
        abort "Error: #{file_path} already exists"
      end

      File.write(file_path, <<~RUBY)
        # frozen_string_literal: true

        module Components
          module #{camel}
            extend Nodex::DSL
            module_function

            def register(registry)
              registry.register_component("#{snake}") do |data|
                div(class: "#{snake.tr('_', '-')}") {
                  h3 data[:title] || "#{camel}"
                  p  data[:body]  || ""
                }
              end
            end
          end
        end
      RUBY

      puts "  #{file_path}"
      puts "  usage: registry.create_component(\"#{snake}\", title: \"...\", body: \"...\")"
    end

    def new_project(args)
      name = args.shift
      abort "Usage: nodex new <project-name>" unless name

      if Dir.exist?(name)
        abort "Error: directory '#{name}' already exists"
      end

      puts "Creating #{name}/"

      FileUtils.mkdir_p(File.join(name, 'pages'))
      FileUtils.mkdir_p(File.join(name, 'static'))
      FileUtils.mkdir_p(File.join(name, 'content'))

      # Sample page
      File.write(File.join(name, 'pages', 'home.rb'), <<~RUBY)
        # frozen_string_literal: true

        module Pages
          module Home
            extend Nodex::DSL
            module_function

            def register(registry)
              registry.register_page("/") do |_data|
                layout("#{name}",
                  head: [stylesheet("/static/style.css")],
                  navbar: [
                    a("Home", href: "/", class: "nav-link"),
                  ],
                  body: [
                    section(class: "hero", style: {text_align: "center", padding: "80px 24px"}) {
                      h1("#{name}").bold.font_size("2.5rem")
                      p("Built with Nodex").color("#666").margin("16px 0")
                    },
                  ],
                  footer: [p("Built with Nodex").center]
                )
              end
            end
          end
        end
      RUBY

      # Minimal CSS
      File.write(File.join(name, 'static', 'style.css'), <<~CSS)
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: system-ui, sans-serif; line-height: 1.6; color: #333; }
        .navbar { padding: 16px 24px; border-bottom: 1px solid #eee; }
        .nav-link { color: inherit; text-decoration: none; }
        .container { max-width: 800px; margin: 0 auto; padding: 40px 24px; }
      CSS

      puts "  pages/home.rb"
      puts "  static/style.css"
      puts "  content/"
      puts "\nDone. Next:"
      puts "  cd #{name}"
      puts "  nodex build     # generate dist/"
      puts "  nodex serve     # start dev server"
    end

    # ── help ─────────────────────────────────────────────────────

    def help
      puts <<~HELP
        nodex #{Nodex::VERSION} — declarative HTML generation

        Commands:
          build [dist_dir]        Render pages/ to dist/ (default)
          serve [--dev]           Start development server with hot-reload
          new <name>              Create new project scaffold
          new page <name>         Generate page with layout boilerplate
          new component <name>    Generate component with registry boilerplate
          version                 Show version

        Project structure:
          pages/              Page definitions (*.rb)
          components/         Reusable components (*.rb)
          static/             Static assets (CSS, JS, images)
          content/            Markdown content files
          dist/               Build output (generated)
      HELP
    end

    # ── helpers ──────────────────────────────────────────────────

    def find_server
      candidates = [
        File.join(Dir.pwd, 'ruby', 'examples', 'server.rb'),
        File.join(Dir.pwd, 'server.rb'),
        File.expand_path('../../examples/server.rb', __dir__),
      ]
      candidates.find { |p| File.exist?(p) }
    end

  end
end