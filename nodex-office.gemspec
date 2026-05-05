# frozen_string_literal: true

require_relative 'ruby/lib/nodex/version'

Gem::Specification.new do |s|
  s.name        = 'nodex-office'
  s.version     = Nodex::VERSION
  s.summary     = 'DOCX/ODT/OMML writers for Nodex (pure Ruby)'
  s.description = 'Office document writers for the Nodex DSL. ' \
                  'Render Node trees to DOCX (with OMML math), ODT, ' \
                  'or PDF (via LibreOffice). Pure Ruby — only stdlib + Zlib.'

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

  s.add_dependency 'nodex', Nodex::VERSION

  s.files = Dir[
    'nodex-office/lib/**/*.rb',
    'README.md',
  ]

  s.require_paths = ['nodex-office/lib']
end
