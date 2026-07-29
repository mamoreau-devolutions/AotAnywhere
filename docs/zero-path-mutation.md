# PATH handling

AotAnywhere invokes the resolved Clang and LLD executables by absolute path for
Linux, macOS, and non-Windows Windows cross-links. The only intentional `PATH`
mutation occurs on a Windows host for the .NET SDK's `where /Q` linker probe:
`where` cannot reliably probe a drive-lettered executable path, so the selected
Clang `bin` directory is prepended for that MSBuild process only.

External toolchains can use `UseExternalClang=true` with Clang/LLD on `PATH`, or
set `AotAnywhereClangPath` and the individual executable override properties.
