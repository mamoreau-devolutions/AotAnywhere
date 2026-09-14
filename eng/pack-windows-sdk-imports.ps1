[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PayloadDirectory,

    [Parameter(Mandatory)]
    [string] $OutputDirectory,

    [string] $Version
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath (Join-Path $PayloadDirectory 'Lib') -PathType Container)) {
    throw "Windows SDK import payload must contain Lib/: $PayloadDirectory"
}
foreach ($architecture in @('x86_64', 'aarch64')) {
    foreach ($kind in @('ucrt', 'um')) {
        $directory = Join-Path $PayloadDirectory "Lib\$kind\$architecture"
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Windows SDK import payload is missing ${kind}/${architecture}: $directory"
        }
    }
}

$project = Join-Path $PSScriptRoot '..\src\AotAnywhere.nuproj'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$arguments = @(
    'pack', $project,
    '-p:AotAnywhereWindowsSdkImportsPayloadDir=' + (Resolve-Path -LiteralPath $PayloadDirectory).Path,
    '--output', $OutputDirectory
)
if ($Version) { $arguments += '-p:Version=' + $Version }
& dotnet @arguments
if ($LASTEXITCODE -ne 0) {
    throw "dotnet pack failed for the AotAnywhere package."
}
