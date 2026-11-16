# macOS build of the Goldberg emulator (gbe_fork) — produces libsteam_api.dylib
cmake_minimum_required(VERSION 3.24)
project(goldberg_emulator_mac LANGUAGES CXX C)

if(NOT ARCHS OR ARCHS STREQUAL "")
    set(ARCHS "arm64")
endif()
set(CMAKE_OSX_ARCHITECTURES ${ARCHS})
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
endif()
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release")
endif()

set(GBE_ROOT     "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH "gbe_fork source")
set(DEPS_PREFIX  "${CMAKE_CURRENT_SOURCE_DIR}/deps/install" CACHE PATH "static deps prefix")
option(EMU_EXPERIMENTAL_BUILD "Build experimental overlay" ON)
list(PREPEND CMAKE_PREFIX_PATH "${DEPS_PREFIX}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---------- protobuf codegen ----------
find_program(PROTOC_BIN
    NAMES protoc
    PATHS ${DEPS_PREFIX}/bin
    NO_DEFAULT_PATH
    REQUIRED)

set(PROTO_GEN_DIR ${CMAKE_BINARY_DIR}/proto_gen)
file(MAKE_DIRECTORY ${PROTO_GEN_DIR} ${PROTO_GEN_DIR}/tf2)

# mirrors upstream premake5.lua protoc invocations
add_custom_command(
    OUTPUT  ${PROTO_GEN_DIR}/net.pb.cc ${PROTO_GEN_DIR}/net.pb.h
    COMMAND ${PROTOC_BIN} --proto_path=${GBE_ROOT}/dll --cpp_out=${PROTO_GEN_DIR} ${GBE_ROOT}/dll/net.proto
    DEPENDS ${GBE_ROOT}/dll/net.proto
    VERBATIM)

add_custom_command(
    OUTPUT  ${PROTO_GEN_DIR}/steammessages.pb.cc ${PROTO_GEN_DIR}/steammessages.pb.h
    COMMAND ${PROTOC_BIN} --proto_path=${GBE_ROOT}/dll/gc_steam --cpp_out=${PROTO_GEN_DIR} ${GBE_ROOT}/dll/gc_steam/steammessages.proto
    DEPENDS ${GBE_ROOT}/dll/gc_steam/steammessages.proto
    VERBATIM)

file(GLOB GC_TF2_PROTOS CONFIGURE_DEPENDS ${GBE_ROOT}/dll/gc_tf2/*.proto)
set(GC_TF2_OUTPUTS "")
foreach(p ${GC_TF2_PROTOS})
    get_filename_component(fname "${p}" NAME_WE)
    list(APPEND GC_TF2_OUTPUTS ${PROTO_GEN_DIR}/tf2/${fname}.pb.cc ${PROTO_GEN_DIR}/tf2/${fname}.pb.h)
endforeach()
add_custom_command(
    OUTPUT  ${GC_TF2_OUTPUTS}
    COMMAND ${PROTOC_BIN}
            --proto_path=${GBE_ROOT}/dll/gc_steam
            --proto_path=${GBE_ROOT}/dll/gc_tf2
            --cpp_out=${PROTO_GEN_DIR}/tf2
            ${GC_TF2_PROTOS}
    DEPENDS ${GC_TF2_PROTOS}
    VERBATIM)

add_library(gbe_proto STATIC
    ${PROTO_GEN_DIR}/net.pb.cc ${PROTO_GEN_DIR}/net.pb.h
    ${PROTO_GEN_DIR}/steammessages.pb.cc ${PROTO_GEN_DIR}/steammessages.pb.h
    ${GC_TF2_OUTPUTS})
target_include_directories(gbe_proto PUBLIC ${PROTO_GEN_DIR})
target_link_libraries(gbe_proto PUBLIC protobuf::libprotobuf)

# ---------- third-party deps (static, from superbuild prefix) ----------
set(ZLIB_USE_STATIC_LIBS ON)   # make transitive ZLIB::ZLIB targets resolve libz.a
set(ZLIB_ROOT "${DEPS_PREFIX}")
find_package(protobuf CONFIG REQUIRED)   # protobuf::libprotobuf
find_package(CURL    CONFIG REQUIRED)    # CURL::libcurl
find_package(Opus    CONFIG REQUIRED)    # Opus::opus

set(MBEDTLS_LIBS
    ${DEPS_PREFIX}/lib/libmbedtls.a
    ${DEPS_PREFIX}/lib/libmbedx509.a
    ${DEPS_PREFIX}/lib/libmbedcrypto.a)
set(ZLIB_STATIC      ${DEPS_PREFIX}/lib/libz.a)
set(PORTAUDIO_STATIC ${DEPS_PREFIX}/lib/libportaudio.a)
set(SSQ_STATIC       ${DEPS_PREFIX}/lib/libssq.a)

# ---------- emulator dylib ----------
file(GLOB GBE_DLL_SOURCES CONFIGURE_DEPENDS ${GBE_ROOT}/dll/*.cpp)
list(FILTER GBE_DLL_SOURCES EXCLUDE REGEX "wrap\\.cpp$") # linux-only interposition, inert elsewhere

set(GBE_OTHER_SOURCES
    ${GBE_ROOT}/helpers/common_helpers.cpp
    ${GBE_ROOT}/helpers/dbg_log.cpp
    ${GBE_ROOT}/crash_printer/linux.cpp          # sigaction + backtrace work on darwin
    ${GBE_ROOT}/libs/simpleini/ConvertUTF.c)

if(EMU_EXPERIMENTAL_BUILD)
    set(OVERLAY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/deps/src/ingame_overlay")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include/InGameOverlay")
    if(NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/include/InGameOverlay/ImGui")
        file(CREATE_LINK "${OVERLAY_ROOT}/deps/ImGui"
            "${CMAKE_CURRENT_BINARY_DIR}/include/InGameOverlay/ImGui" SYMBOLIC)
    endif()
    add_subdirectory(${OVERLAY_ROOT} ${CMAKE_CURRENT_BINARY_DIR}/ingame_overlay)
    file(GLOB GBE_OVERLAY_SOURCES CONFIGURE_DEPENDS ${GBE_ROOT}/overlay_experimental/*.cpp)
endif()

add_library(steam_api SHARED ${GBE_DLL_SOURCES} ${GBE_OTHER_SOURCES} ${GBE_OVERLAY_SOURCES})

set_target_properties(steam_api PROPERTIES
    OUTPUT_NAME              steam_api
    PREFIX                   "lib"
    CXX_VISIBILITY_PRESET    hidden
    VISIBILITY_INLINES_HIDDEN ON
    MACOSX_RPATH             ON)

target_include_directories(steam_api PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}/include
    ${GBE_ROOT}/dll
    ${GBE_ROOT}/libs
    ${GBE_ROOT}/libs/utfcpp
    ${GBE_ROOT}/helpers
    ${GBE_ROOT}/crash_printer
    ${GBE_ROOT}/sdk
    ${GBE_ROOT}/overlay_experimental   # steam_friends.h includes the overlay stub header
    ${DEPS_PREFIX}/include)

target_compile_definitions(steam_api PRIVATE
    UTF_CPP_CPLUSPLUS=201703L
    CURL_STATICLIB
    GNUC                                # upstream defines this on all non-Windows builds
    EMU_BUILD_STRING="gbe-fork-macos")
if(EMU_EXPERIMENTAL_BUILD)
    target_compile_definitions(steam_api PRIVATE EMU_OVERLAY EMU_EXPERIMENTAL_BUILD ImTextureID=ImU64)
    target_link_libraries(steam_api PRIVATE Nemirtingas::InGameOverlay)
endif()
# NOTE: CONTROLLER_SUPPORT intentionally NOT defined on macOS (gamepad lib is win/linux only,
# steam_controller.cpp falls back to no-op stubs)

if(CMAKE_BUILD_TYPE MATCHES "Release")
    target_compile_definitions(steam_api PRIVATE NDEBUG EMU_RELEASE_BUILD)
endif()

target_link_libraries(steam_api PRIVATE
    gbe_proto
    protobuf::libprotobuf
    CURL::libcurl
    Opus::opus
    ${MBEDTLS_LIBS}
    ${ZLIB_STATIC}
    ${PORTAUDIO_STATIC}
    ${SSQ_STATIC}
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework AudioUnit"
    "-framework CoreFoundation"
    pthread
    dl)

# vendored/upstream code — keep clang from drowning us in warnings
target_compile_options(steam_api PRIVATE -Wno-everything)

add_custom_command(TARGET steam_api POST_BUILD
    COMMAND install_name_tool -id @rpath/libsteam_api.dylib $<TARGET_FILE:steam_api>
    VERBATIM)

# ---------- generate_interfaces tool ----------
add_executable(generate_interfaces
    ${GBE_ROOT}/tools/generate_interfaces/generate_interfaces.cpp
    ${GBE_ROOT}/helpers/common_helpers.cpp)
target_include_directories(generate_interfaces PRIVATE
    ${GBE_ROOT}/helpers
    ${GBE_ROOT}/libs
    ${GBE_ROOT}/libs/utfcpp)
target_compile_definitions(generate_interfaces PRIVATE UTF_CPP_CPLUSPLUS=201703L GNUC)
target_compile_options(generate_interfaces PRIVATE -Wno-everything)
