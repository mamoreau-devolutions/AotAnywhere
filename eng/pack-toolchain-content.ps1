[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PackageId,

    [Parameter(Mandatory)]
    [string] $Version,

    [Parameter(Mandatory)]
    [string] $PayloadDirectory,

    [Parameter(Mandatory)]
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PayloadDirectory -PathType Container)) {
    throw "Payload directory does not exist: $PayloadDirectory"
}

$PayloadDirectory = (Resolve-Path -LiteralPath $PayloadDirectory).Path
$project = Join-Path $PSScriptRoot '..\src\toolchains\AotAnywhere.ToolchainContent.nuproj'
dotnet pack $project `
    -p:AotAnywhereToolchainPackageId=$PackageId `
    -p:AotAnywhereToolchainPayloadDir=$PayloadDirectory `
    -p:Version=$Version `
    --output $OutputDirectory

if ($LASTEXITCODE -ne 0) {
    throw "dotnet pack failed for $PackageId."
}
