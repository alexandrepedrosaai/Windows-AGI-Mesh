namespace AGIMesh.Tests {

open Microsoft.Quantum.Diagnostics;
open Microsoft.Quantum.Math;
open Microsoft.Quantum.Simulation.XUnit;
open AGIMesh.Benchmarks;

@Test("QuantumSimulator")
operation TestCapabilityValidation() : Unit {

Fact(
IsValidCapabilityScore(0.0) and
IsValidCapabilityScore(100.0) and
not IsValidCapabilityScore(-0.1) and
not IsValidCapabilityScore(100.1) and
not IsValidCapabilityScore(Sqrt(-1.0)) and
not IsValidCapabilityScore(ExpD(1000.0)),
"Capability scores must be finite and limited to 0 through 100."
);

Fact(
CapabilityWeightCountValidationError(
[1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
CapabilityMetricCount()
) == "" and
CapabilityWeightValidationError([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) ==
    "At least one capability weight must be greater than zero." and
CapabilityWeightValidationError([-1.0, 1.0, 1.0, 1.0, 1.0, 1.0]) ==
    "Capability weights must be finite and nonnegative." and
CapabilityWeightValidationError([Sqrt(-1.0)]) ==
    "Capability weights must be finite and nonnegative." and
CapabilityWeightValidationError([ExpD(1000.0)]) ==
    "Capability weights must be finite and nonnegative." and
CapabilityWeightValidationError([1.0e308, 1.0e308]) ==
    "Total capability weight must be finite." and
CapabilityWeightCountValidationError([1.0], CapabilityMetricCount()) ==
    "Exactly 6 weights are required.",
"Capability weight validation must reject invalid weights and lengths."
);

Fact(
CapabilityMetricValidationError([Metric("valid", 50.0, 1.0)]) == "" and
CapabilityMetricValidationError([Metric("invalid_score", 100.1, 1.0)]) ==
    "Capability score 'invalid_score' must be finite and between 0 and 100." and
CapabilityMetricValidationError([Metric("nan_score", Sqrt(-1.0), 1.0)]) ==
    "Capability score 'nan_score' must be finite and between 0 and 100." and
CapabilityMetricValidationError([Metric("invalid_weight", 50.0, -1.0)]) ==
    "Capability weights must be finite and nonnegative." and
CapabilityMetricValidationError([Metric("zero_weight", 50.0, 0.0)]) ==
    "At least one capability weight must be greater than zero." and
CapabilityMetricValidationError([]) ==
    "At least one capability weight must be greater than zero.",
"Capability metric validation must report invalid scores and weights."
);
}

@Test("QuantumSimulator")
operation TestTrialAndShotValidation() : Unit {

Fact(
TrialCountValidationError(0, 1) == "" and
TrialCountValidationError(1, 1) == "" and
TrialCountValidationError(-1, 1) == "successes must be between zero and trials." and
TrialCountValidationError(2, 1) == "successes must be between zero and trials." and
TrialCountValidationError(0, 0) == "trials must be greater than zero.",
"Trial validation must report invalid counts."
);

Fact(
ShotCountValidationError("shots", 1) == "" and
ShotCountValidationError("shots", 0) == "shots must be greater than zero." and
ShotCountValidationError("samples", -1) == "samples must be greater than zero.",
"Shot and sample validation must report nonpositive counts."
);
}

@Test("QuantumSimulator")
operation TestCapabilityScoring() : Unit {

Fact(
AbsD(ScoreFromTrials(7, 10) - 70.0) < 1e-9 and
ScoreFromTrials(0, 10) == 0.0 and
ScoreFromTrials(10, 10) == 100.0,
"Trial scores must report successful trials as percentages."
);
}

@Test("QuantumSimulator")
operation TestWeightedCapabilityIndex() : Unit {

let benchmark = RunAGICapabilityBenchmark(
CapabilityScores(80.0, 60.0, 100.0, 50.0, 75.0, 100.0),
[1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
);

Fact(
AbsD(benchmark::CapabilityIndex - 77.5) < 1e-9 and
benchmark::Version == AGIMeshCapabilityBenchmarkVersion(),
"The capability index must normalize and apply its weights."
);
}

@Test("QuantumSimulator")
operation TestNonUniformCapabilityWeights() : Unit {

let benchmark = RunAGICapabilityBenchmark(
CapabilityScores(80.0, 60.0, 100.0, 50.0, 75.0, 100.0),
[6.0, 5.0, 4.0, 3.0, 2.0, 1.0]
);

Fact(
AbsD(benchmark::CapabilityIndex - 1580.0 / 21.0) < 1e-9,
"Each configured weight must apply to its corresponding capability."
);
}

@Test("QuantumSimulator")
operation TestLargeFiniteWeights() : Unit {

let score = CalculateAGICapabilityIndex([
Metric("high", 100.0, 1.0e308),
Metric("low", 0.0, 1.0e307)
]);

Fact(
not IsNaN(score) and
not IsInfinite(score) and
AbsD(score - 100.0 * (1.0e308 / 1.1e308)) < 1e-9,
"Large finite weights must produce a finite, correctly normalized score."
);
}

@Test("QuantumSimulator")
operation TestBellPairCorrelation() : Unit {

let score = RunQuantumConsensusBenchmark(100);

Fact(
AbsD(score - 100.0) < 1e-9,
"Bell-pair measurements must be correlated on every shot."
);
}

@ExpectedFail("Invalid trial count must fail.")
@Test("QuantumSimulator")
operation TestInvalidTrialCountFails() : Unit {
let _ = ScoreFromTrials(0, 0);
}

@ExpectedFail("Nonpositive shot count must fail.")
@Test("QuantumSimulator")
operation TestInvalidShotCountFails() : Unit {
let _ = RunQuantumConsensusBenchmark(0);
}

@ExpectedFail("Invalid metrics must fail ACI calculation.")
@Test("QuantumSimulator")
operation TestInvalidCapabilityMetricsFail() : Unit {
let _ = CalculateAGICapabilityIndex([Metric("invalid", 101.0, 1.0)]);
}

@ExpectedFail("An out-of-range score must fail at the ACI entry point.")
@Test("QuantumSimulator")
operation TestInvalidCapabilityScoreFails() : Unit {
let _ = RunAGICapabilityBenchmark(
CapabilityScores(101.0, 60.0, 100.0, 50.0, 75.0, 100.0),
[1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
);
}

@ExpectedFail("A malformed weight count must fail at the ACI entry point.")
@Test("QuantumSimulator")
operation TestInvalidCapabilityWeightCountFails() : Unit {
let _ = RunAGICapabilityBenchmark(
CapabilityScores(80.0, 60.0, 100.0, 50.0, 75.0, 100.0),
[1.0]
);
}
}
