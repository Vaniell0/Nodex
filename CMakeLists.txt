cmake_minimum_required(VERSION 3.22)
project(Nodex VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(Nodex_BUILD_TESTS "Build unit tests" OFF)

# --- Dependencies ---
include(FetchContent)

# fmt
find_package(fmt QUIET)
if(NOT fmt_FOUND)
  FetchContent_Declare(fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG        11.1.4
  )
  FetchContent_MakeAvailable(fmt)
endif()

# nlohmann_json
find_package(nlohmann_json QUIET)
if(NOT nlohmann_json_FOUND)
  FetchContent_Declare(nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
  )
  set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(nlohmann_json)
endif()

# Inja (header-only template engine)
find_package(inja QUIET)
if(NOT inja_FOUND)
  FetchContent_Declare(inja
      GIT_REPOSITORY https://github.com/pantor/inja.git
      GIT_TAG        v3.4.0
      SOURCE_SUBDIR  _unused
  )
  FetchContent_MakeAvailable(inja)
  set(INJA_INCLUDE_DIR ${inja_SOURCE_DIR}/include)
endif()

# --- Core static library ---
add_library(nodex STATIC
    src/core.cpp
    src/elements.cpp
    src/decorators.cpp
    src/renderer.cpp
    src/registry.cpp
    src/template_engine.cpp
    src/file_watcher.cpp
    src/hot_reload.cpp
)

target_include_directories(nodex PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

if(inja_FOUND)
  target_link_libraries(nodex PRIVATE pantor::inja)
else()
  target_include_directories(nodex PRIVATE ${INJA_INCLUDE_DIR})
endif()

target_link_libraries(nodex PUBLIC
    fmt::fmt
    nlohmann_json::nlohmann_json
)

# --- Demo executable ---
add_executable(nodex-demo src/main.cpp)
target_link_libraries(nodex-demo PRIVATE nodex)

# --- Benchmarks ---
add_executable(nodex-bench tests/bench_cpp.cpp)
target_link_libraries(nodex-bench PRIVATE nodex)

add_executable(nodex-bench-mem tests/bench_memory.cpp)
target_link_libraries(nodex-bench-mem PRIVATE nodex)

# --- Install ---
install(TARGETS nodex
    ARCHIVE DESTINATION lib
)
install(TARGETS nodex-demo
    RUNTIME DESTINATION bin
)
install(DIRECTORY include/nodex DESTINATION include)

# --- Tests ---
if(Nodex_BUILD_TESTS)
  enable_testing()

  FetchContent_Declare(Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG        v3.7.1
  )
  FetchContent_MakeAvailable(Catch2)

  add_executable(nodex-tests
    tests/test_node.cpp
    tests/test_elements.cpp
    tests/test_decorators.cpp
    tests/test_renderer.cpp
    tests/test_registry.cpp
    tests/test_template_engine.cpp
  )

  target_link_libraries(nodex-tests PRIVATE nodex Catch2::Catch2WithMain)

  include(CTest)
  include(Catch)
  catch_discover_tests(nodex-tests)
endif()
