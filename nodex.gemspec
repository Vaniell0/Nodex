# frozen_string_literal: true

require_relative 'ruby/lib/nodex/version'

Gem::Specification.new do |s|
  s.name        = 'nodex'
  s.version     = Nodex::VERSION
  s.summary     = 'Declarative HTML generation with pipe-operator DSL'
  s.description = 'Pure Ruby library for declarative HTML/JSON/HTMX generation ' \
                  'with a fluent pipe-operator DSL. ' \
                  'Components, registry, WebSocket, hot-reload, static site builder. ' \
                  'Zero gem dependencies — only Ruby stdlib.'

  s.authors  = ['Vaniello']
  s.email    = ['ripaivan11@gmail.com']
  s.homepage = 'https://github.com/Vaniell0/nodex'
  s.license  = 'Apache-2.0'

  s.required_ruby_version = '>= 3.0.0'

  s.metadata = {
    'homepage_uri'    => s.homepage,
    'source_code_uri' => s.homepage,
    'bug_tracker_uri' => "#{s.homepage}/issues",
  }

  s.files = Dir[
    'ruby/lib/**/*.rb',
    'README.md',
  ]

  s.require_paths = ['ruby/lib']
end
