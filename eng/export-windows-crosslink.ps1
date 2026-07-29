#Requires -Version 7.0
<#
.SYNOPSIS
  Export MSVC CRT and Windows SDK libraries from a licensed Windows install.

.DESCRIPTION
  Copies the release MSVC and Windows SDK import libraries needed by
  AotAnywhere's non-Windows lld-link path into the layout expected by
  AotAnywhereMsvcPath / AotAnywhereWindowsSdkPath:

    <OutputDirectory>/
      vctools/lib/{x64,arm64}/*.lib
      winsdk/Lib/<10.*>/{ucrt,um}/{x64,arm64}/*.lib
      manifest.json

  The resulting tree (or .tar.gz archive) is intended for a private GitHub
  Actions cache or local restore. Do not publish these Microsoft libraries in
  AotAnywhere NuGet packages or other public redistributions.

.PARAMETER OutputDirectory
  Destination root for the staged cross-link tree.

.PARAMETER ArchivePath
  Optional .tar.gz path. When set, the staged tree is packed after export.

.PARAMETER Architectures
  Target architectures to include. Defaults to x64 and arm64.

.PARAMETER VsInstallPath
  Optional Visual Studio installation root. Discovered with vswhere when omitted.

.PARAMETER MsvcVersion
  Optional MSVC toolset version under VC\Tools\MSVC. Latest installed when omitted.

.PARAMETER WindowsSdkRoot
  Optional Windows 10/11 SDK root. Defaults to Program Files (x86)\Windows Kits\10.

.PARAMETER WindowsSdkVersion
  Optional SDK Lib version (10.*). Latest installed when omitted.

.PARAMETER IncludeDebug
  Include *d.lib debug libraries. Off by default to keep the cache small.

.PARAMETER AcceptLicense
  Required acknowledgement that the caller is licensed to use and cache these
  Microsoft libraries and will not redistribute them publicly.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $OutputDirectory,

    [string] $ArchivePath,

    [string[]] $Architectures = @('x64', 'arm64'),

    [string] $VsInstallPath,

    [string] $MsvcVersion,

    [string] $WindowsSdkRoot,

    [string] $WindowsSdkVersion,

    [switch] $IncludeDebug,

    [switch] $AcceptLicense
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-AcceptLicense {
    if (-not $AcceptLicense) {
        throw @"
Refusing to export Microsoft MSVC/Windows SDK libraries without -AcceptLicense.

These files come from a licensed Windows / Visual Studio installation. Cache
them privately (for example GitHub Actions cache) and restore them with
eng/import-windows-crosslink.ps1. Do not publish them in public packages.
"@
    }
}

function Get-VsWherePath {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    return $null
}

function Resolve-VsInstallPath {
    param([string] $ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Container)) {
            throw "Visual Studio install path does not exist: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $vswhere = Get-VsWherePath
    if (-not $vswhere) {
        throw 'vswhere.exe was not found. Install Visual Studio or pass -VsInstallPath.'
    }

    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $path) {
        # Fall back to any VS install that still has an MSVC toolset tree.
        $path = & $vswhere -latest -products * -property installationPath
    }
    if (-not $path) {
        throw 'No Visual Studio installation was found. Pass -VsInstallPath.'
    }

    return $path.Trim()
}

function Resolve-MsvcLibRoot {
    param(
        [Parameter(Mandatory)] [string] $InstallPath,
        [string] $Version
    )

    $msvcRoot = Join-Path $InstallPath 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $msvcRoot -PathType Container)) {
        throw "MSVC toolsets were not found under '$msvcRoot'."
    }

    if ($Version) {
        $candidate = Join-Path $msvcRoot $Version
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            throw "MSVC version '$Version' was not found under '$msvcRoot'."
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $latest = Get-ChildItem -LiteralPath $msvcRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'lib') -PathType Container } |
        Sort-Object Name |
        Select-Object -Last 1
    if (-not $latest) {
        throw "No MSVC lib directories were found under '$msvcRoot'."
    }

    return $latest.FullName
}

function Resolve-WindowsSdkRoot {
    param([string] $ExplicitRoot)

    if ($ExplicitRoot) {
        if (-not (Test-Path -LiteralPath $ExplicitRoot -PathType Container)) {
            throw "Windows SDK root does not exist: $ExplicitRoot"
        }
        return (Resolve-Path -LiteralPath $ExplicitRoot).Path
    }

    $candidates = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10",
        "$env:ProgramFiles\Windows Kits\10"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'Windows 10/11 SDK root was not found. Pass -WindowsSdkRoot.'
}

function Resolve-WindowsSdkVersion {
    param(
        [Parameter(Mandatory)] [string] $SdkRoot,
        [string] $Version
    )

    $libRoot = Join-Path $SdkRoot 'Lib'
    if (-not (Test-Path -LiteralPath $libRoot -PathType Container)) {
        throw "Windows SDK Lib directory was not found under '$SdkRoot'."
    }

    if ($Version) {
        $candidate = Join-Path $libRoot $Version
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            throw "Windows SDK version '$Version' was not found under '$libRoot'."
        }
        return $Version
    }

    $latest = Get-ChildItem -LiteralPath $libRoot -Directory |
        Where-Object { $_.Name -like '10.*' } |
        Sort-Object Name |
        Select-Object -Last 1
    if (-not $latest) {
        throw "No Windows 10 SDK Lib version directories were found under '$libRoot'."
    }

    return $latest.Name
}

function Test-IsReleaseLibrary {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo] $File,
        [switch] $KeepDebug
    )

    if ($File.Extension -ne '.lib') {
        return $false
    }

    if ($KeepDebug) {
        return $true
    }

    # Drop debug CRT/SDK variants and PDBs; release Native AOT links do not need them.
    if ($File.Name -match 'd\.lib$' -and $File.Name -notmatch 'oldnames\.lib$') {
        # Keep names that merely end with a non-debug suffix letter, but drop the
        # conventional *d.lib debug pair (libcmt d, ucrtd, kernel32d is uncommon).
        $base = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        if ($base.EndsWith('d', [System.StringComparison]::OrdinalIgnoreCase)) {
            $releaseSibling = Join-Path $File.DirectoryName ($base.Substring(0, $base.Length - 1) + '.lib')
            if (Test-Path -LiteralPath $releaseSibling -PathType Leaf) {
                return $false
            }
        }
    }

    return $true
}

function Copy-LibraryTree {
    param(
        [Parameter(Mandatory)] [string] $SourceDirectory,
        [Parameter(Mandatory)] [string] $DestinationDirectory,
        [switch] $KeepDebug
    )

    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        throw "Required library directory is missing: $SourceDirectory"
    }

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    $copied = 0
    foreach ($file in Get-ChildItem -LiteralPath $SourceDirectory -File) {
        if (-not (Test-IsReleaseLibrary -File $file -KeepDebug:$KeepDebug)) {
            continue
        }

        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $DestinationDirectory $file.Name) -Force
        $copied++
    }

    if ($copied -eq 0) {
        throw "No .lib files were copied from '$SourceDirectory'."
    }

    return $copied
}

function Assert-RequiredMsvcLibraries {
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $Architecture
    )

    $required = @(
        'libcmt.lib',
        'libvcruntime.lib',
        'vcruntime.lib',
        'oldnames.lib'
    )

    foreach ($name in $required) {
        $path = Join-Path $Directory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "MSVC $Architecture export is missing required library '$name' under '$Directory'."
        }
    }
}

function Assert-RequiredSdkLibraries {
    param(
        [Parameter(Mandatory)] [string] $UcrtDirectory,
        [Parameter(Mandatory)] [string] $UmDirectory,
        [Parameter(Mandatory)] [string] $Architecture
    )

    foreach ($name in @('ucrt.lib', 'libucrt.lib')) {
        if (-not (Test-Path -LiteralPath (Join-Path $UcrtDirectory $name) -PathType Leaf)) {
            throw "Windows SDK $Architecture UCRT export is missing '$name' under '$UcrtDirectory'."
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $UmDirectory 'kernel32.lib') -PathType Leaf)) {
        throw "Windows SDK $Architecture UM export is missing 'kernel32.lib' under '$UmDirectory'."
    }
}

function New-CacheKey {
    param(
        [Parameter(Mandatory)] [string] $MsvcToolsetVersion,
        [Parameter(Mandatory)] [string] $SdkVersion,
        [Parameter(Mandatory)] [string[]] $Arches,
        [bool] $DebugIncluded
    )

    $archPart = ($Arches | Sort-Object) -join '+'
    $debugPart = if ($DebugIncluded) { 'debug' } else { 'release' }
    return "aotanywhere-win-crosslink-msvc$MsvcToolsetVersion-sdk$SdkVersion-$archPart-$debugPart"
}

function Normalize-Architectures {
    param([string[]] $Values)

    $normalized = foreach ($value in $Values) {
        foreach ($part in ($value -split '[,;\s]+')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $arch = $part.Trim().ToLowerInvariant()
            if ($arch -notin @('x64', 'arm64')) {
                throw "Unsupported architecture '$part'. Expected x64 and/or arm64."
            }
            $arch
        }
    }

    $unique = @($normalized | Select-Object -Unique)
    if ($unique.Count -eq 0) {
        throw 'At least one architecture is required.'
    }
    return $unique
}

Assert-AcceptLicense

$architectures = Normalize-Architectures -Values $Architectures
$vsPath = Resolve-VsInstallPath -ExplicitPath $VsInstallPath
$msvcRoot = Resolve-MsvcLibRoot -InstallPath $vsPath -Version $MsvcVersion
$msvcToolsetVersion = Split-Path -Leaf $msvcRoot
$sdkRoot = Resolve-WindowsSdkRoot -ExplicitRoot $WindowsSdkRoot
$sdkVersion = Resolve-WindowsSdkVersion -SdkRoot $sdkRoot -Version $WindowsSdkVersion

$output = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

$vctoolsRoot = Join-Path $output 'vctools'
$winsdkRoot = Join-Path $output 'winsdk'
$counts = [ordered]@{
    msvc = [ordered]@{}
    ucrt = [ordered]@{}
    um   = [ordered]@{}
}

Write-Host "Exporting MSVC $msvcToolsetVersion from $msvcRoot"
Write-Host "Exporting Windows SDK $sdkVersion from $sdkRoot"
Write-Host "Architectures: $($architectures -join ', ')"

foreach ($arch in $architectures) {
    $msvcSource = Join-Path $msvcRoot "lib\$arch"
    $msvcDest = Join-Path $vctoolsRoot "lib\$arch"
    $msvcCount = Copy-LibraryTree -SourceDirectory $msvcSource -DestinationDirectory $msvcDest -KeepDebug:$IncludeDebug
    Assert-RequiredMsvcLibraries -Directory $msvcDest -Architecture $arch
    $counts.msvc[$arch] = $msvcCount

    $ucrtSource = Join-Path $sdkRoot "Lib\$sdkVersion\ucrt\$arch"
    $ucrtDest = Join-Path $winsdkRoot "Lib\$sdkVersion\ucrt\$arch"
    $ucrtCount = Copy-LibraryTree -SourceDirectory $ucrtSource -DestinationDirectory $ucrtDest -KeepDebug:$IncludeDebug
    $counts.ucrt[$arch] = $ucrtCount

    $umSource = Join-Path $sdkRoot "Lib\$sdkVersion\um\$arch"
    $umDest = Join-Path $winsdkRoot "Lib\$sdkVersion\um\$arch"
    $umCount = Copy-LibraryTree -SourceDirectory $umSource -DestinationDirectory $umDest -KeepDebug:$IncludeDebug
    Assert-RequiredSdkLibraries -UcrtDirectory $ucrtDest -UmDirectory $umDest -Architecture $arch
    $counts.um[$arch] = $umCount
}

$cacheKey = New-CacheKey -MsvcToolsetVersion $msvcToolsetVersion -SdkVersion $sdkVersion -Arches $architectures -DebugIncluded:([bool]$IncludeDebug)
$manifest = [ordered]@{
    schemaVersion        = 1
    createdUtc           = [DateTime]::UtcNow.ToString('o')
    source               = [ordered]@{
        vsInstallPath      = $vsPath
        msvcToolsetVersion = $msvcToolsetVersion
        windowsSdkRoot     = $sdkRoot
        windowsSdkVersion  = $sdkVersion
    }
    architectures        = @($architectures)
    includeDebug         = [bool]$IncludeDebug
    layout               = [ordered]@{
        msvcPath       = 'vctools'
        windowsSdkPath = 'winsdk'
    }
    fileCounts           = $counts
    cacheKey             = $cacheKey
    msbuildProperties    = [ordered]@{
        AotAnywhereMsvcPath       = 'vctools'
        AotAnywhereWindowsSdkPath = 'winsdk'
    }
    notes                = @(
        'Private cache artifact only. Do not redistribute Microsoft libraries publicly.',
        'Restore with eng/import-windows-crosslink.ps1 and pass the printed MSBuild properties.'
    )
}

$manifestPath = Join-Path $output 'manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$archiveSha256 = $null
$archiveFullPath = $null
if ($ArchivePath) {
    if (-not $ArchivePath.EndsWith('.tar.gz', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $ArchivePath.EndsWith('.tgz', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'ArchivePath must end with .tar.gz or .tgz.'
    }

    $archiveFullPath = [System.IO.Path]::GetFullPath($ArchivePath)
    $archiveDir = Split-Path -Parent $archiveFullPath
    if ($archiveDir) {
        New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
    }
    if (Test-Path -LiteralPath $archiveFullPath) {
        Remove-Item -LiteralPath $archiveFullPath -Force
    }

    Push-Location $output
    try {
        & tar -czf $archiveFullPath *
        if ($LASTEXITCODE -ne 0) {
            throw "tar failed while creating '$archiveFullPath'."
        }
    }
    finally {
        Pop-Location
    }

    $archiveSha256 = (Get-FileHash -LiteralPath $archiveFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest.archive = [ordered]@{
        path   = $archiveFullPath
        sha256 = $archiveSha256
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

Write-Host ''
Write-Host 'Windows cross-link export complete.'
Write-Host "  OutputDirectory: $output"
Write-Host "  AotAnywhereMsvcPath:       $(Join-Path $output 'vctools')"
Write-Host "  AotAnywhereWindowsSdkPath: $(Join-Path $output 'winsdk')"
Write-Host "  CacheKey: $cacheKey"
if ($archiveFullPath) {
    Write-Host "  ArchivePath: $archiveFullPath"
    Write-Host "  ArchiveSha256: $archiveSha256"
}

# GitHub Actions-friendly outputs when running in CI.
if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "output-directory=$output"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "msvc-path=$(Join-Path $output 'vctools')"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "winsdk-path=$(Join-Path $output 'winsdk')"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "cache-key=$cacheKey"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "msvc-version=$msvcToolsetVersion"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "winsdk-version=$sdkVersion"
    if ($archiveFullPath) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "archive-path=$archiveFullPath"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "archive-sha256=$archiveSha256"
    }
}
