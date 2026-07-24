# Cross-platform validation

The per-PR workflow validates the MSBuild target logic, performs a clean-cache
SDK consumption publish with locally packed manifest-pinned Clang and Ubuntu
18.04 sysroot content packages, and publishes/runs a Linux x64 external-Clang
smoke test.

The clean-consumer job proves the important restore behavior:

1. An `<Sdk Name="StuDev.AotAnywhere" />` reference restores both required
   content packages on its first restore.
2. A bare `PackageReference` fails with the actionable toolset error.
3. A bare package reference plus explicit toolset and sysroot references links
   successfully.

The clean-consumer job packages the released Alpine ARMv7 sysroot, then verifies
first-restore cross-compilation for `linux-musl-arm`. That target requires .NET
9 or later. The CBake Ubuntu 18.04 ARM sysroot remains incompatible with .NET 9
Native AOT because its glibc 2.27 baseline lacks the required time64 ABI.

Non-Windows Windows-target validation remains deferred until a versioned
MSVC/Windows SDK cross-link bundle is available.
