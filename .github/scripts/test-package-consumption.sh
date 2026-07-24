#!/usr/bin/env bash
# Prove that the SDK restores the host Clang package and Linux sysroot during a
# clean first restore. The fixture packages are assembled from the immutable
# artifact manifest into the local feed before the consumer is scaffolded.
#
# Cases:
#   sdk        - SDK element restores the toolset and sysroot automatically
#   bare       - PackageReference only fails with an actionable restore message
#   workaround - PackageReference plus both explicit content packages succeeds

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
host_rid="${1:-$(dotnet --info | sed -n 's/^ *RID: *//p' | head -1)}"
target_rid="${2:-linux-x64}"
[ "$host_rid" = "linux-x64" ] || { echo "Package consumption fixture supports linux-x64 only; got $host_rid"; exit 1; }

case "$target_rid" in
  linux-x64)
    sysroot_id="StuDev.AotAnywhere.Linux.Sysroots.ubuntu-18.04-amd64"
    target_framework="net8.0"
    ;;
  linux-musl-arm)
    sysroot_id="StuDev.AotAnywhere.Linux.Sysroots.alpine-3.17-arm"
    target_framework="net9.0"
    ;;
  *)
    echo "Package consumption fixture does not support target RID: $target_rid"
    exit 1
    ;;
esac

work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/aotanywhere-consumption"
rm -rf "$work"
mkdir -p "$work/feed"

version="0.0.1-ci"
toolset_id="StuDev.AotAnywhere.Clang.Toolsets.$host_rid"
toolset_version="$(pwsh -NoProfile -Command "(Get-Content '$repo_root/eng/toolchain-artifacts.json' -Raw | ConvertFrom-Json).clangToolsets | Where-Object packageId -eq '$toolset_id' | Select-Object -ExpandProperty packageVersion")"
sysroot_version="$(pwsh -NoProfile -Command "(Get-Content '$repo_root/eng/toolchain-artifacts.json' -Raw | ConvertFrom-Json).linuxSysroots | Where-Object packageId -eq '$sysroot_id' | Select-Object -ExpandProperty packageVersion")"

echo "==> Preparing immutable Clang and sysroot fixture packages"
pwsh -NoProfile -File "$repo_root/eng/build-toolchain-content.ps1" -PackageId "$toolset_id" -OutputDirectory "$work/feed"
pwsh -NoProfile -File "$repo_root/eng/build-toolchain-content.ps1" -PackageId "$sysroot_id" -OutputDirectory "$work/feed"

echo "==> Packing StuDev.AotAnywhere $version"
dotnet build -t:Pack "$repo_root/src/AotAnywhere.nuproj" -p:Version="$version"
nupkg=$(find "$repo_root/src/bin" -name "StuDev.AotAnywhere.$version.nupkg" | head -1)
[ -n "$nupkg" ] || { echo "packed nupkg not found"; exit 1; }
cp "$nupkg" "$work/feed/"

scaffold() {
  local dir="$1" csproj_body="$2"
  mkdir -p "$dir"
  cat > "$dir/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="$work/feed" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
EOF
  cat > "$dir/Program.cs" <<'EOF'
System.Console.WriteLine($"Hello from {System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier}");
EOF
  cat > "$dir/Consumer.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
$csproj_body
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>$target_framework</TargetFramework>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
</Project>
EOF
}

publish() {
  local dir="$1" log="$2"
  NUGET_PACKAGES="$dir/nuget-cache" dotnet publish "$dir/Consumer.csproj" \
    -r "$target_rid" -c Release -o "$dir/out" 2>&1 | tee "$log"
}

failures=0

echo
echo "==> Case: SDK element (clean restore, zero configuration)"
scaffold "$work/sdk" "  <Sdk Name=\"StuDev.AotAnywhere\" Version=\"$version\" />"
if publish "$work/sdk" "$work/sdk.log" &&
  [ -f "$work/sdk/out/Consumer" ] &&
  grep -q "$toolset_id" "$work/sdk/obj/project.assets.json" &&
  grep -q "$sysroot_id" "$work/sdk/obj/project.assets.json"; then
  echo "sdk: produced Consumer with the restored toolset and sysroot"
else
  echo "sdk: publish failed or the restore graph omitted a required content package"
  failures=$((failures + 1))
fi

echo
echo "==> Case: bare PackageReference (expected actionable failure)"
scaffold "$work/bare" "  <ItemGroup>
    <PackageReference Include=\"StuDev.AotAnywhere\" Version=\"$version\" PrivateAssets=\"all\" />
  </ItemGroup>"
if publish "$work/bare" "$work/bare.log"; then
  echo "bare: expected publish to fail on a clean cache, but it succeeded"
  failures=$((failures + 1))
elif grep -q "AotAnywhere: the Clang toolset" "$work/bare.log"; then
  echo "bare: failed with the actionable AotAnywhere error"
else
  echo "bare: failed without the expected AotAnywhere error"
  failures=$((failures + 1))
fi

echo
echo "==> Case: PackageReference plus explicit content packages"
scaffold "$work/workaround" "  <ItemGroup>
    <PackageReference Include=\"StuDev.AotAnywhere\" Version=\"$version\" PrivateAssets=\"all\" />
    <PackageReference Include=\"$toolset_id\" Version=\"$toolset_version\" PrivateAssets=\"all\" GeneratePathProperty=\"true\" />
    <PackageReference Include=\"$sysroot_id\" Version=\"$sysroot_version\" PrivateAssets=\"all\" GeneratePathProperty=\"true\" />
  </ItemGroup>"
if publish "$work/workaround" "$work/workaround.log" && [ -f "$work/workaround/out/Consumer" ]; then
  echo "workaround: produced Consumer"
else
  echo "workaround: publish failed or produced no binary"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures package-consumption case(s) failed"
  exit 1
fi
