namespace AGIMesh.Benchmarks {
open Microsoft.Quantum.Intrinsic;
 
open Microsoft.Quantum.Math;
open Microsoft.Quantum.Measurement;
open Microsoft.Quantum.Convert;
 
newtype Metric = (
Name : String,
Value : Double,
Weight : Double
);
 
newtype BenchmarkResult = (
Version : String,
AggregateScore : Double,
TaskAccuracy : Double,
TransferRetention : Double,
ToolSafety : Double,
RunReproducibility : Double
);

newtype CapabilityBenchmarkResult = (
Version : String,
CapabilityIndex : Double,
Reasoning : Double,
ToolUsage : Double,
Memory : Double,
SelfCorrection : Double,
AgentCoordination : Double,
QuantumConsensus : Double
);

newtype CapabilityScores = (
Reasoning : Double,
ToolUsage : Double,
Memory : Double,
SelfCorrection : Double,
AgentCoordination : Double,
QuantumConsensus : Double
);

/// Returns a metric value average normalized by total weight, or zero when the total weight is zero.
function WeightedAverage(metrics : Metric[]) : Double {
 
mutable totalWeight = 0.0;
 
for metric in metrics {
 
let (_, _, weight) = metric!;
set totalWeight += weight;
}
 
if totalWeight == 0.0 {
return 0.0;
}
 
mutable weightedAverage = 0.0;

for metric in metrics {

let (_, value, weight) = metric!;

set weightedAverage += value * (weight / totalWeight);
}

return weightedAverage;
}

/// Returns whether a capability score is within the inclusive 0 to 100 range.
function IsValidCapabilityScore(score : Double) : Bool {
return not IsNaN(score) and not IsInfinite(score) and
    score >= 0.0 and score <= 100.0;
}

/// Returns the version identifier for the AGI capability benchmark.
function AGIMeshCapabilityBenchmarkVersion() : String {
return "0.2";
}

/// Returns the number of capability scores and weights required by the ACI.
function CapabilityMetricCount() : Int {
return 6;
}

/// Returns an error message if weights are negative, non-finite, overflow in aggregate, or have no positive total.
function CapabilityWeightValidationError(
weights : Double[]
) : String {

mutable totalWeight = 0.0;

for weight in weights {
if IsNaN(weight) or IsInfinite(weight) or weight < 0.0 {
return "Capability weights must be finite and nonnegative.";
}

set totalWeight += weight;

if IsInfinite(totalWeight) {
return "Total capability weight must be finite.";
}
}

if totalWeight <= 0.0 {
return "At least one capability weight must be greater than zero.";
}

return "";
}

/// Validates a weight array's expected length and values, returning an empty string when valid.
function CapabilityWeightCountValidationError(
weights : Double[],
expectedCount : Int
) : String {

if Length(weights) != expectedCount {
return $"Exactly {expectedCount} weights are required.";
}

return CapabilityWeightValidationError(weights);
}

/// Returns an error message unless trials are positive and successes are between zero and trials.
function TrialCountValidationError(successes : Int, trials : Int) : String {
if trials <= 0 {
return "trials must be greater than zero.";
}

if successes < 0 or successes > trials {
return "successes must be between zero and trials.";
}

return "";
}

/// Returns an error message if a sample or shot count is not positive.
function ShotCountValidationError(name : String, count : Int) : String {
if count <= 0 {
return $"{name} must be greater than zero.";
}

return "";
}

/// Validates named capability scores first, then weights, returning an empty string when valid.
function CapabilityMetricValidationError(metrics : Metric[]) : String {

for metric in metrics {

let (name, value, _) = metric!;

if not IsValidCapabilityScore(value) {
return $"Capability score '{name}' must be finite and between 0 and 100.";
}
}

mutable weights : Double[] = [];

for metric in metrics {

let (_, _, weight) = metric!;
set weights += [weight];
}

return CapabilityWeightValidationError(weights);
}

/// Calculates the normalized ACI for validated metrics and fails when a score or weight is invalid.
function CalculateAGICapabilityIndex(metrics : Metric[]) : Double {

let validationError = CapabilityMetricValidationError(metrics);

if validationError != "" {
fail validationError;
}

return WeightedAverage(metrics);
}

/// Returns the percentage of successful trials. `trials` must be positive and `successes` must be within its range; invalid inputs fail.
function ScoreFromTrials(successes : Int, trials : Int) : Double {

let validationError = TrialCountValidationError(successes, trials);

if validationError != "" {
fail validationError;
}

return 100.0 * IntAsDouble(successes) / IntAsDouble(trials);
}

/// Measures Bell-pair agreement over positive simulator shots and returns a percentage from 0 to 100. MResetZ resets qubits between shots. Invalid shot counts fail; this does not measure agent consensus.
operation RunQuantumConsensusBenchmark(shots : Int) : Double {

let validationError = ShotCountValidationError("shots", shots);

if validationError != "" {
fail validationError;
}

mutable agreements = 0;

use register = Qubit[2];

for _ in 1..shots {

H(register[0]);
CNOT(register[0], register[1]);

let first = MResetZ(register[0]);
let second = MResetZ(register[1]);

if first == second {
set agreements += 1;
}
}

return 100.0 * IntAsDouble(agreements) / IntAsDouble(shots);
}

/// Combines caller-supplied finite capability scores (each 0 to 100) using exactly six finite, nonnegative weights with a positive finite total. The caller supplies the quantum-consensus score; this function does not run the Bell-pair experiment. Invalid inputs fail.
function RunAGICapabilityBenchmark(
scores : CapabilityScores,
weights : Double[]
) : CapabilityBenchmarkResult {

let weightValidationError = CapabilityWeightCountValidationError(
weights,
CapabilityMetricCount()
);

if weightValidationError != "" {
fail weightValidationError;
}

let reasoning = scores::Reasoning;
let toolUsage = scores::ToolUsage;
let memory = scores::Memory;
let selfCorrection = scores::SelfCorrection;
let agentCoordination = scores::AgentCoordination;
let quantumConsensus = scores::QuantumConsensus;

let metrics = [
Metric("reasoning", reasoning, weights[0]),
Metric("tool_usage", toolUsage, weights[1]),
Metric("memory", memory, weights[2]),
Metric("self_correction", selfCorrection, weights[3]),
Metric("agent_coordination", agentCoordination, weights[4]),
Metric("quantum_consensus", quantumConsensus, weights[5])
];

let capabilityIndex = CalculateAGICapabilityIndex(metrics);
let version = AGIMeshCapabilityBenchmarkVersion();

return CapabilityBenchmarkResult(
version,
capabilityIndex,
reasoning,
toolUsage,
memory,
selfCorrection,
agentCoordination,
quantumConsensus
);
}
 
/// Estimates the one-qubit measurement probability over positive samples, returning a value from 0 to 1.
operation QuantumConfidence(samples : Int) : Double {
let validationError = ShotCountValidationError("samples", samples);

if validationError != "" {
fail validationError;
}
 
mutable hits = 0;
 
use q = Qubit();
 
for _ in 1..samples {
 
H(q);
 
if MResetZ(q) == One {
set hits += 1;
}
}
 
return IntAsDouble(hits) / IntAsDouble(samples);
}
 
/// Calculates the baseline AGI Mesh benchmark using its predefined metric values and weights.
operation ExecuteAGIMeshBenchmark() : BenchmarkResult {
 
let taskAccuracy = 88.2;
let transferRetention = 83.7;
let toolSafety = 96.1;
let runReproducibility = 100.0;
 
 
let metrics = [
 
Metric(
"task_accuracy",
taskAccuracy,
0.40
),
 
Metric(
"transfer_retention",
transferRetention,
0.25
),
 
Metric(
"tool_safety",
toolSafety,
0.25
),
 
Metric(
"run_reproducibility",
runReproducibility,
0.10
)
];
 
let aggregate = WeightedAverage(metrics);
 
return BenchmarkResult(
"0.1",
aggregate,
taskAccuracy,
transferRetention,
toolSafety,
runReproducibility
);
}
}
}
