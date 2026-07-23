[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('clang', 'sysroot')]
    [string] $Kind,

    [Parameter(Mandatory)]
    [string] $ArchivePath,

    [Parameter(Mandatory)]
    [string] $Sha256,

    [Parameter(Mandatory)]
    [string] $PayloadDirectory
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Artifact does not exist: $ArchivePath"
}

$actualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $Sha256.ToLowerInvariant()) {
    throw "SHA-256 mismatch for $ArchivePath. Expected $Sha256, got $actualHash."
}

$archive = (Resolve-Path -LiteralPath $ArchivePath).Path
$payload = [System.IO.Path]::GetFullPath($PayloadDirectory)
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("aotanywhere-toolchain-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    if ($archive.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        $installer = Start-Process -FilePath $archive -ArgumentList "/S", "/D=$staging" -Wait -PassThru
        if ($installer.ExitCode -ne 0) {
            throw "LLVM installer exited with code $($installer.ExitCode)."
        }
    }
    else {
        & tar -xf $archive -C $staging
        if ($LASTEXITCODE -ne 0) {
            throw "Could not extract $archive."
        }
    }

    Remove-Item -LiteralPath $payload -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $payload | Out-Null

    if ($Kind -eq 'sysroot') {
        $sysrootCandidates = @((Get-Item -LiteralPath $staging)) + @(Get-ChildItem -LiteralPath $staging -Directory)
        $sysrootSource = $sysrootCandidates |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'usr') } |
            Select-Object -First 1
        if ($null -eq $sysrootSource) {
            throw "Could not find a Linux sysroot root under $staging."
        }

        $sysrootDestination = Join-Path $payload 'sysroot'
        New-Item -ItemType Directory -Force -Path $sysrootDestination | Out-Null
        Get-ChildItem -LiteralPath $sysrootSource.FullName -Force |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $sysrootDestination -Recurse }
        return
    }

    $source = Get-ChildItem -LiteralPath $staging -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin') } |
        Select-Object -First 1
    if ($null -eq $source) {
        if (Test-Path -LiteralPath (Join-Path $staging 'bin')) {
            $source = Get-Item -LiteralPath $staging
        }
        else {
            throw "Could not find an LLVM distribution root under $staging."
        }
    }

    $binDestination = Join-Path $payload 'bin'
    New-Item -ItemType Directory -Force -Path $binDestination | Out-Null
    $toolNames = 'clang', 'clang++', 'ld.lld', 'ld64.lld', 'lld-link', 'llvm-objcopy', 'llvm-ar', 'llvm-ranlib'
    foreach ($tool in $toolNames) {
        foreach ($candidate in @(
            (Join-Path $source.FullName "bin/$tool"),
            (Join-Path $source.FullName "bin/$tool.exe")
        )) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                Copy-Item -LiteralPath $candidate -Destination $binDestination
                break
            }
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $binDestination 'clang')) -and
        -not (Test-Path -LiteralPath (Join-Path $binDestination 'clang.exe'))) {
        throw "The extracted LLVM distribution has no clang executable."
    }

    $resourceSource = Join-Path $source.FullName 'lib/clang'
    if (-not (Test-Path -LiteralPath $resourceSource -PathType Container)) {
        throw "The extracted LLVM distribution has no Clang resource directory."
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $payload 'lib') | Out-Null
    Copy-Item -LiteralPath $resourceSource -Destination (Join-Path $payload 'lib/clang') -Recurse

    foreach ($libraryRoot in @((Join-Path $source.FullName 'bin'), (Join-Path $source.FullName 'lib'))) {
        if (-not (Test-Path -LiteralPath $libraryRoot -PathType Container)) {
            continue
        }

        $libraryDestination = if ($libraryRoot -eq (Join-Path $source.FullName 'bin')) {
            $binDestination
        }
        else {
            Join-Path $payload 'lib'
        }
        New-Item -ItemType Directory -Force -Path $libraryDestination | Out-Null

        Get-ChildItem -LiteralPath $libraryRoot -File |
            Where-Object {
                $_.Name -match '\.dll$|\.dylib$|\.so(\.[0-9.]+)?$'
            } |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $libraryDestination
            }
    }
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
