# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(printing_ffi_library VERSION 0.0.1 LANGUAGES C)

add_library(printing_ffi SHARED
  "printing_ffi.c"
)

set_target_properties(printing_ffi PROPERTIES
  PUBLIC_HEADER printing_ffi.h
  OUTPUT_NAME "printing_ffi"
)

target_compile_definitions(printing_ffi PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(printing_ffi PRIVATE "-Wl,-z,max-page-size=16384")
endif()
