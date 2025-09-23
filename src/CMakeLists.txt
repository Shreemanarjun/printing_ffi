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
elseif(WIN32)
  # On Windows, link against Pdfium and the Graphics Device Interface library.
  # Use an absolute path to ensure the compiler can always find the headers.
  if(NOT IS_ABSOLUTE "${PDFIUM_INCLUDE_DIR}")
    set(PDFIUM_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/windows/${PDFIUM_INCLUDE_DIR}")
  endif()
  target_include_directories(printing_ffi PUBLIC "${PDFIUM_INCLUDE_DIR}")
  target_link_libraries(printing_ffi PUBLIC "gdi32.lib")
endif()

if(APPLE)
    # On macOS, find CUPS framework
    find_library(CUPS_LIBRARY cups)
    if(CUPS_LIBRARY)
        target_link_libraries(printing_ffi PUBLIC ${CUPS_LIBRARY})
    endif()
elseif(UNIX AND NOT ANDROID)
    # On Linux, find CUPS using pkg-config
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(CUPS REQUIRED cups)
    target_link_libraries(printing_ffi PUBLIC PkgConfig::CUPS)
endif()
