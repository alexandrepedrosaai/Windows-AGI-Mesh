namespace AGIMesh.Tests {

open Microsoft.Quantum.Diagnostics;
open Microsoft.Quantum.Math;
open AGIMesh.Benchmarks;

@Test("QuantumSimulator")
operation TestCapabilityValidation() : Unit {

Fact(
IsValidCapabilityScore(0.0) and
IsValidCapabilityScore(100.0) and
not IsValidCapabilityScore(-0.1) and
not IsValidCapabilityScore(100.1),
"Capability scores must be limited to 0 through 100."
);

Fact(
IsValidCapabilityWeights([1.0, 1.0, 1.0, 1.0, 1.0, 1.0]) and
not IsValidCapabilityWeights([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) and
not IsValidCapabilityWeights([-1.0, 1.0, 1.0, 1.0, 1.0, 1.0]) and
not IsValidCapabilityWeights([1.0]),
"Capability weights must be six nonnegative values with a positive total."
);

Fact(
CapabilityMetricValidationError([Metric("valid", 50.0, 1.0)]) == "" and
CapabilityMetricValidationError([Metric("invalid_score", 100.1, 1.0)]) ==
    "Capability score 'invalid_score' must be between 0 and 100." and
CapabilityMetricValidationError([Metric("invalid_weight", 50.0, -1.0)]) ==
    "Capability weight 'invalid_weight' cannot be negative." and
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
IsValidTrialCount(0, 1) and
IsValidTrialCount(1, 1) and
not IsValidTrialCount(-1, 1) and
not IsValidTrialCount(2, 1) and
not IsValidTrialCount(0, 0),
"Trial counts must be positive and successes must be within the trial count."
);

Fact(
IsValidShotCount(1) and
not IsValidShotCount(0) and
not IsValidShotCount(-1),
"The number of shots must be positive."
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
80.0,
60.0,
100.0,
50.0,
75.0,
100.0,
[1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
);

Fact(
AbsD(benchmark::CapabilityIndex - 77.5) < 1e-9 and
benchmark::Version == AGIMeshCapabilityBenchmarkVersion(),
"The capability index must normalize and apply its weights."
);
}

@Test("QuantumSimulator")
operation TestBellPairCorrelation() : Unit {

let score = RunQuantumConsensusBenchmark(100);

Fact(
score == 100.0,
"Bell-pair measurements must be correlated on every shot."
);
}
}
