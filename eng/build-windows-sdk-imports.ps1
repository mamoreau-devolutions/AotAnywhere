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
        # implementation moved elsewhere, e.g. into kernelbase.dll) have no
        # RVA column - they don't point to code within this module - and
        # render as:
        #   <ordinal> <hint> <name> (forwarded to OTHERDLL.OtherName)
        # while ordinary exports render as:
        #   <ordinal> <hint> <RVA> <name> [DATA]
        if ($line -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)(?:\s+(DATA))?\s*$') {
            [pscustomobject]@{ Name = $Matches[1]; Data = ($Matches[2] -eq 'DATA') }
        }
        elseif ($line -match '^\s+\d+\s+[0-9A-Fa-f]+\s+(\S+)\s+\(forwarded to [^)]+\)\s*$') {
            [pscustomobject]@{ Name = $Matches[1]; Data = $false }
        }
    }
    if (@($exports).Count -eq 0) {
        throw "No exports were found in '$dll'. Raw dumpbin output:`n$($lines -join "`n")"
    }
    $exports
}

function Build-ImportLibrary {
    param(
        [Parameter(Mandatory)] [string] $DllName,
        [Parameter(Mandatory)] [string] $Destination,
        # Some SDK import libraries do not correspond to a real on-disk DLL:
        # they are "virtual" API set contracts (e.g. Synchronization.lib ->
        # api-ms-win-core-synch-l1-2-0.dll) that the OS loader redirects to
        # a real implementing DLL at load time. There is no physical file
        # to run dumpbin against for those, so ExportSourceDll lets exports
        # be read from the real host DLL instead, while ImportDllName keeps
        # the generated .lib's embedded import-table entry set to the
        # contract name so the loader's API set redirection still applies
        # normally at runtime on the eventual target machine.
        [string] $ExportSourceDll,
        [string] $ImportDllName,
        [string[]] $OnlyNames
    )

    $sourceDllName = if ($ExportSourceDll) { $ExportSourceDll } else { $DllName }
    $dll = Join-Path $DllRoot "$sourceDllName.dll"
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        throw "Required Windows DLL was not found: $dll"
    }
    $libraryName = if ($ImportDllName) { $ImportDllName } else { "$DllName.dll" }

    $def = Join-Path ([System.IO.Path]::GetDirectoryName($Destination)) "$DllName.def"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("LIBRARY $libraryName")
    $lines.Add('EXPORTS')
    $exports = Get-Exports $dll
    if ($OnlyNames) {
        $names = [System.Collections.Generic.HashSet[string]]::new([string[]] $exports.Name)
        $missing = $OnlyNames | Where-Object { -not $names.Contains($_) }
        if ($missing) {
            throw "Expected export(s) not found in '$dll': $($missing -join ', ')"
        }
        $exports = $exports | Where-Object { $OnlyNames -contains $_.Name }
    }
    foreach ($export in $exports) {
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
        '-l' $Destination
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "llvm-dlltool failed to create '$Destination'."
    }
    Remove-Item -LiteralPath $def -Force
}

# Synchronization.lib is a virtual API set contract with no physical DLL on
# disk; its functions (WaitOnAddress/WakeByAddress*) are implemented in and
# exported directly by kernelbase.dll.
$importOverrides = @{
    'Synchronization' = @{
        ExportSourceDll = 'kernelbase'
        ImportDllName   = 'api-ms-win-core-synch-l1-2-0.dll'
        OnlyNames       = @('WaitOnAddress', 'WakeByAddressAll', 'WakeByAddressSingle')
    }
}

foreach ($name in $umLibraries) {
    $destination = Join-Path $um "$name.lib"
    if ($importOverrides.ContainsKey($name)) {
        $o = $importOverrides[$name]
        Build-ImportLibrary $name $destination -ExportSourceDll $o.ExportSourceDll -ImportDllName $o.ImportDllName -OnlyNames $o.OnlyNames
    }
    else {
        Build-ImportLibrary $name $destination
    }
}
Build-ImportLibrary 'ucrtbase' (Join-Path $ucrt 'ucrt.lib')
Copy-Item (Join-Path $ucrt 'ucrt.lib') (Join-Path $ucrt 'libucrt.lib')

Write-Host "Generated Windows SDK import libraries for $Architecture in $OutputDirectory"
