using Mzm.VAQLearningNeural;

var agent = new VariationalQuantumQLearner(stateCount: 4, actionCount: 2, seed: 7);
for (var episode = 0; episode < 32; episode++)
{
    var state = episode % 4;
    var action = agent.SelectAction(state);
    var nextState = (state + action + 1) % 4;
    var reward = nextState == 0 ? 1.0 : -0.05;
    agent.Update(state, action, reward, nextState);
}

Console.WriteLine($"VA Q-learning neural polymorphism score: {agent.Score():F4}");

namespace Mzm.VAQLearningNeural;

public interface IQuantumState
{
    double Amplitude(int basis);
    string Family { get; }
}

public sealed record ComputationalState(double[] Amplitudes) : IQuantumState
{
    public string Family => "computational";
    public double Amplitude(int basis) => Amplitudes[basis];
}

public sealed record VariationalState(double[] Parameters) : IQuantumState
{
    public string Family => "variational";
    public double Amplitude(int basis) => Math.Tanh(Parameters[basis % Parameters.Length]);
}

public sealed class VariationalQuantumQLearner
{
    private readonly double[,] q;
    private readonly Random random;
    private readonly double learningRate = 0.2;
    private readonly double discount = 0.85;
    private readonly IQuantumState[] polymorphicStates;

    public VariationalQuantumQLearner(int stateCount, int actionCount, int seed)
    {
        q = new double[stateCount, actionCount];
        random = new Random(seed);
        polymorphicStates =
        [
            new ComputationalState([1, 0, 0, 0]),
            new VariationalState([0.2, -0.4, 0.7, 0.1])
        ];
    }

    public int SelectAction(int state)
    {
        var exploration = random.NextDouble() < 0.15;
        if (exploration) return random.Next(q.GetLength(1));
        return q[state, 0] >= q[state, 1] ? 0 : 1;
    }

    public void Update(int state, int action, double reward, int nextState)
    {
        var next = Math.Max(q[nextState, 0], q[nextState, 1]);
        q[state, action] += learningRate * (reward + discount * next - q[state, action]);
    }

    public double Score()
    {
        var polymorphism = polymorphicStates.Average(s => s.Amplitude(0));
        var value = Enumerable.Range(0, q.GetLength(0)).Sum(s => Math.Max(q[s, 0], q[s, 1]));
        return value + polymorphism;
    }
}
