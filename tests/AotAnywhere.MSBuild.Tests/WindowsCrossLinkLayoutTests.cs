using AotAnywhere.Tasks;

namespace AotAnywhere.MSBuild.Tests;

public class WindowsCrossLinkLayoutTests
{
    [Test]
    public async Task AcceptsExportImportCacheLayout()
    {
        var root = CreateTempDir();
        try
        {
            Create(root, "vctools/lib/x64",
                       "winsdk/Lib/10.0.26100.0/ucrt/x64",
                       "winsdk/Lib/10.0.26100.0/um/x64");

            await AssertSamePath(MsvcLib(Path.Combine(root, "vctools")), Path.Combine(root, "vctools", "lib", "x64"));
            var (ucrt, um) = SdkLibs(Path.Combine(root, "winsdk"));
            await AssertSamePath(ucrt, Path.Combine(root, "winsdk", "Lib", "10.0.26100.0", "ucrt", "x64"));
            await AssertSamePath(um, Path.Combine(root, "winsdk", "Lib", "10.0.26100.0", "um", "x64"));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task AcceptsPlainXwinSplatLayout()
    {
        // `xwin splat --preserve-ms-arch-notation`: lower-case `lib`, no
        // version segment under the SDK, LLVM notation directories.
        var root = CreateTempDir();
        try
        {
            Create(root, "crt/lib/x86_64",
                       "sdk/lib/ucrt/x86_64",
                       "sdk/lib/um/x86_64");

            await AssertSamePath(MsvcLib(Path.Combine(root, "crt")), Path.Combine(root, "crt", "lib", "x86_64"));
            var (ucrt, um) = SdkLibs(Path.Combine(root, "sdk"));
            await AssertSamePath(ucrt, Path.Combine(root, "sdk", "lib", "ucrt", "x86_64"));
            await AssertSamePath(um, Path.Combine(root, "sdk", "lib", "um", "x86_64"));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task AcceptsMixedNotationAcrossRoots()
    {
        // CRT splatted with --preserve-ms-arch-notation, SDK without.
        var root = CreateTempDir();
        try
        {
            Create(root, "crt/lib/x64",
                       "sdk/lib/ucrt/x86_64",
                       "sdk/lib/um/x86_64");

            await AssertSamePath(MsvcLib(Path.Combine(root, "crt")), Path.Combine(root, "crt", "lib", "x64"));
            await AssertSamePath(SdkLibs(Path.Combine(root, "sdk")).Um, Path.Combine(root, "sdk", "lib", "um", "x86_64"));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task AcceptsXwinWinsysrootLayout()
    {
        var root = CreateTempDir();
        try
        {
            Create(root, "VC/Tools/MSVC/14.44.35207/lib/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/ucrt/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/um/x64");

            await AssertSamePath(MsvcLib(Path.Combine(root, "VC", "Tools", "MSVC", "14.44.35207")),
                                 Path.Combine(root, "VC", "Tools", "MSVC", "14.44.35207", "lib", "x64"));
            var (ucrt, um) = SdkLibs(Path.Combine(root, "Windows Kits", "10"));
            await AssertSamePath(ucrt, Path.Combine(root, "Windows Kits", "10", "Lib", "10.0.26100.0", "ucrt", "x64"));
            await AssertSamePath(um, Path.Combine(root, "Windows Kits", "10", "Lib", "10.0.26100.0", "um", "x64"));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task DescendsIntoWinsysrootRoot()
    {
        // Both inputs given the winsysroot root itself.
        var root = CreateTempDir();
        try
        {
            Create(root, "VC/Tools/MSVC/14.44.35207/lib/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/ucrt/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/um/x64");

            await AssertSamePath(MsvcLib(root),
                                 Path.Combine(root, "VC", "Tools", "MSVC", "14.44.35207", "lib", "x64"));
            var (ucrt, um) = SdkLibs(root);
            await AssertSamePath(ucrt, Path.Combine(root, "Windows Kits", "10", "Lib", "10.0.26100.0", "ucrt", "x64"));
            await AssertSamePath(um, Path.Combine(root, "Windows Kits", "10", "Lib", "10.0.26100.0", "um", "x64"));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task HighestVersionDirectoryWins()
    {
        var root = CreateTempDir();
        try
        {
            Create(root, "VC/Tools/MSVC/14.40.1/lib/x64",
                       "VC/Tools/MSVC/14.44.35207/lib/x64",
                       "Windows Kits/10/Lib/10.0.19041.0/ucrt/x64",
                       "Windows Kits/10/Lib/10.0.19041.0/um/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/ucrt/x64",
                       "Windows Kits/10/Lib/10.0.26100.0/um/x64");

            await AssertSamePath(MsvcLib(root),
                                 Path.Combine(root, "VC", "Tools", "MSVC", "14.44.35207", "lib", "x64"));
            var (ucrt, um) = SdkLibs(root);
            await AssertSamePath(ucrt, Path.Combine(root, "Windows Kits", "10", "Lib", "10.0.26100.0", "ucrt", "x64"));
            await AssertSamePath(um, Path.Combine(root, "Windows Kits", "10", "Lib", "10.0.26100.0", "um", "x64"));
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task IncompleteLayoutsReturnNull()
    {
        var root = CreateTempDir();
        try
        {
            // UCRT present, UM missing.
            Create(root, "sdk/lib/ucrt/x86_64");

            await Assert.That(MsvcLib(root)).IsNull();
            await Assert.That(WindowsCrossLinkLayout.ResolveWindowsSdkLibraries(root, "x86_64")).IsNull();
        }
        finally { Delete(root); }
    }

    [Test]
    public async Task MissingTreesReturnNull()
    {
        var root = CreateTempDir();
        try
        {
            await Assert.That(MsvcLib(root)).IsNull();
            await Assert.That(WindowsCrossLinkLayout.ResolveWindowsSdkLibraries(root, "x86_64")).IsNull();
        }
        finally { Delete(root); }
    }

    // The casing the resolver returns depends on which root casing exists on
    // the host file system, so compare case-insensitively.
    static async Task AssertSamePath(string? actual, string expected)
    {
        if (actual == null)
        {
            await Assert.That(actual).IsEqualTo(expected);
            return;
        }

        await Assert.That(string.Equals(
            Path.GetFullPath(actual),
            Path.GetFullPath(expected),
            StringComparison.OrdinalIgnoreCase)).IsTrue().Because($"expected '{expected}' but got '{actual}'");
    }

    static string? MsvcLib(string msvcPath) =>
        WindowsCrossLinkLayout.ResolveMsvcLibraryDirectory(msvcPath, "x86_64");

    static (string Ucrt, string Um) SdkLibs(string windowsSdkPath) =>
        WindowsCrossLinkLayout.ResolveWindowsSdkLibraries(windowsSdkPath, "x86_64")
            ?? throw new InvalidOperationException("no SDK layout matched");

    static string CreateTempDir()
    {
        var root = Path.Combine(Path.GetTempPath(), "aotanywhere-crosslink-tests", Path.GetRandomFileName());
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
