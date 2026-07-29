# Direct link architecture

AotAnywhere takes over the NativeAOT `LinkNative` target before the SDK runs it.
The .NET SDK remains the source of the object files, runtime libraries, and
`@(LinkerArg)` values; AotAnywhere selects the target linker and adds only the
target-environment framing.

- Linux invokes Clang with the selected target triple, the restored CBake
  sysroot, `--gcc-toolchain=<sysroot>/usr`, its discovered GCC support library,
  and `-fuse-ld=lld`.
- macOS invokes Clang with `ld64.lld`, the bundled generated Apple stubs (or a
  configured real SDK), Swift overlays when required, link-time symbol stripping,
  and ad-hoc signing for cross-linked output.
- Non-Windows hosts invoke `lld-link` through `AotAnywhereWindowsLink` with the
  native MSVC response-file arguments plus MSVC, UCRT, and Windows SDK library
  directories. No GNU argument translation or second link pass is involved.

The SDK's early linker probes point at the same Clang/LLVM tools. Windows hosts
prepend the packaged `bin` directory only because the SDK's `where /Q` probe
cannot accept a drive-lettered executable path. Linux ELF symbol stripping stays
in the managed `AotAnywhereStrip` task to preserve existing `.dbg` sidecar and
`.gnu_debuglink` behavior.
