[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PayloadDirectory,

    [Parameter(Mandatory)]
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PayloadDirectory -PathType Container)) {
    throw "CRT stub payload directory does not exist: $PayloadDirectory"
}

foreach ($architecture in @('x86_64', 'aarch64')) {
    $directory = Join-Path $PayloadDirectory $architecture
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "CRT stub payload is missing architecture directory: $directory"
    }

    foreach ($library in @('aotcrtstub.lib', 'ntdllcrt.lib')) {
        $path = Join-Path $directory $library
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "CRT stub payload is missing '$library' for ${architecture}: $path"
        }
    }
}

$project = Join-Path $PSScriptRoot '..\src\AotAnywhere.nuproj'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
dotnet pack $project `
    -p:AotAnywhereAotCrtStubPayloadDir=(Resolve-Path -LiteralPath $PayloadDirectory).Path `
    --output $OutputDirectory

if ($LASTEXITCODE -ne 0) {
    throw "dotnet pack failed for the AotAnywhere package."
}
