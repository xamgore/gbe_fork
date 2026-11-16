# macOS experimental `libsteam_api.dylib`

Build on macOS with Xcode Command Line Tools, CMake and Ninja:

```sh
./build_mac/build.sh arm64
```

On an Intel Mac, use `./build_mac/build.sh x86_64`. The output is
`dist/macos/<architecture>/libsteam_api.dylib`. The build uses the experimental
`gbe_fork` overlay and statically links its third-party dependencies. It does
not change the existing Windows or Linux build scripts.

The dependency tarballs come from `Detanup01/gbe_fork` commit
`92a4a130262083c4e887155cbe6bcab99baf36ea` on the
`third-party/deps/common` branch. The overlay tarball is pinned separately
to dependency commit `9ed52894f85943758c776cc4394be8b921e8d354`
(ImGui 1.92.9).
The macOS changes to that external project are in
`patches/ingame-overlay-macos.patch`. Abseil is pinned to `20250512.1`.
The build script checks SHA-256 hashes before unpacking sources.

For a Steam game that loads `steam_api.bundle`, replace the dylib inside that
bundle, keep a copy of the original, and re-sign the **application bundle** if
macOS reports an invalid code signature. The game-specific `steam_settings`
directory is separate from this library.

The Metal hook discovers loaded Apple GPU command-buffer classes at runtime,
so it is not tied to one M-series chip. The arm64 build has been tested with
Cat Mail Co. on M3 Max: Shift+Tab and LAN discovery/join worked. Other Apple
GPU generations and the Intel build need runtime testing. Cat Mail Co. has
also shown a loading hang and flickering during multiplayer; the cause has not
been isolated. Releases are marked prerelease until that is understood.

Tags named `macos-v*` build arm64 and x86_64 binaries on separate GitHub
macOS runners and publish them as release assets. A manual workflow run builds
both architectures and keeps the packages as Actions artifacts.
