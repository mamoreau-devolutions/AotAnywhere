# Windows targets

On Linux and macOS hosts, AotAnywhere passes the SDK's native MSVC-style link
arguments directly to `lld-link`. A versioned cross-link content package will
supply matching MSVC, UCRT, and Windows SDK import libraries. Until that package
is published, set `AotAnywhereMsvcPath` and `AotAnywhereWindowsSdkPath` to
compatible external roots; on case-sensitive hosts the task creates lower-case
aliases for Windows SDK libraries before linking.

This preserves the NativeAOT runtime's MSVC ABI and lets `lld-link` honor
`/MERGE`, `/OPT:REF`, and `/OPT:ICF` directly. The output imports the Universal
CRT and includes a PDB copied to the publish directory. On Windows hosts,
`win-*` targets continue to use the .NET SDK's native MSVC link path.
