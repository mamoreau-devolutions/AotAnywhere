using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace AotAnywhere.Tasks;

/// <summary>
/// Resolves the MSVC and Windows SDK import-library directories consumed by
/// <see cref="AotAnywhereWindowsLink"/>. In addition to the documented
/// export/import cache layout it accepts the layouts produced by
/// <c>xwin splat</c> (https://github.com/Jake-Shadle/xwin):
///
/// - default: <c>&lt;out&gt;/crt/lib/&lt;arch&gt;</c> (MSVC) and
///   <c>&lt;out&gt;/sdk/lib/{ucrt,um}/&lt;arch&gt;</c> (SDK, no version
///   segment, lower-case <c>lib</c>)
/// - <c>--use-winsysroot-style</c>: <c>&lt;out&gt;/VC/Tools/MSVC/&lt;crt-version&gt;/lib/&lt;arch&gt;</c>
///   and <c>&lt;out&gt;/Windows Kits/10/Lib/&lt;sdk-version&gt;/{ucrt,um}/&lt;arch&gt;</c>;
///   the winsysroot root itself is also accepted for both inputs and descended
///   into automatically.
///
/// On case-sensitive hosts, both the MSVC notation (<c>x64</c>/<c>arm64</c>,
/// emitted with <c>--preserve-ms-arch-notation</c>) and the LLVM notation
/// (<c>x86_64</c>/<c>aarch64</c>, the xwin default) are accepted.
/// </summary>
public static class WindowsCrossLinkLayout
{
    /// <summary>Directory names for an architecture, MSVC notation first, then the LLVM notation xwin uses by default.</summary>
    public static IEnumerable<string> ArchitectureDirectories(string architecture) =>
        architecture switch
        {
            "x86_64" => new[] { "x64", "x86_64" },
            "aarch64" => new[] { "arm64", "aarch64" },
            _ => new[] { architecture },
        };

    /// <summary>
    /// Finds the MSVC library directory for <paramref name="architecture"/>.
    /// Accepts <c>&lt;msvcPath&gt;/lib/&lt;arch&gt;</c> and, when the input is
    /// an xwin winsysroot, <c>&lt;msvcPath&gt;/VC/Tools/MSVC/&lt;version&gt;/lib/&lt;arch&gt;</c>
    /// (highest version wins). Returns <c>null</c> when no layout matches.
    /// </summary>
    public static string? ResolveMsvcLibraryDirectory(string msvcPath, string architecture)
    {
        var direct = ResolveUnderLib(Path.Combine(msvcPath, "lib"), architecture);
        if (direct != null) return direct;

        var vcTools = Path.Combine(msvcPath, "VC", "Tools", "MSVC");
        if (Directory.Exists(vcTools))
            foreach (var version in VersionsHighestFirst(vcTools, searchPattern: "*"))
            {
                var inVersion = ResolveUnderLib(Path.Combine(version, "lib"), architecture);
                if (inVersion != null) return inVersion;
            }

        return null;
    }

    /// <summary>
    /// Finds the UCRT and UM library directories for <paramref name="architecture"/>
    /// under <paramref name="windowsSdkPath"/>. Supported shapes (first match wins):
    /// <c>&lt;sdk&gt;/Lib/10.*/{ucrt,um}/&lt;arch&gt;</c> (export/import cache and
    /// xwin winsysroot), the same with a lower-case <c>lib</c>, and
    /// <c>&lt;sdk&gt;/lib/{ucrt,um}/&lt;arch&gt;</c> (xwin default, no version
    /// segment). When the input is an xwin winsysroot, the
    /// <c>Windows Kits/10</c> subtree is also consulted. Returns <c>null</c>
    /// when no layout matches.
    /// </summary>
    public static (string Ucrt, string Um)? ResolveWindowsSdkLibraries(string windowsSdkPath, string architecture)
    {
        var sdkRoots = new[]
        {
            Path.Combine(windowsSdkPath, "Lib"),
            Path.Combine(windowsSdkPath, "lib"),
            Path.Combine(windowsSdkPath, "Windows Kits", "10", "Lib"),
            Path.Combine(windowsSdkPath, "Windows Kits", "10", "lib"),
        };

        foreach (var root in sdkRoots)
        {
            if (!Directory.Exists(root)) continue;

            // Prefer the highest 10.* version directory; fall back to the
            // version-less xwin default layout where ucrt/um sit directly
            // under the root.
            var candidates = VersionsHighestFirst(root, searchPattern: "10.*");
            if (candidates.Count == 0) candidates.Add(root);

            foreach (var version in candidates)
            {
                var ucrt = ResolveArchDirectory(Path.Combine(version, "ucrt"), architecture);
                var um = ResolveArchDirectory(Path.Combine(version, "um"), architecture);
                if (ucrt != null && um != null) return (ucrt, um);
            }
        }

        return null;
    }

    static List<string> VersionsHighestFirst(string parent, string searchPattern) =>
        Directory.EnumerateDirectories(parent, searchPattern)
            .OrderByDescending(path => path, System.StringComparer.Ordinal)
            .ToList();

    // The MSVC tree places the architecture directly beneath `lib`; the SDK
    // tree places it beneath `Lib/<version>/ucrt` and `.../um`.
    static string? ResolveUnderLib(string libDir, string architecture)
    {
        if (!Directory.Exists(libDir)) return null;

        foreach (var dir in ArchitectureDirectories(architecture))
        {
            var candidate = Path.Combine(libDir, dir);
            if (Directory.Exists(candidate)) return candidate;
        }

        return null;
    }

    static string? ResolveArchDirectory(string parent, string architecture)
    {
        if (!Directory.Exists(parent)) return null;

        foreach (var dir in ArchitectureDirectories(architecture))
        {
            var candidate = Path.Combine(parent, dir);
            if (Directory.Exists(candidate)) return candidate;
        }

        return null;
    }
}
