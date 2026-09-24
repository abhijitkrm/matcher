cmake_minimum_required(VERSION 3.16)
project(matcher-cpp CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Header-only library target.
add_library(matcher INTERFACE)
target_include_directories(matcher INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_features(matcher INTERFACE cxx_std_20)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(matcher INTERFACE -Wall -Wextra)
endif()

enable_testing()

add_executable(golden_test tests/golden.cpp)
target_link_libraries(golden_test PRIVATE matcher)
add_test(NAME golden COMMAND golden_test ${CMAKE_CURRENT_SOURCE_DIR}/../vectors)

add_executable(matcherbench bench/matcherbench.cpp)
target_link_libraries(matcherbench PRIVATE matcher)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(matcherbench PRIVATE -O3 -march=native)
endif()
