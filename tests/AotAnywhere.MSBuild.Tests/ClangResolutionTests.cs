namespace AotAnywhere.MSBuild.Tests;

public class ClangResolutionTests
{
    [Test]
    public async Task ExternalClangPathSuppliesAllDriverPaths()
    {
        var root = Path.Combine(Path.GetTempPath(), "aotanywhere-clang-" + Guid.NewGuid());
        try
        {
            Directory.CreateDirectory(Path.Combine(root, "bin"));

            var result = Harness.Run("SetPathToClang", new Dictionary<string, string>
            {
                ["UseExternalClang"] = "true",
                ["AotAnywhereClangPath"] = root,
                ["HostRuntimeIdentifier"] = "linux-x64",
            });

            await Assert.That(result.Success)
                .IsTrue().Because($"SetPathToClang failed: {result.ErrorText}");
            var executableSuffix = OperatingSystem.IsWindows() ? ".exe" : "";
            await Assert.That(result.Prop("AotAnywhereClangExe"))
                .IsEqualTo(root + "/bin/clang" + executableSuffix);
            await Assert.That(result.Prop("AotAnywhereLldLinkExe"))
                .IsEqualTo(root + "/bin/lld-link" + executableSuffix);
            await Assert.That(result.Prop("AotAnywhereLd64LldExe"))
                .IsEqualTo(root + "/bin/ld64.lld" + executableSuffix);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Test]
    public async Task LinuxSysrootFindsTheGccSupportLibrary()
    {
        var root = Path.Combine(Path.GetTempPath(), "aotanywhere-sysroot-" + Guid.NewGuid());
        var gccLibrary = Path.Combine(root, "usr", "lib", "gcc", "x86_64-linux-gnu", "13.2.0");
        try
        {
            Directory.CreateDirectory(gccLibrary);

            var result = Harness.Run("ResolveLinuxToolchainForTests", new Dictionary<string, string>
            {
                ["RuntimeIdentifier"] = "linux-x64",
                ["HostRuntimeIdentifier"] = "linux-x64",
                ["UseExternalClang"] = "true",
                ["AotAnywhereLinuxSysroot"] = root,
            });

            await Assert.That(result.Success)
                .IsTrue().Because($"SetLinuxSysroot failed: {result.ErrorText}");
            await Assert.That(result.Prop("AotAnywhereLinuxGccLibraryDirectory"))
                .IsEqualTo(gccLibrary);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Test]
    public async Task LinuxMuslArmSysrootUsesCbakeGccTargetLayout()
    {
        var root = Path.Combine(Path.GetTempPath(), "aotanywhere-musl-arm-sysroot-" + Guid.NewGuid());
        var gccLibrary = Path.Combine(root, "usr", "lib", "gcc", "armv7-alpine-linux-musleabihf", "13.2.0");
        try
        {
            Directory.CreateDirectory(gccLibrary);

            var result = Harness.Run("ResolveLinuxToolchainForTests", new Dictionary<string, string>
            {
                ["RuntimeIdentifier"] = "linux-musl-arm",
                ["HostRuntimeIdentifier"] = "linux-x64",
                ["UseExternalClang"] = "true",
                ["AotAnywhereLinuxSysroot"] = root,
            });

            await Assert.That(result.Success)
                .IsTrue().Because($"SetLinuxSysroot failed: {result.ErrorText}");
            await Assert.That(result.Prop("AotAnywhereLinuxSysrootId"))
                .IsEqualTo("alpine-3.17-arm");
            await Assert.That(result.Prop("AotAnywhereLinuxGccTarget"))
                .IsEqualTo("armv7-alpine-linux-musleabihf");
            await Assert.That(result.Prop("AotAnywhereLinuxGccLibraryDirectory"))
                .IsEqualTo(gccLibrary);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Test]
    [Arguments("linux-musl-x64", "x86_64-alpine-linux-musl")]
    [Arguments("linux-musl-arm64", "aarch64-alpine-linux-musl")]
    public async Task LinuxMuslSysrootsUseCbakeGccTargetLayouts(string runtimeIdentifier, string gccTarget)
    {
        var root = Path.Combine(Path.GetTempPath(), "aotanywhere-musl-sysroot-" + Guid.NewGuid());
        var gccLibrary = Path.Combine(root, "usr", "lib", "gcc", gccTarget, "13.2.0");
        try
        {
            Directory.CreateDirectory(gccLibrary);

            var result = Harness.Run("ResolveLinuxToolchainForTests", new Dictionary<string, string>
            {
                ["RuntimeIdentifier"] = runtimeIdentifier,
                ["HostRuntimeIdentifier"] = "linux-x64",
                ["UseExternalClang"] = "true",
                ["AotAnywhereLinuxSysroot"] = root,
            });

            await Assert.That(result.Success)
                .IsTrue().Because($"SetLinuxSysroot failed: {result.ErrorText}");
            await Assert.That(result.Prop("AotAnywhereLinuxGccTarget"))
                .IsEqualTo(gccTarget);
            await Assert.That(result.Prop("AotAnywhereLinuxGccLibraryDirectory"))
                .IsEqualTo(gccLibrary);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Test]
    public async Task PublishedMuslArmSysrootResolvesFromTheNuGetPackageProperty()
    {
        var root = Path.Combine(Path.GetTempPath(), "aotanywhere-musl-arm-sysroot-" + Guid.NewGuid());
        var toolset = Path.Combine(root, "clang-toolset");
        var sysrootPackage = Path.Combine(root, "sysroot-package");
        var gccLibrary = Path.Combine(
            sysrootPackage,
            "tools",
            "sysroot",
            "usr",
            "lib",
            "gcc",
            "armv7-alpine-linux-musleabihf",
            "14.2.0");
        try
        {
            Directory.CreateDirectory(Path.Combine(toolset, "tools"));
            Directory.CreateDirectory(gccLibrary);

            var result = Harness.Run("ResolveLinuxToolchainForTests", new Dictionary<string, string>
            {
                ["RuntimeIdentifier"] = "linux-musl-arm",
                ["HostRuntimeIdentifier"] = "linux-x64",
                ["PkgStuDev_AotAnywhere_Clang_Toolsets_linux-x64"] = toolset,
                ["PkgStuDev_AotAnywhere_Linux_Sysroots_alpine-3_17-arm"] = sysrootPackage,
            });

            await Assert.That(result.Success)
                .IsTrue().Because($"SetLinuxSysroot failed: {result.ErrorText}");
            await Assert.That(result.Prop("AotAnywhereLinuxMuslArmSysrootAvailable"))
                .IsEqualTo("true");
            await Assert.That(Path.GetFullPath(result.Prop("AotAnywhereLinuxGccLibraryDirectory")))
                .IsEqualTo(Path.GetFullPath(gccLibrary));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Test]
    public async Task MissingRestoredToolsetHasActionableError()
    {
        var result = Harness.Run("SetPathToClang", new Dictionary<string, string>
        {
            ["HostRuntimeIdentifier"] = "linux-x64",
            ["UseExternalClang"] = "false",
            ["NuGetPackageRoot"] = Path.Combine(Path.GetTempPath(), "aotanywhere-empty-" + Guid.NewGuid()),
        });

        await Assert.That(result.Success).IsFalse();
        await Assert.That(result.ErrorText).Contains("the Clang toolset");
        await Assert.That(result.ErrorText).Contains("UseExternalClang=true");
    }

    [Test]
    public async Task IncompatibleArmGlibcSysrootHasActionableError()
    {
        var result = Harness.Run("ResolveLinuxToolchainForTests", new Dictionary<string, string>
        {
            ["RuntimeIdentifier"] = "linux-arm",
            ["HostRuntimeIdentifier"] = "linux-x64",
            ["UseExternalClang"] = "true",
        });

        await Assert.That(result.Success).IsFalse();
        await Assert.That(result.ErrorText).Contains("linux-arm requires an ARM glibc sysroot");
        await Assert.That(result.ErrorText).Contains("AotAnywhereLinuxSysroot");
    }

    [Test]
    public async Task DeferredWindowsCrossLinkHasActionableError()
    {
        var result = Harness.Run("SetWindowsCrossLinkPaths", new Dictionary<string, string>
        {
            ["_AotAnywhereWindowsCross"] = "true",
            ["UseExternalClang"] = "true",
            ["AotAnywhereWindowsCrossLinkAvailable"] = "false",
        });

        await Assert.That(result.Success).IsFalse();
        await Assert.That(result.ErrorText).Contains("Windows-target links are deferred");
        await Assert.That(result.ErrorText).Contains("AotAnywhereMsvcPath");
    }
}
