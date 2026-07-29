# Cross-platform validation

The per-PR workflow validates the MSBuild target logic, then performs
clean-cache SDK consumption publishes with locally packed manifest-pinned Clang
and sysroot content packages for every released Linux target:

- `linux-x64` runs directly and `linux-musl-x64` runs in a native-architecture
  Alpine container.
- `linux-arm64`, `linux-arm`, `linux-musl-arm64`, and `linux-musl-arm` run in Docker with
  QEMU emulation.

Each target checks the restored package graph, ELF architecture, managed-strip
output and debuglink sidecar, and execution of the resulting binary.

The clean-consumer job proves the important restore behavior:

1. An `<Sdk Name="StuDev.AotAnywhere" />` reference restores both required
   content packages on its first restore.
2. A bare `PackageReference` fails with the actionable toolset error.
3. A bare package reference plus explicit toolset and sysroot references links
   successfully.

`linux-arm` and `linux-musl-arm` require .NET 9 or later. `linux-arm` uses
CBake's Ubuntu 22.04 ARM sysroot, whose glibc 2.35 baseline provides the time64
ABI required by .NET 9 Native AOT.

Non-Windows Windows-target validation remains deferred until CI provisions a
private MSVC/Windows SDK library cache with
`eng/export-windows-crosslink.ps1` and `eng/import-windows-crosslink.ps1`
(see [windows-crosslink-cache.md](windows-crosslink-cache.md)). Those Microsoft
libraries are not redistributed by AotAnywhere packages.
