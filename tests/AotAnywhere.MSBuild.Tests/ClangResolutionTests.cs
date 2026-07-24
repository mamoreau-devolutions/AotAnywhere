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
    public async Task DeferredArmv7SysrootHasActionableError()
    {
        var result = Harness.Run("ResolveLinuxToolchainForTests", new Dictionary<string, string>
        {
            ["RuntimeIdentifier"] = "linux-arm",
            ["HostRuntimeIdentifier"] = "linux-x64",
            ["UseExternalClang"] = "true",
            ["AotAnywhereArmv7SysrootsAvailable"] = "false",
        });

        await Assert.That(result.Success).IsFalse();
        await Assert.That(result.ErrorText).Contains("ARMv7 Linux sysroots are deferred");
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
