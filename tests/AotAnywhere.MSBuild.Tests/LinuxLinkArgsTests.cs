namespace AotAnywhere.MSBuild.Tests;

public class LinuxLinkArgsTests
{
    static string[] Compute(string linkerArgs)
    {
        var result = Harness.Run("_AotAnywhereComputeLinuxLinkArgs", new Dictionary<string, string>
        {
            ["AotAnywhereLinuxSysroot"] = "/opt/sysroot",
            ["AotAnywhereLinuxGccLibraryDirectory"] = "/opt/sysroot/usr/lib/gcc/arm-linux-gnueabihf/7",
            ["NativeObject"] = "/obj/Hello.o",
            ["NativeBinary"] = "/bin/Hello",
            ["ExportsFile"] = "",
            ["TestLinkerArgs"] = linkerArgs,
        });
        if (!result.Success)
            throw new Exception($"_AotAnywhereComputeLinuxLinkArgs failed: {result.ErrorText}");
        return result.Items("_AotAnywhereLinkArg");
    }

    [Test]
    public async Task ReplacesSdkLinkerSelectionWithLld()
    {
        var args = Compute("-fuse-ld=bfd;--target=arm-linux-gnueabihf");

        await Assert.That(args.Any(arg => arg == "-fuse-ld=bfd")).IsFalse();
        await Assert.That(args.Count(arg => arg == "-fuse-ld=lld")).IsEqualTo(1);
        await Assert.That(Array.IndexOf(args, "-fuse-ld=lld"))
            .IsGreaterThan(Array.IndexOf(args, "--target=arm-linux-gnueabihf"));
    }

    [Test]
    public async Task UsesResolvedGccDirectoryForCompilerStartupFiles()
    {
        var args = Compute("--target=arm-linux-musleabihf");

        await Assert.That(args)
            .Contains("-B\"/opt/sysroot/usr/lib/gcc/arm-linux-gnueabihf/7\"");
    }
}
