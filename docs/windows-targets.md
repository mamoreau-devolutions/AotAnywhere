# Windows targets

On Linux and macOS hosts, AotAnywhere passes the SDK's native MSVC-style link
arguments directly to `lld-link`. Microsoft does not allow the required MSVC CRT and Windows SDK import libraries
to ship in AotAnywhere packages, so set `AotAnywhereMsvcPath` and
`AotAnywhereWindowsSdkPath` to compatible external roots — either exported from
a licensed Windows install (see
[windows-crosslink-cache.md](windows-crosslink-cache.md)) or produced with
[xwin](https://github.com/Jake-Shadle/xwin) on any host, whose output layouts
the linker task accepts directly. On case-sensitive hosts the task creates
lower-case aliases for Windows SDK libraries before linking.

If the NativeAOT runtime pack was built from the experimental
`UseAotCrtStub=true` path, the pack supplies the compiler-runtime pieces that
would otherwise come from `libcmt.lib` and `libvcruntime.lib`. In that mode
AotAnywhere does not require or add an MSVC CRT library path, but it still
requires Windows SDK UCRT/UM import libraries and `lld-link`.

AotAnywhere cannot turn an ordinary runtime pack into a CRT-free pack by
setting this property: the runtime pack must contain the stub libraries and
the corresponding NativeAOT runtime targets must add the `/NODEFAULTLIB`
linker options. For an independently built stub, set
`UseAotCrtStub=true` and `AotAnywhereAotCrtStubPath` to a directory containing
`aotcrtstub.lib` and `ntdllcrt.lib`; this adds that directory and both
libraries to the `lld-link` invocation.

The release package can embed those artifacts under
`build/aot-crt-stub/{x86_64,aarch64}`. The package build helper
`eng/pack-aot-crt-stub.ps1` validates a Windows-CI-produced payload and
includes it in the AotAnywhere package. When the embedded artifacts are used,
set `UseAotCrtStub=true`; AotAnywhere selects the directory matching
`CrossCompileArch` automatically.

To remove the remaining Windows SDK library cache dependency, run
`eng/build-windows-sdk-imports.ps1` on a Windows CI runner for each target
architecture. It reads only the export tables of the Windows system DLLs and
uses the packaged `llvm-dlltool` to produce COFF import libraries. It does not
copy DLLs, headers, or SDK binaries. Combine the x64 and ARM64 outputs under
one payload and package them with `eng/pack-windows-sdk-imports.ps1`.

This is a symbol-table substitute, not a complete Windows SDK. It covers the
libraries currently listed by NativeAOT (`advapi32`, `bcrypt`, `crypt32`,
`iphlpapi`, `kernel32`, `mswsock`, `ncrypt`, `normaliz`, `ntdll`, `ole32`,
`oleaut32`, `secur32`, `Synchronization`, `user32`, `version`, `ws2_32`, and
the UCRT). Any runtime-pack update that adds a library or requires exported
data symbols must update and validate the generator.

The CRT libraries can be built on the same Windows runner with
`eng/build-aot-crt-stub.ps1` against the pinned `dotnet/runtime` CRT-stub
sources. The runner needs the Windows SDK/Visual Studio only as a build
environment; none of those inputs are copied into the package.

Use the helper scripts to build a private, cacheable tree from a licensed
Windows install:

- `eng/export-windows-crosslink.ps1` on Windows
- `eng/import-windows-crosslink.ps1` on Linux/macOS CI

or produce the equivalent tree on any host with
[xwin](https://github.com/Jake-Shadle/xwin) — see
[windows-crosslink-cache.md](windows-crosslink-cache.md) for the layout, the
xwin invocation, the GitHub Actions cache pattern, and licensing constraints.

This preserves the NativeAOT runtime's MSVC ABI and lets `lld-link` honor
`/MERGE`, `/OPT:REF`, and `/OPT:ICF` directly (the takeover's `lld-link` never
sees `/SOURCELINK`, which no lld version implements). The output imports the
Universal CRT and includes a PDB copied to the publish directory. On Windows
hosts, `win-*` targets continue to use the .NET SDK's native MSVC link path.
