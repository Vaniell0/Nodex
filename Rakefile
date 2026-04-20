# frozen_string_literal: true

require 'rubygems/package'

desc 'Build gem'
task :build do
  spec = Gem::Specification.load('fwui.gemspec')
  Gem::Package.build(spec)
end

desc 'Clean built gems'
task :clean do
  Dir['*.gem'].each { |f| File.delete(f) }
  puts 'Cleaned *.gem files'
end

task default: :build
