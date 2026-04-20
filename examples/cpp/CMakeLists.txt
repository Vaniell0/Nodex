cmake_minimum_required(VERSION 3.22)
project(nodex_example LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Option 1: FetchContent (recommended for new projects) ────
#
# include(FetchContent)
# FetchContent_Declare(nodex
#   GIT_REPOSITORY https://github.com/Vaniell0/nodex.git
#   GIT_TAG        v1.0.0
# )
# set(Nodex_GEM_BUILD ON CACHE BOOL "" FORCE)  # skip server deps
# FetchContent_MakeAvailable(nodex)

# ── Option 2: Local path (for development) ───────────────────
set(Nodex_GEM_BUILD ON CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../.. ${CMAKE_CURRENT_BINARY_DIR}/nodex)

# ── Build example ────────────────────────────────────────────
add_executable(example main.cpp)
target_link_libraries(example PRIVATE nodex)
