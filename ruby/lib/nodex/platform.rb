# frozen_string_literal: true

require 'rbconfig'

module Nodex
  module Platform
    module_function

    # RubyGems platform triplet for the current OS/arch.
    def platform_triplet
      case RUBY_PLATFORM
      when /x86_64.*linux/                    then 'x86_64-linux'
      when /x64.*mingw/, /x86_64.*mingw/      then 'x64-mingw-ucrt'
      when /aarch64.*darwin/, /arm64.*darwin/  then 'arm64-darwin'
      when /x86_64.*darwin/                    then 'x86_64-darwin'
      else RUBY_PLATFORM
      end
    end

    # Root directory of the gem / repository.
    def gem_root
      File.expand_path('../../..', __dir__)
    end
  end
end
