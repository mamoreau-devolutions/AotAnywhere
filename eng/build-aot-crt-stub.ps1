[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SourceDirectory,

    [Parameter(Mandatory)]
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "NativeAOT CRT stub source directory does not exist: $SourceDirectory"
}
# armasm64.exe lives under the MSVC toolset's Host*\arm64 bin directory, which
# msvc-dev-cmd does not add to PATH when the active host/target arch is x64.
# Resolve it explicitly from VCToolsInstallDir instead of relying on PATH.
function Resolve-Tool([string] $name, [string[]] $extraSearchDirs = @()) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($dir in $extraSearchDirs) {
        if (-not $dir) { continue }
        $found = Get-ChildItem -LiteralPath $dir -Filter $name -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    throw "Could not locate required tool '$name' on PATH or under: $($extraSearchDirs -join ', ')"
}

$armasmSearchDirs = @()
if ($env:VCToolsInstallDir) {
    $armasmSearchDirs += (Join-Path $env:VCToolsInstallDir 'bin')
}

$clang = Resolve-Tool 'clang-cl.exe'
$llvmLib = Resolve-Tool 'llvm-lib.exe'
$ml64 = Resolve-Tool 'ml64.exe'
$armasm = Resolve-Tool 'armasm64.exe' $armasmSearchDirs
$dllTool = Resolve-Tool 'llvm-dlltool.exe'

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$sourceFiles = @('aotcrtstub.c', 'aotcrtstubcpp.cpp', 'aotcrtstub_amd64.asm', 'aotcrtstub_arm64.asm', 'ntdllcrt.def')
foreach ($file in $sourceFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $file) -PathType Leaf)) {
        throw "CRT stub source is missing '$file'."
    }
}

function Build-Architecture([string] $name, [string] $assembler) {
    $dir = Join-Path $OutputDirectory $name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $c = Join-Path $dir 'aotcrtstub.c.obj'
    $cpp = Join-Path $dir 'aotcrtstubcpp.cpp.obj'
    $asm = Join-Path $dir 'aotcrtstub.asm.obj'
    $target = if ($name -eq 'x86_64') { @() } else { @('--target=arm64-pc-windows-msvc') }
    # No explicit /std:c11: strict ISO C11 conformance rejects the
    # MSVC-style truncated address constants (e.g. "(DWORD)&__guard_flags"
    # for the load-config directory's absolute guard symbols) that
    # clang-cl's default MSVC-compatible dialect accepts.
    & $clang @target /nologo /c /GS- /Gs1000000 /EHs-c- /GR- `
        "/Fo$c" (Join-Path $SourceDirectory 'aotcrtstub.c')
    if ($LASTEXITCODE) { throw "clang-cl failed for $name C source." }
    & $clang @target /nologo /c /GS- /Gs1000000 /EHs-c- /GR- `
        "/Fo$cpp" (Join-Path $SourceDirectory 'aotcrtstubcpp.cpp')
    if ($LASTEXITCODE) { throw "clang-cl failed for $name C++ source." }
    if ($name -eq 'x86_64') {
        & $assembler /c "/Fo$asm" (Join-Path $SourceDirectory 'aotcrtstub_amd64.asm')
    } else {
        & $assembler -nologo -c -o $asm (Join-Path $SourceDirectory 'aotcrtstub_arm64.asm')
    }
    if ($LASTEXITCODE) { throw "assembler failed for $name." }
    & $llvmLib /nologo "/out:$(Join-Path $dir 'aotcrtstub.lib')" $c $cpp $asm
    if ($LASTEXITCODE) { throw "llvm-lib failed for $name." }
    $machine = if ($name -eq 'x86_64') { 'i386:x86-64' } else { 'arm64' }
    & $dllTool "--machine=$machine" `
        "--input-def=$(Join-Path $SourceDirectory 'ntdllcrt.def')" `
        "--output-lib=$(Join-Path $dir 'ntdllcrt.lib')"
    if ($LASTEXITCODE) { throw "llvm-dlltool failed for $name." }
}

Build-Architecture 'x86_64' $ml64
Build-Architecture 'aarch64' $armasm
