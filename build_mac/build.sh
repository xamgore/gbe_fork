#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$repo_root/build_mac"
deps_root="$build_root/deps"
sources="$deps_root/src"
archives="$deps_root/tarballs"
arch="${1:-$(uname -m)}"
deps_commit="92a4a130262083c4e887155cbe6bcab99baf36ea"
overlay_commit="9ed52894f85943758c776cc4394be8b921e8d354"

case "$arch" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

for tool in cmake ninja curl tar shasum patch python3 codesign lipo nm otool; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

mkdir -p "$archives" "$sources"

fetch_source() {
    local name="$1" expected="$2" url="$3"
    local archive="$archives/$name.tar.gz" target="$sources/$name"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 3 --silent --show-error "$url" -o "$archive"
    fi
    printf '%s  %s\n' "$expected" "$archive" | shasum -a 256 --check --status
    if [[ ! -f "$target/.source-ready" ]]; then
        mkdir -p "$target"
        tar -xzf "$archive" -C "$target" --strip-components=1
        if [[ "$name" == ingame_overlay ]]; then
            python3 - "$target" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]) / 'src' / 'MacOSX'
for name in ('MetalHook.h', 'MetalHook.mm', 'RendererDetector.mm'):
    path = root / name
    path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
PY
            patch -d "$target" -p1 < "$repo_root/patches/ingame-overlay-macos.patch"
        fi
        touch "$target/.source-ready"
    fi
    if [[ "$name" == ingame_overlay ]]; then
        grep 'MyCAMetalDrawablePresent' "$target/src/MacOSX/MetalHook.mm" >/dev/null
    fi
}

base="https://raw.githubusercontent.com/Detanup01/gbe_fork/$deps_commit"
fetch_source zlib           5726e93ad621930942876e5388a0966ad10d8643ed6cb2e1ad2fb1c6a007d228 "$base/zlib/zlib.tar.gz"
fetch_source mbedtls        27133c38f383738d8ba0f0d86b52226f1ef3a48da32fed1a2e306b8ded66b6d8 "$base/mbedtls/mbedtls.tar.gz"
fetch_source curl           e3b4c895f160bb1ad5617cbaf1d4f09efefd1398947093a8a7c66fa578bbbad4 "$base/curl/curl.tar.gz"
fetch_source protobuf       1f29cfcd40dbb033ebd7680e42ddefb22fdc3e5ac1c37a4f09d4931cbfae7ba1 "$base/protobuf/protobuf.tar.gz"
fetch_source opus           e360d4e85994f3b84985159bff106e8640cf1108784e6c38fa78589d894553d0 "$base/opus/opus.tar.gz"
fetch_source portaudio      a516a2fb86c8927e674433c376167abf0d42023dc6f47c55d5e4e09a8ccb92ac "$base/portaudio/portaudio.tar.gz"
fetch_source libssq         e92860f8ff94e04485174b6e075fac8dd56a5ebacbb245ccee0d8104fa3074f4 "$base/libssq/libssq.tar.gz"
fetch_source ingame_overlay eb01d18e2597e4e3a2b95dcbcc507efe8b1620de29b93a97119370e99d866f29 "https://raw.githubusercontent.com/Detanup01/gbe_fork/$overlay_commit/ingame_overlay/ingame_overlay.tar.gz"
fetch_source abseil         9b7a064305e9fd94d124ffa6cc358592eb42b5da588fb4e07d09254aa40086db "https://github.com/abseil/abseil-cpp/archive/refs/tags/20250512.1.tar.gz"

cmake -S "$deps_root" -B "$deps_root/build-$arch" -G Ninja -DARCHS="$arch"
cmake --build "$deps_root/build-$arch" --parallel 3

cmake -S "$build_root" -B "$build_root/build-$arch" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DARCHS="$arch" -DEMU_EXPERIMENTAL_BUILD=ON
cmake --build "$build_root/build-$arch" --parallel 3

artifact="$build_root/build-$arch/libsteam_api.dylib"
codesign --force --sign - "$artifact"
[[ "$(lipo -archs "$artifact")" == "$arch" ]]
nm -gU "$artifact" | grep ' _SteamAPI_Init$' >/dev/null
mkdir -p "$repo_root/dist/macos/$arch"
cp "$artifact" "$repo_root/dist/macos/$arch/libsteam_api.dylib"
otool -L "$artifact"
echo "Built $repo_root/dist/macos/$arch/libsteam_api.dylib"
