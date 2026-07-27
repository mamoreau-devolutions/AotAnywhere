# AotAnywhere roadmap

## Toolchain publication

1. Publish the manifest-pinned Clang toolset packages for Linux x64/ARM64,
   Windows x64/ARM64, and macOS x64/ARM64.
2. Publish the Ubuntu 18.04, Ubuntu 22.04 ARM, and Alpine 3.17 CBake sysroot
   packages, including both ARMv7 RIDs, and verify their complete
   host-by-target matrix.
3. Publish the versioned MSVC/Windows SDK cross-link bundle needed by
   `lld-link` on Linux and macOS hosts.

## Quality and maintenance

5. Run real Linux, macOS, and Windows integration publishes from fresh package
   feeds after all content packages are available.
6. Keep the Apple stub generator current with new .NET runtime packs.
7. Extend the Windows link task tests with a real cross-link bundle and verify
   PDB, `/OPT`, and `/MERGE` behavior.
