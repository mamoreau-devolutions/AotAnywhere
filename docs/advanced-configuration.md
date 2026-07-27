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
`AotAnywhereWindowsSdkPath` to MSVC and Windows SDK roots when not using the
bundled cross-link package.

Plain `PackageReference` consumption cannot restore the toolchain references on
its first restore because NuGet does not evaluate build targets early enough.
Use the SDK form, restore the matching content packages explicitly, or configure
an external toolchain.
