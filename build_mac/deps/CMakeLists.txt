# Static dependency superbuild for the macOS Goldberg port.
# Sources are extracted from the exact tarballs gbe_fork builds with
# (fetched by build.sh from the pinned `third-party/deps/common` branch).
cmake_minimum_required(VERSION 3.24)
project(goldberg_mac_deps NONE)

include(ExternalProject)

set(DEPS_ROOT        "${CMAKE_CURRENT_SOURCE_DIR}")
set(SRC_ROOT         "${DEPS_ROOT}/src")
set(INSTALL_PREFIX   "${DEPS_ROOT}/install")

if(NOT ARCHS OR ARCHS STREQUAL "")
    set(ARCHS "arm64")
endif()

if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
endif()

set(common_cmake_args
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_CXX_STANDARD=17
    -DCMAKE_CXX_STANDARD_REQUIRED=ON
    -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}
    -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX}
    -DCMAKE_OSX_ARCHITECTURES=${ARCHS}
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
    # tolerate deps whose cmake_minimum_required predates CMake 4 policies
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

function(gbe_dep name)
    cmake_parse_arguments(ARG "" "" "DEPS" ${ARGN})
    ExternalProject_Add(${name}
        SOURCE_DIR        ${SRC_ROOT}/${name}
        INSTALL_DIR       ${INSTALL_PREFIX}
        CMAKE_ARGS        ${common_cmake_args} ${ARG_UNPARSED_ARGUMENTS}
        DEPENDS           ${ARG_DEPS}
    )
endfunction()

gbe_dep(zlib
    -DBUILD_SHARED_LIBS=OFF
)
# zlib's cmake still installs shared libs alongside the static one — drop them so
# every consumer (curl, protobuf, final link) resolves the static archive
ExternalProject_Add_Step(zlib remove_shared
    COMMAND ${CMAKE_COMMAND} -E remove_directory <INSTALL_DIR>/lib/libz.dylib
    COMMAND ${CMAKE_COMMAND} -E remove        <INSTALL_DIR>/lib/libz.1.dylib
    COMMAND ${CMAKE_COMMAND} -E remove        <INSTALL_DIR>/lib/libz.1.3.2.dylib
    DEPENDEES install)

gbe_dep(mbedtls
    -DUSE_STATIC_MBEDTLS_LIBRARY=ON
    -DUSE_SHARED_MBEDTLS_LIBRARY=OFF
    -DENABLE_TESTING=OFF
    -DENABLE_PROGRAMS=OFF
    -DMBEDTLS_FATAL_WARNINGS=OFF
    -DLINK_WITH_PTHREAD=ON
    DEPS zlib
)

gbe_dep(curl
    -DBUILD_CURL_EXE=OFF
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_STATIC_LIBS=ON
    -DBUILD_MISC_DOCS=OFF
    -DBUILD_TESTING=OFF
    -DBUILD_LIBCURL_DOCS=OFF
    -DENABLE_CURL_MANUAL=OFF
    -DCURL_USE_OPENSSL=OFF
    -DCURL_USE_SECTRANSP=OFF
    -DCURL_USE_MBEDTLS=ON
    -DCURL_ZLIB=ON
    -DZLIB_USE_STATIC_LIBS=ON
    -DZLIB_ROOT=${INSTALL_PREFIX}
    -DZLIB_INCLUDE_DIR=${INSTALL_PREFIX}/include
    -DZLIB_LIBRARY=${INSTALL_PREFIX}/lib/libz.a
    -DCURL_USE_LIBSSH2=OFF
    -DCURL_USE_LIBPSL=OFF
    -DUSE_LIBIDN2=OFF
    -DCURL_DISABLE_LDAP=ON
    -DUSE_NGHTTP2=OFF
    -DCURL_BROTLI=OFF
    -DCURL_ZSTD=OFF
    -DCURL_CA_FALLBACK=OFF
    DEPS zlib mbedtls
)

# abseil pinned exactly as protobuf v34.1 pins it (cmake/dependencies.cmake),
# built+installed separately so protobuf, its installed headers, and the final
# dylib all compile against ONE abseil (mixed abseil ABI => undefined symbols).
# CMAKE_CXX_STANDARD=17 must be explicit: abseil rewrites options.h at install
# time based on it, and a mismatch makes absl::string_view ABI diverge.
ExternalProject_Add(abseil
    SOURCE_DIR      ${SRC_ROOT}/abseil
    INSTALL_DIR     ${INSTALL_PREFIX}
    CMAKE_ARGS
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
        -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}
        -DCMAKE_OSX_ARCHITECTURES=${ARCHS}
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
        -DABSL_ENABLE_INSTALL=ON
        -DABSL_BUILD_TESTING=OFF
        -DABSL_PROPAGATE_CXX_STD=ON
        -DBUILD_SHARED_LIBS=OFF
)

# protobuf finds abseil above via find_package(absl CONFIG) in the install prefix
gbe_dep(protobuf
    -Dprotobuf_BUILD_PROTOBUF_BINARIES=ON
    -Dprotobuf_BUILD_PROTOC_BINARIES=ON
    -Dprotobuf_BUILD_LIBPROTOC=ON
    -Dprotobuf_BUILD_LIBUPB=ON
    -Dprotobuf_BUILD_TESTS=OFF
    -Dprotobuf_BUILD_EXAMPLES=OFF
    -Dprotobuf_DISABLE_RTTI=ON
    -Dprotobuf_BUILD_CONFORMANCE=OFF
    -Dprotobuf_BUILD_SHARED_LIBS=OFF
    -Dprotobuf_WITH_ZLIB=ON
    -DZLIB_USE_STATIC_LIBS=ON
    -DZLIB_ROOT=${INSTALL_PREFIX}
    -DZLIB_INCLUDE_DIR=${INSTALL_PREFIX}/include
    -DZLIB_LIBRARY=${INSTALL_PREFIX}/lib/libz.a
    DEPS zlib abseil
)

gbe_dep(libssq
    -DBUILD_SHARED_LIBS=OFF
)

gbe_dep(opus
    -DOPUS_BUILD_SHARED_LIBRARY=OFF
    -DOPUS_BUILD_TESTING=OFF
    -DOPUS_BUILD_PROGRAMS=OFF
    -DOPUS_CUSTOM_MODES=OFF
)

gbe_dep(portaudio
    -DPA_BUILD_SHARED_LIBS=OFF
    -DPA_BUILD_TESTS=OFF
    -DPA_BUILD_EXAMPLES=OFF
    -DPA_ENABLE_DEBUG_OUTPUT=OFF
    -DPA_USE_SKELETON=OFF
)
