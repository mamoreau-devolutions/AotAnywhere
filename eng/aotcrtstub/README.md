# NativeAOT CRT stub

This directory vendors the NativeAOT CRT-stub sources from
[`awakecoding/runtime`](https://github.com/awakecoding/runtime/tree/experimental/nativeaot-crt-free/src/coreclr/nativeaot/Runtime/aotcrtstub)
at commit [`ba60ffe69414bb52dfd30303bbff0360664c33ea`](https://github.com/awakecoding/runtime/commit/ba60ffe69414bb52dfd30303bbff0360664c33ea)
("Add experimental x86 NativeAOT CRT stub support").

The sources are licensed by the .NET Foundation under the MIT license; see
`LICENSE.TXT`. AotAnywhere compiles them on Windows when producing its
redistributable Windows cross-link payload. The resulting package contains
only `aotcrtstub.lib` and `ntdllcrt.lib`, not these source files.

`aotcrtstub.c` gained `#if defined(_M_IX86)` / `#if !defined(_WIN64)`
sections and switched the TLS/load-config directory structs from the
explicit `*64` types to the architecture-neutral `IMAGE_TLS_DIRECTORY` /
`IMAGE_LOAD_CONFIG_DIRECTORY` (which resolve to the 64-bit layout under
`_WIN64` via `<windows.h>`), so the file now also supports 32-bit x86 without
changing behavior on x64/ARM64. `aotcrtstub_i386.asm` and `ntdllcrt_i386.def`
are vendored for parity with upstream but are **not currently built or used**:
`eng/build-aot-crt-stub.ps1` only produces `x86_64`/`aarch64` stub libraries,
matching the `win-x64` / `win-arm64` targets `Crosscompile.targets` supports
(`win-x86` is explicitly rejected there today).

AotAnywhere-specific ARM64 support remains in the adjacent
`eng/aotcrtstub-extra.c` and `eng/aotcrtstub-extra-arm64.asm` files.

