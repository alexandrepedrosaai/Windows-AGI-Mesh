circuit EdgeAIApp {
  version = "0.1"
  kind = sovereign_edge_intelligence

  scope {
    purpose = "Run distributed and embedded AI models locally on Windows PCs for user-controlled, sovereign edge intelligence."
    inputs = ["signed local model artifacts", "user-authorized local context", "available CPU, GPU, or NPU resources"]
    outputs = ["local inference responses", "resource and health telemetry", "optional user-approved mesh messages"]
    boundaries = ["Cloud use is optional and disabled by default.", "Model output is not guaranteed to be accurate or safe without application-level validation."]
  }

  metrics {
    local_inference_ratio = { unit: "percent", target: ">= 95% of supported requests complete locally when configured for offline mode." }
    cold_start_time = { unit: "milliseconds", target: "Report median and p95 by model and hardware profile." }
    resource_budget = { unit: "megabytes_and_watts", target: "Measure peak memory and power draw on supported device profiles." }
    offline_availability = { unit: "percent", target: ">= 99% successful requests in the offline functional test suite." }
  }

  integration_pipeline {
    stage provision { action = "Verify model signature, compatibility, license, and user-selected device policy." }
    stage execute { action = "Load the model locally and select supported CPU, GPU, or NPU execution paths." }
    stage protect { action = "Apply input limits, content safety checks, and application-level output validation." }
    stage connect { action = "Exchange only declared, minimized messages with authenticated mesh peers." }
    stage update { action = "Install signed updates with rollback support and disclose any changed data policy." }
  }

  security {
    rules = [
      "Keep prompts, context, embeddings, and model state on-device by default.",
      "Require explicit per-feature consent before any cloud or peer data transfer.",
      "Sandbox model runtimes and plugins with least privilege and resource limits.",
      "Verify model and application signatures before loading; support revocation and rollback.",
      "Protect local data with Windows platform security features and provide user-controlled deletion."
    ]
  }
}
