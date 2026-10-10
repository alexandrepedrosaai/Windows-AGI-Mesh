circuit MagneticMajorana {
  version = "0.1"
  kind = quantum_persistence_study

  scope {
    purpose = "Study persistence, state representation, and error behavior using quantum-inspired models and optional simulators."
    inputs = ["abstract state definitions", "simulator configurations", "synthetic experiment traces"]
    outputs = ["reproducible simulation results", "state-decay and error summaries", "experiment manifests"]
    boundaries = ["Software studies do not demonstrate Majorana particles or fault-tolerant quantum memory.", "Hardware claims require independently verified experimental evidence."]
  }

  metrics {
    state_retention = { unit: "steps", target: "Report survival distribution against the selected simulator and noise model." }
    logical_error_rate = { unit: "percent", target: "Measure per declared code, noise model, and run count." }
    simulation_reproducibility = { unit: "percent", target: "100% of published runs include simulator and configuration versions." }
    resource_cost = { unit: "time_and_memory", target: "Record runtime and peak memory for every experiment." }
  }

  integration_pipeline {
    stage define { action = "Specify states, observables, assumptions, and a versioned experiment configuration." }
    stage simulate { action = "Run in a bounded local simulator; isolate optional external quantum services." }
    stage analyze { action = "Compute retention and error statistics against declared baselines." }
    stage validate { action = "Repeat seeded runs and compare results with expected simulator behavior." }
    stage publish { action = "Publish manifests and limitations without presenting simulated outcomes as hardware results." }
  }

  security {
    rules = [
      "Accept only signed simulator plugins from an approved source.",
      "Run plugins with resource limits and no network access by default.",
      "Do not transmit experiment data to external quantum services without explicit authorization.",
      "Protect experiment configurations and results with access control and integrity checks.",
      "Label simulated, emulated, and hardware-measured results distinctly."
    ]
  }
}
