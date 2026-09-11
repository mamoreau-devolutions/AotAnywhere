# Advanced configuration

For everyday use, reference AotAnywhere as an MSBuild SDK and publish normally.
The SDK restores a host-specific Clang/LLVM runtime and the target's sysroot
content package during the first restore; CMake is never invoked.

## Linking model

- Linux links run `clang --target=<triple> --sysroot=<sysroot> -fuse-ld=lld`.
  The packaged Ubuntu 18.04 (x64/ARM64), Ubuntu 22.04 (ARMv7), and Alpine 3.17
  sysroots provide the target CRT, libc, and GCC support libraries.
- macOS links use Clang with `ld64.lld` against the bundled Apple `.tbd` stubs
  (or a real SDK supplied through `AotAnywhereAppleSysroot`).
- Non-Windows hosts link Windows targets with `lld-link` and the MSVC, UCRT,
  and Windows SDK import libraries. The versioned cross-link package will
  provide those libraries once published; until then, configure both external
  library roots. The SDK's native MSVC argument list is preserved, including
  `/MERGE` and `/OPT`.
- Linux symbol stripping remains a portable managed task that writes the normal
  `.dbg` sidecar and `.gnu_debuglink`.

## Using an external toolchain

Set `UseExternalClang=true` to bypass content-package resolution. The external
toolchain must expose Clang and the matching LLD drivers on `PATH`, or set
`AotAnywhereClangPath` to its root (containing `bin/`). Individual executable
paths can be overridden with `AotAnywhereClangExe`,
`AotAnywhereLd64LldExe`, `AotAnywhereLldLinkExe`, and
`AotAnywhereLlvmObjcopyExe`.

For Linux targets, set `AotAnywhereLinuxSysroot` to a compatible sysroot root.
It must contain `usr/` and a GCC support-library tree under `usr/lib/gcc` or
`usr/lib64/gcc`. For Windows cross-links, set `AotAnywhereMsvcPath` and
`AotAnywhereWindowsSdkPath` to roots produced by
`eng/export-windows-crosslink.ps1` /
`eng/import-windows-crosslink.ps1`, or produced by
[xwin](https://github.com/Jake-Shadle/xwin) on any host (see
[windows-crosslink-cache.md](windows-crosslink-cache.md)); the external
`lld-link` must be LLVM 21 or later (the ILC packs emit `/NOEXP`):

- `AotAnywhereMsvcPath` must contain `lib/{x64,arm64}` (or
  `lib/{x86_64,aarch64}`, the LLVM directory notation xwin uses by default),
  or be an xwin `--use-winsysroot-style` root — the link task then resolves
  `VC/Tools/MSVC/<crt-version>/lib/<arch>` itself
- `AotAnywhereWindowsSdkPath` must contain `Lib/<10.*/>{ucrt,um}/{x64,arm64}`
  (export/import cache and xwin winsysroot), a lower-case `lib/10.*/...`
  variant, or the version-less `lib/{ucrt,um}/<arch>` xwin default layout — an
  xwin winsysroot root itself is also accepted and the
  `Windows Kits/10/Lib` subtree resolved automatically

Plain `PackageReference` consumption cannot restore the toolchain references on
its first restore because NuGet does not evaluate build targets early enough.
Use the SDK form, restore the matching content packages explicitly, or configure
an external toolchain.
