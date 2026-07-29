[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PackageId,

    [string] $ManifestPath = (Join-Path $PSScriptRoot 'toolchain-artifacts.json'),

    [string] $DownloadDirectory = (Join-Path $PSScriptRoot '..\artifacts\toolchain-downloads'),

    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts\toolchain-packages')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Toolchain artifact manifest does not exist: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$artifact = @($manifest.clangToolsets) + @($manifest.linuxSysroots) |
    Where-Object { $_.packageId -eq $PackageId } |
    Select-Object -First 1

if ($null -eq $artifact) {
    throw "No packable artifact with package ID '$PackageId' exists in $ManifestPath."
}

New-Item -ItemType Directory -Force -Path $DownloadDirectory, $OutputDirectory | Out-Null

$fileName = [System.IO.Path]::GetFileName(([uri]$artifact.url).AbsolutePath)
$archive = Join-Path $DownloadDirectory $fileName
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    Write-Host "Downloading $($artifact.url)"
    Invoke-WebRequest -Uri $artifact.url -OutFile $archive
}

$payload = Join-Path $OutputDirectory "$($artifact.packageId).payload"
$kind = if ($null -ne $artifact.hostRuntimeIdentifier) { 'clang' } else { 'sysroot' }

& (Join-Path $PSScriptRoot 'prepare-toolchain-payload.ps1') `
    -Kind $kind `
    -ArchivePath $archive `
    -Sha256 $artifact.sha256 `
    -PayloadDirectory $payload

& (Join-Path $PSScriptRoot 'pack-toolchain-content.ps1') `
    -PackageId $artifact.packageId `
    -Version $artifact.packageVersion `
    -PayloadDirectory $payload `
    -OutputDirectory $OutputDirectory
