using System.Diagnostics;
using System.Text;
using Microsoft.Build.Framework;
using MSBuildTask = Microsoft.Build.Utilities.Task;

namespace AotAnywhere.Tasks;

/// <summary>
/// Links a NativeAOT Windows target from a non-Windows host by invoking
/// lld-link with the MSVC-style arguments emitted by the SDK. The task supplies
/// the MSVC, UCRT, and Windows SDK library paths from AotAnywhere's content
/// package and creates lower-case aliases for Windows SDK import libraries on
/// case-sensitive file systems.
/// </summary>
public sealed class AotAnywhereWindowsLink : MSBuildTask
{
    [Required] public ITaskItem[] MsvcArgs { get; set; } = Array.Empty<ITaskItem>();

    [Required] public string LldLinkExe { get; set; } = "";

    [Required] public string SupportDir { get; set; } = "";

    [Required] public string MsvcPath { get; set; } = "";

    [Required] public string WindowsSdkPath { get; set; } = "";

    [Required] public string TargetArchitecture { get; set; } = "";

    public override bool Execute()
    {
        var machine = ToMachine(TargetArchitecture);
        if (machine == null)
        {
            Log.LogError($"AotAnywhere: unsupported Windows target architecture '{TargetArchitecture}'.");
            return false;
        }

        try
        {
            var msvcLibDir = WindowsCrossLinkLayout.ResolveMsvcLibraryDirectory(MsvcPath, TargetArchitecture);
            if (msvcLibDir == null)
            {
                Log.LogError($"AotAnywhere: no MSVC library directory for '{TargetArchitecture}' under '{MsvcPath}'. Expected '<path>/lib/{{x64,arm64}}' (or x86_64/aarch64), or an xwin --use-winsysroot-style '<path>/VC/Tools/MSVC/<version>/lib/<arch>' tree.");
                return false;
            }

            var sdkLibraries = WindowsCrossLinkLayout.ResolveWindowsSdkLibraries(WindowsSdkPath, TargetArchitecture);
            if (sdkLibraries == null)
            {
                Log.LogError($"AotAnywhere: no Windows SDK UCRT/UM library directories for '{TargetArchitecture}' under '{WindowsSdkPath}'. Expected '<path>/Lib/10.*/{{ucrt,um}}/<arch>' (a lower-case lib or the version-less xwin default also work), or an xwin --use-winsysroot-style '<path>/Windows Kits/10/Lib/...' tree.");
                return false;
            }
            var (ucrtLibDir, umLibDir) = sdkLibraries.Value;

            Directory.CreateDirectory(SupportDir);
            var umAliasDir = CreateCaseInsensitiveAliases(umLibDir);

            var args = WindowsRspTokenizer.Tokenize(MsvcArgs.Select(item => item.ItemSpec));
            if (!args.Any(arg => arg.StartsWith("/MACHINE:", StringComparison.OrdinalIgnoreCase) ||
                                 arg.StartsWith("-MACHINE:", StringComparison.OrdinalIgnoreCase)))
                args.Add("/MACHINE:" + machine);

            // lld does not implement /SOURCELINK (MSVC-only); it would treat
            // the argument as an input file and fail the link. The PDB loses
            // the source-link blob, which no lld version can produce anyway.
            args.RemoveAll(arg => arg.StartsWith("/SOURCELINK:", StringComparison.OrdinalIgnoreCase) ||
                                  arg.StartsWith("-SOURCELINK:", StringComparison.OrdinalIgnoreCase));

            args.Add("/LIBPATH:" + msvcLibDir);
            args.Add("/LIBPATH:" + ucrtLibDir);
            args.Add("/LIBPATH:" + umLibDir);
            if (umAliasDir != null) args.Add("/LIBPATH:" + umAliasDir);

            var responseFile = Path.Combine(SupportDir, "aotanywhere-lld-link.rsp");
            File.WriteAllLines(responseFile, args.Select(QuoteResponseArgument), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

            Log.LogMessage(MessageImportance.Normal, $"AotAnywhere: {LldLinkExe} @{responseFile}");
            return RunLldLink(responseFile);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
        {
            Log.LogError($"AotAnywhere: could not prepare the lld-link invocation: {e.Message}");
            return false;
        }
    }

    string? CreateCaseInsensitiveAliases(string umLibDir)
    {
        var aliasesDir = Path.Combine(SupportDir, "winsdk-um-libs");
        foreach (var source in Directory.EnumerateFiles(umLibDir, "*.lib"))
        {
            var alias = Path.Combine(aliasesDir, Path.GetFileName(source).ToLowerInvariant());
            if (string.Equals(alias, source, StringComparison.Ordinal)) continue;

            Directory.CreateDirectory(aliasesDir);
            if (File.Exists(alias)) continue;
            if (symlink(source, alias) != 0)
                throw new IOException($"Could not create library alias '{alias}' for '{source}' (errno {System.Runtime.InteropServices.Marshal.GetLastWin32Error()}).");
        }

        return Directory.Exists(aliasesDir) ? aliasesDir : null;
    }

    bool RunLldLink(string responseFile)
    {
        var psi = new ProcessStartInfo
        {
            FileName = LldLinkExe,
            Arguments = QuoteResponseArgument("@" + responseFile),
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        try
        {
            using var process = new Process { StartInfo = psi };
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data != null) Log.LogMessage(MessageImportance.Normal, e.Data);
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data != null) Log.LogMessage(MessageImportance.High, e.Data);
            };
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.WaitForExit();
            if (process.ExitCode == 0) return true;

            Log.LogError($"AotAnywhere: lld-link failed with exit code {process.ExitCode}.");
            return false;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            Log.LogError($"AotAnywhere: could not run lld-link ('{LldLinkExe}'): {e.Message}");
            return false;
        }
    }

    static string? ToMachine(string architecture) =>
        architecture switch
        {
            "x86_64" => "X64",
            "aarch64" => "ARM64",
            _ => null,
        };

    static string QuoteResponseArgument(string argument)
    {
        if (argument.Length != 0 && argument.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            return argument;

        var builder = new StringBuilder().Append('"');
        var index = 0;
        while (index < argument.Length)
        {
            var character = argument[index++];
            if (character == '\\')
            {
                var backslashes = 1;
                while (index < argument.Length && argument[index] == '\\')
                {
                    index++;
                    backslashes++;
                }

                if (index == argument.Length) builder.Append('\\', backslashes * 2);
                else if (argument[index] == '"')
                {
                    builder.Append('\\', backslashes * 2 + 1);
                    builder.Append('"');
                    index++;
                }
                else builder.Append('\\', backslashes);
            }
            else if (character == '"') builder.Append("\\\"");
            else builder.Append(character);
        }

        return builder.Append('"').ToString();
    }

    [System.Runtime.InteropServices.DllImport("libc", SetLastError = true)]
    static extern int symlink(string target, string linkPath);
}
