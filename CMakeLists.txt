cmake_minimum_required(VERSION 4.1)

project(6502-emu LANGUAGES CXX)

set(CMAKE_BUILD_TYPE Debug)

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/bin)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

file(GLOB PROJECT_SOURCES CONFIGURE_DEPENDS
        ${PROJECT_SOURCE_DIR}/src/*.cpp
)

add_executable(${PROJECT_NAME} ${PROJECT_SOURCES})

target_compile_options(${PROJECT_NAME} PRIVATE 
  -Wall
  -Wextra
  -Wshadow
  -Wno-c23-extensions
  -fno-omit-frame-pointer
  -static
  $<$<CONFIG:Debug>:-O0>
  $<$<CONFIG:Debug>:-g>
  $<$<CONFIG:Debug>:-gcodeview>
  $<$<CONFIG:Release>:-O3>
  $<$<CONFIG:Release>:-flto>
)

target_link_options(${PROJECT_NAME} PRIVATE 
  -fuse-ld=lld
  $<$<CONFIG:Release>:-flto>
  $<$<CONFIG:Debug>:-Wl,--pdb=>
)

target_link_libraries(${PROJECT_NAME} PRIVATE
)

add_custom_target(run
    COMMAND $<TARGET_FILE:${PROJECT_NAME}>
    DEPENDS ${PROJECT_NAME}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    USES_TERMINAL
    COMMENT ""
)
