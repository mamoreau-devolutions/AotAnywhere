# Windows targets

On Linux and macOS hosts, AotAnywhere passes the SDK's native MSVC-style link
arguments directly to `lld-link`. Microsoft does not allow the required MSVC CRT
and Windows SDK import libraries to ship in AotAnywhere packages, so set
`AotAnywhereMsvcPath` and `AotAnywhereWindowsSdkPath` to compatible external
roots. On case-sensitive hosts the task creates lower-case aliases for Windows
SDK libraries before linking.

Use the helper scripts to build a private, cacheable tree from a licensed
Windows install:

- `eng/export-windows-crosslink.ps1` on Windows
- `eng/import-windows-crosslink.ps1` on Linux/macOS CI

See [windows-crosslink-cache.md](windows-crosslink-cache.md) for the layout,
GitHub Actions cache pattern, and licensing constraints.

This preserves the NativeAOT runtime's MSVC ABI and lets `lld-link` honor
`/MERGE`, `/OPT:REF`, and `/OPT:ICF` directly. The output imports the Universal
CRT and includes a PDB copied to the publish directory. On Windows hosts,
`win-*` targets continue to use the .NET SDK's native MSVC link path.
