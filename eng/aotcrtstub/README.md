# NativeAOT CRT stub

This directory vendors the NativeAOT CRT-stub sources from
[`awakecoding/runtime`](https://github.com/awakecoding/runtime/tree/experimental/nativeaot-crt-free/src/coreclr/nativeaot/Runtime/aotcrtstub)
at commit [`ba0c43c17535ff23bda655bf4300b8514e7ccf67`](https://github.com/awakecoding/runtime/commit/ba0c43c17535ff23bda655bf4300b8514e7ccf67).

The sources are licensed by the .NET Foundation under the MIT license; see
`LICENSE.TXT`. AotAnywhere compiles them on Windows when producing its
redistributable Windows cross-link payload. The resulting package contains
only `aotcrtstub.lib` and `ntdllcrt.lib`, not these source files.

AotAnywhere-specific ARM64 support remains in the adjacent
`eng/aotcrtstub-extra.c` and `eng/aotcrtstub-extra-arm64.asm` files.

