# Windows cross-link library cache

Non-Windows hosts link `win-x64` / `win-arm64` with `lld-link` against real MSVC
CRT and Windows SDK import libraries. Microsoft does not allow those libraries
to be redistributed in AotAnywhere packages, so the helpers below extract them
from a licensed Windows install and restore a private cache on Linux/macOS CI.

## Layout contract

```text
<crosslink-root>/
  manifest.json
  vctools/lib/{x64,arm64}/*.lib          -> AotAnywhereMsvcPath
  winsdk/Lib/<10.*>/{ucrt,um}/{x64,arm64}/*.lib
                                         -> AotAnywhereWindowsSdkPath
```

This matches `SetWindowsCrossLinkPaths` and `AotAnywhereWindowsLink`:

- MSVC libs: `$(AotAnywhereMsvcPath)/lib/{x64,arm64}`
- SDK libs: `$(AotAnywhereWindowsSdkPath)/Lib/<latest 10.*>/{ucrt,um}/{x64,arm64}`

## Export on Windows

Run on a machine with Visual Studio C++ toolsets and a Windows 10/11 SDK:

```powershell
pwsh -File eng/export-windows-crosslink.ps1 `
  -OutputDirectory $env:RUNNER_TEMP/win-crosslink `
  -ArchivePath $env:RUNNER_TEMP/win-crosslink.tar.gz `
  -Architectures x64,arm64 `
  -AcceptLicense
```

Useful optional pins:

- `-MsvcVersion 14.51.36231`
- `-WindowsSdkVersion 10.0.26100.0`
- `-VsInstallPath 'C:\Program Files\Microsoft Visual Studio\2022\Enterprise'`
- `-IncludeDebug` only if you need `*d.lib`

The script prints:

- `AotAnywhereMsvcPath` / `AotAnywhereWindowsSdkPath`
- a stable `CacheKey` derived from MSVC toolset, SDK version, arches, and debug mode
- optional archive SHA-256

It also writes GitHub Actions step outputs when `GITHUB_OUTPUT` is set.

## Import on Linux or macOS

```powershell
pwsh -File eng/import-windows-crosslink.ps1 `
  -ArchivePath ./win-crosslink.tar.gz `
  -ExpectedSha256 <sha256-from-export> `
  -Destination $HOME/.cache/aotanywhere/win-crosslink `
  -Architectures x64,arm64
```

Then publish with the restored roots:

```bash
dotnet publish -r win-x64 \
  -p:AotAnywhereMsvcPath=$HOME/.cache/aotanywhere/win-crosslink/vctools \
  -p:AotAnywhereWindowsSdkPath=$HOME/.cache/aotanywhere/win-crosslink/winsdk
```

## GitHub Actions pattern

### 1. Export job on `windows-latest`

```yaml
jobs:
  export-windows-crosslink:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Export MSVC + Windows SDK libraries
        id: export
        shell: pwsh
        run: |
          ./eng/export-windows-crosslink.ps1 `
            -OutputDirectory "$env:RUNNER_TEMP/win-crosslink" `
            -ArchivePath "$env:RUNNER_TEMP/win-crosslink.tar.gz" `
            -Architectures x64,arm64 `
            -AcceptLicense
      - name: Upload private archive
        uses: actions/upload-artifact@v4
        with:
          name: win-crosslink-libs
          path: ${{ runner.temp }}/win-crosslink.tar.gz
          retention-days: 1
      - name: Expose cache metadata
        id: meta
        shell: pwsh
        run: |
          $manifest = Get-Content "$env:RUNNER_TEMP/win-crosslink/manifest.json" -Raw | ConvertFrom-Json
          "cache-key=$($manifest.cacheKey)" >> $env:GITHUB_OUTPUT
          "archive-sha256=$($manifest.archive.sha256)" >> $env:GITHUB_OUTPUT
```

Hosted `windows-latest` images already include MSVC and a Windows SDK, so no
extra installer is required for the common x64/ARM64 library set.

### 2. Consume job on `ubuntu-latest` with Actions cache

```yaml
  link-win-x64:
    needs: export-windows-crosslink
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: win-crosslink-libs
          path: ${{ runner.temp }}
      - name: Cache restored cross-link tree
        id: cache
        uses: actions/cache@v4
        with:
          path: ${{ runner.temp }}/win-crosslink
          key: ${{ needs.export-windows-crosslink.outputs.cache-key }}
      - name: Import archive when cache misses
        if: steps.cache.outputs.cache-hit != 'true'
        shell: pwsh
        run: |
          ./eng/import-windows-crosslink.ps1 `
            -ArchivePath "$env:RUNNER_TEMP/win-crosslink.tar.gz" `
            -Destination "$env:RUNNER_TEMP/win-crosslink" `
            -Architectures x64,arm64
      - name: Publish win-x64
        run: |
          dotnet publish path/to/app.csproj -r win-x64 -c Release \
            -p:AotAnywhereMsvcPath=${{ runner.temp }}/win-crosslink/vctools \
            -p:AotAnywhereWindowsSdkPath=${{ runner.temp }}/win-crosslink/winsdk
```

For a long-lived cache without re-exporting every PR, store the archive in a
private location you control and key the cache on the export script's
`cacheKey` / archive SHA-256. Do not commit the archive to git.

## What is copied

Release libraries only (unless `-IncludeDebug`):

| Tree | Source | Destination |
| --- | --- | --- |
| MSVC CRT / STL import libs | `VC\Tools\MSVC\<ver>\lib\{x64,arm64}` | `vctools/lib/{x64,arm64}` |
| Universal CRT | `Windows Kits\10\Lib\<sdk>\ucrt\{x64,arm64}` | `winsdk/Lib/<sdk>/ucrt/{x64,arm64}` |
| Windows UM import libs | `Windows Kits\10\Lib\<sdk>\um\{x64,arm64}` | `winsdk/Lib/<sdk>/um/{x64,arm64}` |

Headers and compiler binaries are intentionally omitted; Clang/`lld-link` only
need the import libraries for Native AOT link.

## Licensing

- Export only from a machine/account licensed for Visual Studio and the Windows
  SDK.
- Keep the archive and restored tree private (Actions cache, private artifact,
  private blob storage).
- Do not publish these files through AotAnywhere NuGet content packages or other
  public redistribution channels.
- `-AcceptLicense` on the export script is an explicit local acknowledgement of
  those constraints.
