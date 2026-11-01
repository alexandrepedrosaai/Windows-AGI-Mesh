using System;
using System.Threading.Tasks;

namespace AGUI;

internal static class Program
{
    public static async Task Main(string[] args)
    {
        var runtime = new AgentRuntime();
        var host = new AgentHost(runtime);
        await host.StartAsync(args);
    }
}
