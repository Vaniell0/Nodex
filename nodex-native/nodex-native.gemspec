# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'nodex-native'
  s.version     = '1.2.0'
  s.summary     = 'Native C extension for Nodex rendering and document export'
  s.description = 'C extension for Nodex: direct ivar access (ROBJECT_IVPTR), ' \
                  'render caching, baked templates, Inja template engine, ' \
                  'and DOCX/ODT export (zero dependencies, pure C++17).'

  s.authors  = ['Vaniello']
  s.email    = ['ripaivan11@gmail.com']
  s.homepage = 'https://github.com/Vaniell0/nodex'
  s.license  = 'BUSL-1.1'

  s.required_ruby_version = '>= 3.0.0'

  s.add_runtime_dependency 'nodex', '~> 1.0'

  s.files         = Dir['ext/**/*.{c,cpp,h,hpp,rb}', 'ext/**/vendor/**/*.hpp', 'lib/**/*.rb']
  s.extensions    = ['ext/nodex_native/extconf.rb']
  s.require_paths = ['lib']
end
