cmake_minimum_required(VERSION 3.20)
project(sample LANGUAGES CXX)

add_library(corelib src/lib.cpp)
add_executable(app src/main.cpp)
target_link_libraries(app PRIVATE corelib)

add_custom_target(docs COMMAND ${CMAKE_COMMAND} -E echo "docs")

enable_testing()
add_test(NAME smoke COMMAND app)
add_test(NAME corelib_unit COMMAND app --unit)
