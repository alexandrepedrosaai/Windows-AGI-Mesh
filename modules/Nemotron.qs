circuit Nemotron {
  version = "0.1"
  kind = dataset

  scope {
    purpose = "Curate and version datasets for evaluating reasoning, adaptation, and task transfer."
    inputs = ["licensed source data", "synthetic examples with recorded generation provenance", "reviewer annotations"]
    outputs = ["versioned dataset manifests", "task and capability labels", "data-quality reports"]
    boundaries = ["Dataset inclusion does not imply model capability or AGI.", "No personal or sensitive data without documented lawful basis and consent."]
  }

  metrics {
    provenance_coverage = { unit: "percent", target: "100% of released records trace to a source or generation record" }
    label_agreement = { unit: "percent", target: ">= 90% on the reviewed annotation sample" }
    contamination_rate = { unit: "percent", target: "<= 1% overlap with benchmark evaluation items" }
    adaptability_tasks = { unit: "count", target: "Report task coverage by version; do not infer capability from count alone." }
  }

  integration_pipeline {
    stage ingest { action = "Accept only approved, licensed sources and record provenance." }
    stage sanitize { action = "Remove or transform disallowed personal data; validate format and content." }
    stage annotate { action = "Attach task labels and independently review a documented sample." }
    stage split { action = "Create reproducible train, validation, and held-out evaluation manifests; check for leakage." }
    stage publish { action = "Version and sign manifests; expose only authorized dataset subsets to consumers." }
  }

  security {
    rules = [
      "Enforce source-license and retention requirements for every dataset version.",
      "Restrict raw data access by role and encrypt it at rest and in transit.",
      "Scan for personal data, secrets, malware, prompt injection, and poisoned examples.",
      "Keep held-out evaluation records access-controlled and log all access.",
      "Support dataset removal and downstream version/dependency notifications."
    ]
  }
}
