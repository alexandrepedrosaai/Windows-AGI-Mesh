using System;
using System.Threading.Tasks;

namespace AGUI;

public sealed class AgentHost
{
    private readonly AgentRuntime _runtime;

    public AgentHost(AgentRuntime runtime) => _runtime = runtime;

    public async Task StartAsync(string[] args)
    {
        await _runtime.StartAsync();
        Console.WriteLine("AG-UI Runtime Started");
        Console.WriteLine($"Arguments: {args.Length}");
    }
}
