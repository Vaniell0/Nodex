# frozen_string_literal: true

require 'mkmf'

if RUBY_PLATFORM =~ /mswin|mingw/
  # MSVC / MinGW: C++17, UTF-8 source, suppress noisy warnings
  $CFLAGS << ' /O2' if RUBY_PLATFORM =~ /mswin/
  $CXXFLAGS << ' /O2 /std:c++17 /utf-8 /Zc:__cplusplus' if RUBY_PLATFORM =~ /mswin/

  # MinGW uses GCC-style flags
  if RUBY_PLATFORM =~ /mingw/
    $CFLAGS << ' -O3 -Wall -Wextra -Wno-unused-parameter'
    $CXXFLAGS << ' -O3 -std=c++17 -Wall -Wextra -Wno-unused-parameter'
  end
else
  # GCC / Clang (Linux, macOS)
  $CFLAGS << ' -O3 -Wall -Wextra -Wno-unused-parameter'
  $CXXFLAGS << ' -O3 -std=c++17 -Wall -Wextra -Wno-unused-parameter'

  # macOS Xcode 15+ emits compound-token-split warnings for Ruby macros
  if RUBY_PLATFORM =~ /darwin/
    $CFLAGS << ' -Wno-compound-token-split-by-macro'
    $CXXFLAGS << ' -Wno-compound-token-split-by-macro'
  end
end

# Vendored headers (inja.hpp, nlohmann/json.hpp)
vendor_dir = File.join(__dir__, 'vendor')
$INCFLAGS << " -I#{vendor_dir}"

# pthread for thread-safe baked template registry (not needed on Windows/macOS)
have_library('pthread') unless RUBY_PLATFORM =~ /mswin|mingw|darwin/

# Build both .c and .cpp sources
$srcs = Dir.glob(File.join(__dir__, '*.{c,cpp}'))

create_makefile('nodex_native/nodex_native')
