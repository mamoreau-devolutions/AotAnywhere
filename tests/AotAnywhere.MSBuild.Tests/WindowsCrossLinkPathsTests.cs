namespace AotAnywhere.MSBuild.Tests;

// Covers SetWindowsCrossLinkPaths deriving the MSVC/Windows SDK roots from
// AotAnywhereWindowsCrossLinkPath for every supported source-tree shape: the
// export/import tools root, a plain xwin splat, and an xwin winsysroot.
public class WindowsCrossLinkPathsTests
{
    [Test]
    public async Task DerivesVctoolsAndWinsdkFromToolsRoot()
    {
        var root = CreateTempDir();
        try
        {
            Create(root, "vctools/lib/x64",
                       "winsdk/Lib/10.0.26100.0/ucrt/x64",
                       "winsdk/Lib/10.0.26100.0/um/x64");

            var result = Run(root);
            await Assert.That(result.Success).IsTrue().Because($"SetWindowsCrossLinkPaths failed: {result.ErrorText}");
            await Assert.That(NormPath(result.Prop("AotAnywhereMsvcPath"))).IsEqualTo(NormPath(Path.Combine(root, "vctools")));
            await Assert.That(NormPath(result.Prop("AotAnywhereWindowsSdkPath"))).IsEqualTo(NormPath(Path.Combine(root, "winsdk")));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task DerivesCrtAndSdkFromPlainXwinSplat()
    {
        var root = CreateTempDir();
        try
        {
            // Lower-case `lib` under the SDK: only passes the Exists checks
            // when both casings are accepted.
            Create(root, "crt/lib/x86_64",
                       "sdk/lib/ucrt/x86_64",
                       "sdk/lib/um/x86_64");

            var result = Run(root);
            await Assert.That(result.Success).IsTrue().Because($"SetWindowsCrossLinkPaths failed: {result.ErrorText}");
            await Assert.That(NormPath(result.Prop("AotAnywhereMsvcPath"))).IsEqualTo(NormPath(Path.Combine(root, "crt")));
            await Assert.That(NormPath(result.Prop("AotAnywhereWindowsSdkPath"))).IsEqualTo(NormPath(Path.Combine(root, "sdk")));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task FallsBackToWinsysrootRootItself()
    {
        var root = CreateTempDir();
        try
        {
            Create(root, "VC/Tools/MSVC/14.44.35207/lib/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/ucrt/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/um/x64");

            var result = Run(root);
            await Assert.That(result.Success).IsTrue().Because($"SetWindowsCrossLinkPaths failed: {result.ErrorText}");
            await Assert.That(NormPath(result.Prop("AotAnywhereMsvcPath"))).IsEqualTo(NormPath(root));
            await Assert.That(NormPath(result.Prop("AotAnywhereWindowsSdkPath"))).IsEqualTo(NormPath(root));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task KeepsExplicitPathsOverDerivedOnes()
    {
        var root = CreateTempDir();
        try
        {
            Create(root, "vctools/lib/x64",
                       "winsdk/Lib/10.0.26100.0/ucrt/x64",
                       "winsdk/Lib/10.0.26100.0/um/x64",
                       "external/lib/x64",
                       "external/Lib/10.0.26100.0/ucrt/x64",
                       "external/Lib/10.0.26100.0/um/x64");

            var result = Harness.Run("SetWindowsCrossLinkPaths", new Dictionary<string, string>
            {
                ["_AotAnywhereWindowsCross"] = "true",
                ["UseExternalClang"] = "true",
                ["AotAnywhereWindowsCrossLinkAvailable"] = "false",
                ["AotAnywhereWindowsCrossLinkPath"] = root,
                ["AotAnywhereMsvcPath"] = Path.Combine(root, "external"),
                ["AotAnywhereWindowsSdkPath"] = Path.Combine(root, "external"),
            });

            await Assert.That(result.Success).IsTrue().Because($"SetWindowsCrossLinkPaths failed: {result.ErrorText}");
            await Assert.That(NormPath(result.Prop("AotAnywhereMsvcPath"))).IsEqualTo(NormPath(Path.Combine(root, "external")));
            await Assert.That(NormPath(result.Prop("AotAnywhereWindowsSdkPath"))).IsEqualTo(NormPath(Path.Combine(root, "external")));
        }
        finally { Delete(root); }
    }

    // The derived paths join segments with '/' (MSBuild), while the
    // expectations come from Path.Combine; compare fully normalized.
    static string NormPath(string path) => Path.GetFullPath(path).ToLowerInvariant();

    static RunResult Run(string crossLinkPath) =>
        Harness.Run("SetWindowsCrossLinkPaths", new Dictionary<string, string>
        {
            ["_AotAnywhereWindowsCross"] = "true",
            ["UseExternalClang"] = "true",
            ["AotAnywhereWindowsCrossLinkAvailable"] = "true",
            ["AotAnywhereWindowsCrossLinkPath"] = crossLinkPath,
        });

    static string CreateTempDir()
    {
        var root = Path.Combine(Path.GetTempPath(), "aotanywhere-crosslink-paths-tests", Path.GetRandomFileName());
        Directory.CreateDirectory(root);
        return root;
    }

    static void Create(string root, params string[] directories)
    {
        foreach (var directory in directories)
        {
            var dir = Path.Combine(root, directory);
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "placeholder.lib"), "");
        }
    }

    static void Delete(string root) => Directory.Delete(root, recursive: true);
}
