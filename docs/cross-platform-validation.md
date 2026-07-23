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

ARMv7 validation is deferred until CBake publishes its Ubuntu 18.04 and Alpine
3.17 ARMv7 sysroots. Non-Windows Windows-target validation is deferred until a
versioned MSVC/Windows SDK cross-link bundle is available. The release workflow
must not claim a complete host-by-target matrix before those immutable inputs are
published.
