circuit LocalEdgeDeployment {
  version = "0.1"
  kind = local_edge_deployment

  scope {
    purpose = "Demonstrate a local-only edge inference deployment on one Windows PC."
    inputs = ["signature-verified model package", "user-approved local inputs"]
    outputs = ["local inference responses", "resource usage report"]
    boundaries = ["Peer and cloud routing are disabled.", "Inputs and outputs are not retained by default.", "Consequential actions require operator approval."]
  }

  deployment {
    host = "Windows PC"
    enabled_modules = ["EdgeAIApp", "Nemotron"]
    inference_route = "local only"
    network_access = "disabled unless explicitly authorized per task"
    workload_isolation = "required"
    model_source = "operator-approved, signature-verified package"
  }

  policy {
    user_data = "process locally; do not retain inputs or outputs by default"
    telemetry = "disabled unless separately opted in"
    external_routes = "deny by default"
    consequential_actions = "require explicit operator approval"
  }

  integration_pipeline {
    stage verify { action = "Verify the model package signature and operator approval." }
    stage isolate { action = "Start the model in an isolated workload with local-only network policy." }
    stage infer { action = "Process user-approved input locally and validate the response." }
    stage cleanup { action = "Report resource use and remove transient task data when the task ends." }
  }

  metrics {
    inference_latency = { unit: "milliseconds", target: "measure on deployment hardware" }
    peak_memory = { unit: "megabytes", target: "measure for selected model" }
    external_data_transfer = { unit: "bytes", target: "expect zero for local-only tasks; verify" }
  }

  security {
    rules = [
      "Verify package signatures before installation.",
      "Grant only the file and device access required for a user-approved task.",
      "Do not store credentials in this example configuration.",
      "Expose execution state and allow the operator to stop the workload."
    ]
  }
}
