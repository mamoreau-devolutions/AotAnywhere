using AotAnywhere.Tasks;

namespace AotAnywhere.MSBuild.Tests;

public class WindowsRspTokenizerTests
{
    [Test]
    public async Task PreservesQuotedResponseFileArguments()
    {
        var tokens = WindowsRspTokenizer.Tokenize(new[]
        {
            "\"obj/native/Hello.obj\"",
            "/NOLOGO /MANIFEST:NO",
            "/NATVIS:\"/path with spaces/NativeAOT.natvis\"",
        });

        await Assert.That(tokens).IsEquivalentTo(new[]
        {
            "obj/native/Hello.obj",
            "/NOLOGO",
            "/MANIFEST:NO",
            "/NATVIS:/path with spaces/NativeAOT.natvis",
        });
    }
}
