[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $DllRoot,

    [Parameter(Mandatory)]
    [string] $OutputDirectory,

    [Parameter(Mandatory)]
    [string] $LlvmBinDirectory,

    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = 'x64',

    [string] $DumpbinPath = 'dumpbin.exe'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $DllRoot -PathType Container)) {
    throw "Windows DLL root does not exist: $DllRoot"
}
if (-not (Test-Path -LiteralPath $LlvmBinDirectory -PathType Container)) {
    throw "LLVM bin directory does not exist: $LlvmBinDirectory"
}
$dllTool = Join-Path $LlvmBinDirectory 'llvm-dlltool.exe'
if (-not (Test-Path -LiteralPath $dllTool -PathType Leaf)) {
    throw "llvm-dlltool.exe was not found under '$LlvmBinDirectory'."
}

$machine = if ($Architecture -eq 'x64') { 'i386:x86-64' } else { 'arm64' }
$archName = if ($Architecture -eq 'x64') { 'x86_64' } else { 'aarch64' }
$root = Join-Path $OutputDirectory 'Lib'
$um = Join-Path $root "um\$archName"
$ucrt = Join-Path $root "ucrt\$archName"
New-Item -ItemType Directory -Force -Path $um, $ucrt | Out-Null

# These are the SDK libraries referenced by NativeAOT's Windows targets. The
# DLLs are read only on the Windows build runner; only generated import
# libraries are emitted.
$umLibraries = @(
    'advapi32', 'bcrypt', 'crypt32', 'iphlpapi', 'kernel32', 'mswsock',
    'ncrypt', 'normaliz', 'ntdll', 'ole32', 'oleaut32', 'secur32',
    'Synchronization', 'user32', 'version', 'ws2_32'
)

function Get-Exports([string] $dll) {
    $lines = & $DumpbinPath /exports $dll 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dumpbin failed for '$dll'."
    }

    $exports = foreach ($line in $lines) {
        # Forwarded exports (the entire symbol table of some system DLLs,
        # e.g. normaliz.dll on current Windows versions, since their real
        # implementation moved elsewhere) render as:
        #   <ordinal> <hint> <RVA> <name> (forwarded to OTHERDLL.OtherName)
        # The forwarder suffix carries no information the linker needs -
        # the name/ordinal/DATA-ness of the export are unchanged - so it is
        # matched and discarded here rather than rejecting the whole line.
        if ($line -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)(?:\s+(DATA))?(?:\s+\(forwarded to [^)]+\))?\s*$') {
            [pscustomobject]@{ Name = $Matches[1]; Data = ($Matches[2] -eq 'DATA') }
        }
    }
    if (@($exports).Count -eq 0) {
        throw "No exports were found in '$dll'. Raw dumpbin output:`n$($lines -join "`n")"
    }
    $exports
}

function Build-ImportLibrary([string] $dllName, [string] $destination) {
    $dll = Join-Path $DllRoot "$dllName.dll"
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        throw "Required Windows DLL was not found: $dll"
    }

    $def = Join-Path ([System.IO.Path]::GetDirectoryName($destination)) "$dllName.def"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("LIBRARY $dllName.dll")
    $lines.Add('EXPORTS')
    foreach ($export in Get-Exports $dll) {
        $suffix = if ($export.Data) { ' DATA' } else { '' }
        $lines.Add("    $($export.Name)$suffix")
    }
    Set-Content -LiteralPath $def -Value $lines -Encoding ascii

    # Use the short-form flags (-m/-d/-l): llvm-dlltool's long "--machine="
    # alias goes through option-alias resolution that this LLVM build does
    # not appear to honor reliably, silently falling back to a broken
    # host-default machine detection and failing with "unknown target".
    & $dllTool '-m' $machine `
        '-d' $def `
        '-l' $destination
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw "llvm-dlltool failed to create '$destination'."
    }
    Remove-Item -LiteralPath $def -Force
}

foreach ($name in $umLibraries) {
    Build-ImportLibrary $name (Join-Path $um "$name.lib")
}
Build-ImportLibrary 'ucrtbase' (Join-Path $ucrt 'ucrt.lib')
Copy-Item (Join-Path $ucrt 'ucrt.lib') (Join-Path $ucrt 'libucrt.lib')

Write-Host "Generated Windows SDK import libraries for $Architecture in $OutputDirectory"
