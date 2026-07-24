# AotAnywhere

**Cross-compile [Native AOT](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/) .NET apps to Linux, macOS and Windows — from any of them.**

[PublishAot](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
normally refuses to build for another OS:

```sh
$ dotnet publish -r linux-x64
Microsoft.NETCore.Native.Publish.targets(59,5): error : Cross-OS native compilation is not supported.
```

AotAnywhere is a NuGet package that lifts that restriction. Add it to your
project and `dotnet publish -r <rid>` just works for Linux, macOS and Windows
RIDs, from a Windows, macOS or Linux machine. It uses Clang, LLD, and
versioned target sysroots, restored through host-specific NuGet content
packages, so no CMake installation or separately configured cross toolchain is
required on the build machine.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/platform-matrix-dark.svg">
    <img alt="Diagram: builds on Windows (x64, arm64), macOS (arm64, x64) and Linux (x64, arm64) hosts, through AotAnywhere (dotnet publish -r <rid>), and runs on Linux glibc and musl (x64, arm64, arm), macOS (osx-arm64, osx-x64) and Windows (win-x64, win-arm64)." src="docs/assets/platform-matrix-light.svg" width="880">
  </picture>
</p>

## Quick start

1. In a project that already uses Native AOT, add an `Sdk` reference to
   [`StuDev.AotAnywhere`](https://www.nuget.org/packages/StuDev.AotAnywhere)
   inside the `<Project>` element:

   ```xml
   <Project Sdk="Microsoft.NET.Sdk">

     <Sdk Name="StuDev.AotAnywhere" Version="1.0.4" />
   ```

   (Or omit the `Version` and pin it once in `global.json` under
   [`msbuild-sdks`](https://learn.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk#how-project-sdks-are-resolved).)

2. Publish for one of the newly available RIDs:

   ```sh
   dotnet publish -r linux-x64        # or linux-arm64
   dotnet publish -r linux-musl-x64   # or linux-musl-arm64, linux-musl-arm*
   dotnet publish -r osx-x64          # or osx-arm64
   dotnet publish -r win-x64          # or win-arm64
   ```

That's it — no other tools or CMake installation required. The package supplies
the required Clang/LLD runtime and target sysroot packages, while retaining its
managed symbol-strip implementation.

> **Why an `Sdk` reference and not a `PackageReference`?** The package pulls in
> its Clang/LLD toolset and target sysroot through host-specific NuGet content
> packages, and
> NuGet cannot restore package references declared inside a package's build
> targets ([NuGet/Home#4790](https://github.com/NuGet/Home/issues/4790)). SDK
> props *are* evaluated during restore, so the `Sdk` form fetches everything the
> first time with no further setup. A plain `PackageReference` still works if you
> restore the matching content packages yourself — see [Advanced configuration](docs/advanced-configuration.md).

## Supported platforms

**Host machines** (where you run `dotnet publish`):

- **Windows** (x64, arm64)
- **macOS** (x64, arm64)
- **Linux** (x64, arm64)

**Targets** (what you can publish for), from any supported host:

| Target | RIDs | Notes |
| --- | --- | --- |
| **Linux** | `linux-x64`, `linux-arm64`, `linux-musl-x64`, `linux-musl-arm64`, `linux-musl-arm` | Ubuntu 18.04 glibc and Alpine 3.17 musl sysroots. `linux-musl-arm` requires `net9.0`+. |
| **Linux glibc (deferred)** | `linux-arm` | CBake's Ubuntu 18.04 ARM sysroot has glibc 2.27, below the .NET 9 ARM Native AOT time64 ABI baseline. |
| **macOS** | `osx-x64`, `osx-arm64` | Links against bundled Apple linker stubs. See [macOS targets](docs/macos-targets.md). |
| **Windows** | `win-x64`, `win-arm64` | Native Windows hosts use MSVC. Linux/macOS cross-links use LLD once the versioned MSVC/Windows SDK cross-link package is published. See [Windows targets](docs/windows-targets.md). |

## Things to be aware of

- **ARMv7 musl requires .NET 9 or later.** `linux-musl-arm` uses the published
  CBake Alpine 3.17 sysroot. `linux-arm` remains deferred until CBake provides
  an ARM glibc sysroot with the .NET 9 time64 ABI baseline.

- **macOS binaries need signing before you distribute them.** Out of the box the
  output has an ad-hoc signature for local execution. To hand it to other people
  you must sign it with a Developer ID
  certificate and notarize it — both doable from any host, no Mac required. See
  [Signing and notarizing](docs/macos-targets.md#signing-and-notarizing).

- **Windows x86 is not supported as a host.** The Clang content-package matrix
  supplies Windows x64 and ARM64 hosts. Windows ARM64 is supported as both a
  host and target.

- **Linux ICU dependency.** A cross-compiled binary may need the ICU library on
  the target machine, the same as any globalization-enabled .NET app. See
  [Runtime dependencies on Linux](#runtime-dependencies-on-target-linux-systems)
  below.

## Runtime dependencies on target Linux systems

When running the cross-compiled binaries on Linux, you may hit a missing ICU
library:

```
Process terminated. Couldn't find a valid ICU package installed on the system. Please install libicu (or icu-libs) using your package manager and try again.
```

**Solution 1 (recommended):** install ICU on the target system:

```bash
# Ubuntu/Debian
sudo apt-get install libicu-dev

# CentOS/RHEL/Fedora
sudo yum install libicu-devel   # or: sudo dnf install libicu-devel

# Alpine Linux
sudo apk add icu-libs
```

**Solution 2:** build with invariant globalization (no ICU dependency):

```bash
dotnet publish -r linux-x64 /p:InvariantGlobalization=true
```

Note that invariant globalization disables culture-specific formatting, sorting,
and other globalization features.

## Packing .NET tools for every platform (.NET 11+)

Since .NET 10, a [.NET tool](https://learn.microsoft.com/dotnet/core/tools/global-tools)
can ship native AOT binaries as one small "pointer" package plus one
RID-specific package per platform — `dotnet tool install` downloads just the
binary matching the user's machine. A single `dotnet pack` builds all of them,
but the base SDK only packs the RIDs the host's native toolchain can build
(e.g. a linux-x64 machine packs only linux-x64).

With AotAnywhere referenced, that limit goes away for every RID whose content
packages have been released: `dotnet pack` on one machine produces packages for
the listed RIDs, via the SDK's
tool-packaging extensibility point
([dotnet/sdk#55250](https://github.com/dotnet/sdk/pull/55250)).

```xml
<PropertyGroup>
  <PackAsTool>true</PackAsTool>
  <PublishAot>true</PublishAot>
  <ToolPackageRuntimeIdentifiers>linux-x64;linux-arm64;linux-musl-x64;linux-musl-arm64;linux-musl-arm;osx-x64;osx-arm64</ToolPackageRuntimeIdentifiers>
</PropertyGroup>
```

```bash
dotnet pack   # one host, one command, a package per RID
```

Things to know:

- **Requires a .NET 11 SDK** with the extensibility point; on older SDKs the
  hook is inert and the SDK's own host-capability rules apply.
- Include Windows target RIDs after publishing the MSVC/Windows SDK cross-link
  package, and `linux-arm` after CBake publishes a compatible ARM glibc sysroot.
- Set `AotAnywhereMultiRidToolPackaging=false` to opt out and restore the
  SDK's default host-capability selection.

## Compressing the output with UPX

The published binary can optionally be compressed with
[UPX](https://upx.github.io/) (the same idea as
[PublishAotCompressed](https://github.com/MichalStrehovsky/PublishAotCompressed)),
typically halving its on-disk size. UPX produces a self-extracting executable
that unpacks itself in memory at launch; the startup cost is usually not
observable.

Install UPX on the build machine (from the
[releases page](https://github.com/upx/upx/releases), or
`apt install upx-ucl` / `brew install upx` / `winget install upx`), then:

```bash
dotnet publish -r linux-x64 /p:AotAnywhereUpxCompress=true
```

Knobs:

- `AotAnywhereUpxPath` — path to the UPX executable if it is not on `PATH`.
- `AotAnywhereUpxLzma=true` — LZMA compression: smaller output, slower startup.
- `AotAnywhereUpxArgs` — extra arguments appended to the UPX command line
  (the default is `--best`).

Things to know:

- **Works for Linux and Windows x64/x86 targets.** UPX cannot pack macOS
  binaries (its Mach-O support was removed; macOS 13+ refuses to run packed
  binaries) or win-arm64 (no ARM64 PE support) — publishing those with the
  option set fails with an error rather than producing broken output.
- **Windows antivirus false positives.** UPX-packed executables are a common
  malware wrapper, so some scanners flag them. Weigh that before shipping
  compressed Windows binaries.
- **Executables only** — native libraries (`NativeLib`) cannot be packed.

## Documentation

- [macOS targets](docs/macos-targets.md) — Apple linker stubs, and signing &
  notarizing for distribution
- [Windows targets](docs/windows-targets.md) — how win-x64/win-arm64 cross-linking works
- [Advanced configuration](docs/advanced-configuration.md) — how linking works
  (MSBuild takeovers + managed tasks), and using an external Clang toolchain
- [Cross-platform validation](docs/cross-platform-validation.md) — current CI
  coverage and the Windows cross-link prerequisite

## Credits

AotAnywhere began as a fork of Michal Strehovsky's
[PublishAotCross](https://github.com/MichalStrehovsky/PublishAotCross), which
demonstrated that Native AOT's platform restrictions can be lifted by supplying
the right linker and sysroot. It has since been substantially rewritten: links
run directly through Clang/LLD and managed MSBuild tasks, with bundled Apple
stubs, Linux sysroots, and symbol stripping.

## License

MIT — see [LICENSE.TXT](LICENSE.TXT).
