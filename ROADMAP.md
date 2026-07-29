# AotAnywhere roadmap

## Toolchain publication

1. Publish the manifest-pinned Clang toolset packages for Linux x64/ARM64,
   Windows x64/ARM64, and macOS x64/ARM64.
2. Publish the Ubuntu 18.04, Ubuntu 22.04 ARM, and Alpine 3.17 CBake sysroot
   packages, including both ARMv7 RIDs, and verify their complete
   host-by-target matrix.
3. Keep non-Windows Windows links on private MSVC/Windows SDK library caches
   produced by `eng/export-windows-crosslink.ps1` (Microsoft assets are not
   redistributed in AotAnywhere packages). Optionally automate export/import in
   CI once a durable private cache is available.

## Quality and maintenance

5. Run real Linux, macOS, and Windows integration publishes from fresh package
   feeds after all content packages are available.
6. Keep the Apple stub generator current with new .NET runtime packs.
7. Extend the Windows link task tests with a real cross-link bundle and verify
   PDB, `/OPT`, and `/MERGE` behavior.
