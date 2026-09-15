[CmdletBinding()]
param(
    [string] $SourceDirectory = (Join-Path $PSScriptRoot 'aotcrtstub'),

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

# aotcrtstub.c initializes IMAGE_LOAD_CONFIG_DIRECTORY64.GuardFlags from the
# address of the absolute symbol "__guard_flags" truncated to DWORD:
#   .GuardFlags = (DWORD)(ULONG_PTR)&__guard_flags,
# MSVC's cl.exe accepts a pointer-to-integer-truncation as a static
# initializer here (the linker resolves it as a relocation); clang-cl
# rejects it as "initializer element is not a compile-time constant"
# regardless of /std: dialect - this is a Sema constant-expression
# restriction, not a conformance-mode toggle.
#
# GuardFlags only matters when the final link enables Control Flow Guard
# (/guard:cf). Per the source's own comments, the linker only *warns* -
# it does not error - when the load config directory does not already
# reference the CFG tables it synthesizes, and the resulting image is
# simply not treated as CFG-guarded by the loader. Hard-coding GuardFlags
# to 0 here reproduces exactly that already-accepted degraded state (no
# CFG enforcement), which is fine since AotAnywhere does not request
# /guard:cf for its NativeAOT links. This patch is applied to a build-time
# copy only; the pinned upstream source is left untouched.
function Set-GuardFlagsConstant([string] $sourcePath, [string] $patchedPath) {
    $content = Get-Content -LiteralPath $sourcePath -Raw
    $needle = '.GuardFlags = (DWORD)(ULONG_PTR)&__guard_flags,'
    if ($content -notlike "*$needle*") {
        throw "aotcrtstub.c no longer contains the expected GuardFlags initializer; the clang-cl workaround needs to be revisited."
    }
    $content = $content.Replace($needle, '.GuardFlags = 0, /* patched: see build-aot-crt-stub.ps1 */')
    Set-Content -LiteralPath $patchedPath -Value $content -NoNewline
}

function Build-Architecture([string] $name, [string] $assembler) {
    $dir = Join-Path $OutputDirectory $name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $c = Join-Path $dir 'aotcrtstub.c.obj'
    $cpp = Join-Path $dir 'aotcrtstubcpp.cpp.obj'
    $asm = Join-Path $dir 'aotcrtstub.asm.obj'
    $extraC = Join-Path $dir 'aotcrtstub-extra.c.obj'
    # Wrapped in @(...): PowerShell unrolls a single-element array returned
    # from an if/else expression back into a bare string when only one item
    # flows through the pipeline, which would make "@target" splat the
    # string's individual characters as separate arguments instead of one
    # "--target=..." argument.
    $target = @(if ($name -eq 'x86_64') { } else { '--target=arm64-pc-windows-msvc' })
    $patchedC = Join-Path $dir 'aotcrtstub.patched.c'
    Set-GuardFlagsConstant (Join-Path $SourceDirectory 'aotcrtstub.c') $patchedC
    & $clang @target /nologo /c /GS- /Gs1000000 /EHs-c- /GR- `
        "/Fo$c" $patchedC
    if ($LASTEXITCODE) { throw "clang-cl failed for $name C source." }
    & $clang @target /nologo /c /GS- /Gs1000000 /EHs-c- /GR- `
        "/Fo$cpp" (Join-Path $SourceDirectory 'aotcrtstubcpp.cpp')
    if ($LASTEXITCODE) { throw "clang-cl failed for $name C++ source." }
    # aotcrtstub-extra.c is AotAnywhere's own addition (not vendored from
    # upstream): the AotCrtInterlockedXxx helper bodies that
    # aotcrtstub-extra-arm64.asm's _InterlockedXxx tail-branch trampolines
    # jump into (the ARM64 NativeAOT bootstrapper objects reference the real
    # _InterlockedXxx names directly, which MSVC always inlines on x86_64
    # instead, leaving no external reference there). It compiles to an
    # empty translation unit on x86_64 (see the file's #if guard), so it is
    # built unconditionally for simplicity.
    & $clang @target /nologo /c /GS- /Gs1000000 /EHs-c- /GR- `
        "/Fo$extraC" (Join-Path $PSScriptRoot 'aotcrtstub-extra.c')
    if ($LASTEXITCODE) { throw "clang-cl failed for $name aotcrtstub-extra.c." }
    $extraObjs = @($extraC)
    if ($name -eq 'x86_64') {
        & $assembler /c "/Fo$asm" (Join-Path $SourceDirectory 'aotcrtstub_amd64.asm')
    } else {
        # armasm64.exe has no "-c" (compile-only) switch: it always
        # produces a single object file from a single source file, invoked
        # as "armasm64 [options] -o objectfile sourcefile".
        & $assembler -nologo -o $asm (Join-Path $SourceDirectory 'aotcrtstub_arm64.asm')
        if ($LASTEXITCODE) { throw "assembler failed for $name." }
        # AotAnywhere's own addition: __security_push_cookie /
        # __security_pop_cookie, referenced by ARM64 NativeAOT bootstrapper
        # objects but not part of the vendored aotcrtstub_arm64.asm.
        $extraAsm = Join-Path $dir 'aotcrtstub-extra-arm64.asm.obj'
        & $assembler -nologo -o $extraAsm (Join-Path $PSScriptRoot 'aotcrtstub-extra-arm64.asm')
        if ($LASTEXITCODE) { throw "assembler failed for $name aotcrtstub-extra-arm64.asm." }
        $extraObjs += $extraAsm
    }
    if ($LASTEXITCODE) { throw "assembler failed for $name." }
    & $llvmLib /nologo "/out:$(Join-Path $dir 'aotcrtstub.lib')" $c $cpp $asm @extraObjs
    if ($LASTEXITCODE) { throw "llvm-lib failed for $name." }
    # Use the short-form flags (-m/-d/-l): llvm-dlltool's long "--machine="
    # alias goes through option-alias resolution that this LLVM build does
    # not appear to honor reliably, silently falling back to a broken
    # host-default machine detection and failing with "unknown target".
    $machine = if ($name -eq 'x86_64') { 'i386:x86-64' } else { 'arm64' }
    & $dllTool '-m' $machine `
        '-d' (Join-Path $SourceDirectory 'ntdllcrt.def') `
        '-l' (Join-Path $dir 'ntdllcrt.lib')
    if ($LASTEXITCODE) { throw "llvm-dlltool failed for $name." }
}

Build-Architecture 'x86_64' $ml64
Build-Architecture 'aarch64' $armasm
