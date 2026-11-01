using System.Threading;
using System.Threading.Tasks;

namespace AGUI;

public sealed class AgentRuntime
{
    public bool IsRunning { get; private set; }

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        IsRunning = true;
        return Task.CompletedTask;
    }
}
