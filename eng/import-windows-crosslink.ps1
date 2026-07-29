#Requires -Version 7.0
<#
.SYNOPSIS
  Restore a previously exported Windows cross-link library tree.

.DESCRIPTION
  Imports an archive or staged directory produced by
  eng/export-windows-crosslink.ps1, validates the AotAnywhere layout, and prints
  the MSBuild properties / GitHub Actions cache values needed to link win-x64
  and win-arm64 from Linux or macOS hosts.

  Expected layout:

    <Destination>/
      vctools/lib/{x64,arm64}/*.lib
      winsdk/Lib/<10.*>/{ucrt,um}/{x64,arm64}/*.lib
      manifest.json

.PARAMETER ArchivePath
  Path to a .tar.gz/.tgz archive created by export-windows-crosslink.ps1.

.PARAMETER SourceDirectory
  Already-extracted export directory. Mutually exclusive with ArchivePath.

.PARAMETER Destination
  Directory that will contain the restored vctools/ and winsdk/ roots.

.PARAMETER ExpectedSha256
  Optional SHA-256 of ArchivePath. Verified before extraction when provided.

.PARAMETER Architectures
  Architectures that must be present after restore. Defaults to x64 and arm64.

.PARAMETER KeepExisting
  Do not delete Destination before restore. Off by default.
#>
[CmdletBinding()]
param(
    [string] $ArchivePath,

    [string] $SourceDirectory,

    [Parameter(Mandatory)]
    [string] $Destination,

    [string] $ExpectedSha256,

    [string[]] $Architectures = @('x64', 'arm64'),

    [switch] $KeepExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-OneSource {
    $hasArchive = -not [string]::IsNullOrWhiteSpace($ArchivePath)
    $hasSource = -not [string]::IsNullOrWhiteSpace($SourceDirectory)
    if ($hasArchive -eq $hasSource) {
        throw 'Specify exactly one of -ArchivePath or -SourceDirectory.'
    }
}

function Get-ManifestObject {
    param([Parameter(Mandatory)] [string] $Root)

    $manifestPath = Join-Path $Root 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Restored tree is missing manifest.json under '$Root'."
    }

    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Assert-CrossLinkLayout {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string[]] $Arches
    )

    $msvcPath = Join-Path $Root 'vctools'
    $sdkPath = Join-Path $Root 'winsdk'
    $sdkLibRoot = Join-Path $sdkPath 'Lib'

    if (-not (Test-Path -LiteralPath (Join-Path $msvcPath 'lib') -PathType Container)) {
        throw "MSVC root is missing lib/: $msvcPath"
    }
    if (-not (Test-Path -LiteralPath $sdkLibRoot -PathType Container)) {
        throw "Windows SDK root is missing Lib/: $sdkPath"
    }

    $sdkVersionDir = Get-ChildItem -LiteralPath $sdkLibRoot -Directory |
        Where-Object { $_.Name -like '10.*' } |
        Sort-Object Name |
        Select-Object -Last 1
    if (-not $sdkVersionDir) {
        throw "No Windows 10 SDK Lib version directory exists under '$sdkLibRoot'."
    }

    $requiredMsvc = @('libcmt.lib', 'libvcruntime.lib', 'vcruntime.lib', 'oldnames.lib')
    foreach ($arch in $Arches) {
        $msvcLibDir = Join-Path $msvcPath "lib\$arch"
        if (-not (Test-Path -LiteralPath $msvcLibDir -PathType Container)) {
            throw "Missing MSVC architecture directory: $msvcLibDir"
        }
        foreach ($name in $requiredMsvc) {
            if (-not (Test-Path -LiteralPath (Join-Path $msvcLibDir $name) -PathType Leaf)) {
                throw "Missing required MSVC library '$name' under '$msvcLibDir'."
            }
        }

        $ucrtDir = Join-Path $sdkVersionDir.FullName "ucrt\$arch"
        $umDir = Join-Path $sdkVersionDir.FullName "um\$arch"
        if (-not (Test-Path -LiteralPath $ucrtDir -PathType Container)) {
            throw "Missing Windows SDK UCRT directory: $ucrtDir"
        }
        if (-not (Test-Path -LiteralPath $umDir -PathType Container)) {
            throw "Missing Windows SDK UM directory: $umDir"
        }
        foreach ($name in @('ucrt.lib', 'libucrt.lib')) {
            if (-not (Test-Path -LiteralPath (Join-Path $ucrtDir $name) -PathType Leaf)) {
                throw "Missing required UCRT library '$name' under '$ucrtDir'."
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $umDir 'kernel32.lib') -PathType Leaf)) {
            throw "Missing required UM library 'kernel32.lib' under '$umDir'."
        }
    }

    return [pscustomobject]@{
        MsvcPath          = (Resolve-Path -LiteralPath $msvcPath).Path
        WindowsSdkPath    = (Resolve-Path -LiteralPath $sdkPath).Path
        WindowsSdkVersion = $sdkVersionDir.Name
    }
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

Assert-OneSource

$destination = [System.IO.Path]::GetFullPath($Destination)
$architectures = Normalize-Architectures -Values $Architectures

if (-not $KeepExisting -and (Test-Path -LiteralPath $destination)) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $destination | Out-Null

if ($ArchivePath) {
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Archive does not exist: $ArchivePath"
    }

    $archive = (Resolve-Path -LiteralPath $ArchivePath).Path
    if ($ExpectedSha256) {
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
            throw "SHA-256 mismatch for '$archive'. Expected $ExpectedSha256, got $actual."
        }
    }

    & tar -xzf $archive -C $destination
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed while extracting '$archive'."
    }
}
else {
    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        throw "Source directory does not exist: $SourceDirectory"
    }

    $source = (Resolve-Path -LiteralPath $SourceDirectory).Path
    # Support either the export root itself or a parent that contains it.
    if (Test-Path -LiteralPath (Join-Path $source 'vctools') -PathType Container) {
        Copy-Item -LiteralPath (Join-Path $source '*') -Destination $destination -Recurse -Force
    }
    elseif (Test-Path -LiteralPath (Join-Path $source 'manifest.json') -PathType Leaf) {
        Copy-Item -LiteralPath (Join-Path $source '*') -Destination $destination -Recurse -Force
    }
    else {
        throw "Source directory '$source' does not look like an AotAnywhere Windows cross-link export."
    }
}

# Some archives may nest a single top-level directory. Flatten one level if needed.
if (-not (Test-Path -LiteralPath (Join-Path $destination 'vctools') -PathType Container)) {
    $nested = Get-ChildItem -LiteralPath $destination -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'vctools') -PathType Container } |
        Select-Object -First 1
    if ($nested) {
        Get-ChildItem -LiteralPath $nested.FullName | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $destination -Force
        }
        Remove-Item -LiteralPath $nested.FullName -Recurse -Force
    }
}

$manifest = $null
if (Test-Path -LiteralPath (Join-Path $destination 'manifest.json') -PathType Leaf) {
    $manifest = Get-ManifestObject -Root $destination
}

$layout = Assert-CrossLinkLayout -Root $destination -Arches $architectures
$cacheKey = if ($manifest -and $manifest.cacheKey) { [string]$manifest.cacheKey } else { $null }
$msvcVersion = if ($manifest -and $manifest.source -and $manifest.source.msvcToolsetVersion) {
    [string]$manifest.source.msvcToolsetVersion
}
else {
    'unknown'
}

Write-Host 'Windows cross-link import complete.'
Write-Host "  Destination: $destination"
Write-Host "  AotAnywhereMsvcPath:       $($layout.MsvcPath)"
Write-Host "  AotAnywhereWindowsSdkPath: $($layout.WindowsSdkPath)"
Write-Host "  WindowsSdkVersion: $($layout.WindowsSdkVersion)"
Write-Host "  MsvcVersion: $msvcVersion"
if ($cacheKey) {
    Write-Host "  CacheKey: $cacheKey"
}
Write-Host ''
Write-Host 'MSBuild example:'
Write-Host "  /p:AotAnywhereMsvcPath=$($layout.MsvcPath)"
Write-Host "  /p:AotAnywhereWindowsSdkPath=$($layout.WindowsSdkPath)"

if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "destination=$destination"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "msvc-path=$($layout.MsvcPath)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "winsdk-path=$($layout.WindowsSdkPath)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "winsdk-version=$($layout.WindowsSdkVersion)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "msvc-version=$msvcVersion"
    if ($cacheKey) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "cache-key=$cacheKey"
    }
}
