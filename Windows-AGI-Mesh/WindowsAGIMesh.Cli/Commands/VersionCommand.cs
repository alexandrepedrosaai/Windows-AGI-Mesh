using System.Reflection;

namespace WindowsAGIMesh.Cli;

/// <summary>
/// Handles the <c>agimesh version</c> command.
/// Prints the current assembly version and runtime information.
/// </summary>
public static class VersionCommand
{
    public static Task<int> RunAsync(string[] args)
    {
        Assembly asm     = Assembly.GetExecutingAssembly();
        string   version = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()
                              ?.InformationalVersion
                           ?? asm.GetName().Version?.ToString()
                           ?? "unknown";

        string runtime   = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription;
        string os        = System.Runtime.InteropServices.RuntimeInformation.OSDescription;
        string arch      = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString();

        Console.WriteLine("Windows AGI Mesh CLI");
        Console.WriteLine($"  Version   : {version}");
        Console.WriteLine($"  Runtime   : {runtime}");
        Console.WriteLine($"  OS        : {os}");
        Console.WriteLine($"  Arch      : {arch}");

        return Task.FromResult(0);
    }
}
