# =============================================================================
# Windows AGI Benchmark Lab — Azure ML Pipeline
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
Azure ML Pipeline for cloud-scale benchmark execution.

Deploys and runs benchmark jobs on Azure ML compute clusters:
  - GPU clusters (NVIDIA A100, H100, V100)
  - CPU clusters (Standard_D series)
  - Multi-node distributed benchmarks
  - Automated result collection and storage
  - Integration with Azure Monitor and Application Insights
  - Microsoft 365 Teams notifications
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import os
import pathlib
import sys
import time
from dataclasses import asdict, dataclass
from typing import Any

log = logging.getLogger("agi.azure.ml")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
RESOURCE_GROUP = os.environ.get("AZURE_RESOURCE_GROUP", "rg-agi-bench-dev")
WORKSPACE_NAME = os.environ.get("AZURE_ML_WORKSPACE", "mlw-agi-bench-dev")
STORAGE_ACCOUNT = os.environ.get("BENCHMARK_STORAGE_ACCOUNT", "stagibenchdev")
STORAGE_CONTAINER = os.environ.get("BENCHMARK_CONTAINER", "benchmark-results")
TENANT_ID = os.environ.get("AZURE_TENANT_ID", "")
CLIENT_ID = os.environ.get("AZURE_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("AZURE_CLIENT_SECRET", "")
TEAMS_WEBHOOK = os.environ.get("TEAMS_WEBHOOK_URL", "")

# Compute cluster configurations
COMPUTE_CONFIGS = {
    "cpu-small": {
        "vm_size": "Standard_D4s_v3",
        "min_instances": 0,
        "max_instances": 4,
        "description": "CPU benchmark cluster (4 vCPUs)",
    },
    "cpu-large": {
        "vm_size": "Standard_D32s_v3",
        "min_instances": 0,
        "max_instances": 2,
        "description": "CPU benchmark cluster (32 vCPUs)",
    },
    "gpu-v100": {
        "vm_size": "Standard_NC6s_v3",
        "min_instances": 0,
        "max_instances": 2,
        "description": "NVIDIA V100 GPU cluster",
    },
    "gpu-a100": {
        "vm_size": "Standard_ND40rs_v2",
        "min_instances": 0,
        "max_instances": 1,
        "description": "NVIDIA A100 GPU cluster",
    },
}

# Environment configurations
ENVIRONMENTS = {
    "benchmark-cpu": {
        "image": "mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04:latest",
        "conda_file": "azure/environments/benchmark_cpu.yml",
        "description": "CPU benchmark environment",
    },
    "benchmark-gpu-cuda": {
        "image": "mcr.microsoft.com/azureml/pytorch-2.0-cuda11.7-cudnn8-py38:latest",
        "conda_file": "azure/environments/benchmark_gpu_cuda.yml",
        "description": "NVIDIA CUDA GPU benchmark environment",
    },
    "benchmark-gpu-rocm": {
        "image": "rocm/pytorch:latest",
        "conda_file": "azure/environments/benchmark_gpu_rocm.yml",
        "description": "AMD ROCm GPU benchmark environment",
    },
}


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------
@dataclass
class AzureMLJob:
    """Azure ML job configuration."""

    job_name: str
    display_name: str
    description: str
    compute_target: str
    environment: str
    command: str
    inputs: dict[str, Any]
    outputs: dict[str, Any]
    tags: dict[str, str]
    experiment_name: str
    status: str = "pending"
    job_id: str = ""
    run_url: str = ""
    started_at: str = ""
    completed_at: str = ""
    duration_sec: float = 0.0
    error_message: str = ""


@dataclass
class BenchmarkPipelineConfig:
    """Configuration for a benchmark pipeline run."""

    pipeline_name: str
    suites: list[str]
    compute_targets: list[str]
    models: list[str]
    export_formats: list[str]
    generate_charts: bool
    generate_report: bool
    notify_teams: bool
    storage_account: str
    storage_container: str
    tags: dict[str, str]


# ---------------------------------------------------------------------------
# Azure ML Client
# ---------------------------------------------------------------------------
class AzureMLClient:
    """Azure ML workspace client."""

    def __init__(
        self,
        subscription_id: str,
        resource_group: str,
        workspace_name: str,
    ) -> None:
        self.subscription_id = subscription_id
        self.resource_group = resource_group
        self.workspace_name = workspace_name
        self._ml_client = None
        self._credential = None

    def _get_credential(self) -> Any:
        """Get Azure credential."""
        if self._credential:
            return self._credential

        try:
            from azure.identity import (  # type: ignore[import]
                ClientSecretCredential,
                DefaultAzureCredential,
                ManagedIdentityCredential,
            )

            if CLIENT_ID and CLIENT_SECRET and TENANT_ID:
                log.info("Using ClientSecretCredential")
                self._credential = ClientSecretCredential(
                    tenant_id=TENANT_ID,
                    client_id=CLIENT_ID,
                    client_secret=CLIENT_SECRET,
                )
            elif os.environ.get("MSI_ENDPOINT"):
                log.info("Using ManagedIdentityCredential")
                self._credential = ManagedIdentityCredential()
            else:
                log.info("Using DefaultAzureCredential")
                self._credential = DefaultAzureCredential()

        except ImportError:
            log.error("azure-identity not installed. Run: pip install azure-identity")
            raise

        return self._credential

    def _get_ml_client(self) -> Any:
        """Get Azure ML client."""
        if self._ml_client:
            return self._ml_client

        try:
            from azure.ai.ml import MLClient  # type: ignore[import]

            credential = self._get_credential()
            self._ml_client = MLClient(
                credential=credential,
                subscription_id=self.subscription_id,
                resource_group_name=self.resource_group,
                workspace_name=self.workspace_name,
            )
            log.info("Azure ML client initialized: %s/%s", self.resource_group, self.workspace_name)

        except ImportError:
            log.error("azure-ai-ml not installed. Run: pip install azure-ai-ml")
            raise

        return self._ml_client

    def create_compute_cluster(self, cluster_name: str, config: dict[str, Any]) -> bool:
        """Create or update a compute cluster."""
        try:
            from azure.ai.ml.entities import AmlCompute  # type: ignore[import]

            ml_client = self._get_ml_client()

            compute = AmlCompute(
                name=cluster_name,
                type="amlcompute",
                size=config["vm_size"],
                min_instances=config["min_instances"],
                max_instances=config["max_instances"],
                idle_time_before_scale_down=120,
                tags={
                    "Project": "Windows-AGI-Benchmark",
                    "Vendor": "Microsoft Corporation",
                },
            )

            ml_client.compute.begin_create_or_update(compute).result()
            log.info("Compute cluster created: %s (%s)", cluster_name, config["vm_size"])
            return True

        except Exception as exc:
            log.error("Failed to create compute cluster %s: %s", cluster_name, exc)
            return False

    def create_environment(self, env_name: str, config: dict[str, Any]) -> bool:
        """Create or update an ML environment."""
        try:
            from azure.ai.ml.entities import Environment  # type: ignore[import]

            ml_client = self._get_ml_client()

            env = Environment(
                name=env_name,
                description=config["description"],
                image=config["image"],
                tags={
                    "Project": "Windows-AGI-Benchmark",
                    "Vendor": "Microsoft Corporation",
                },
            )

            ml_client.environments.create_or_update(env)
            log.info("Environment created: %s", env_name)
            return True

        except Exception as exc:
            log.error("Failed to create environment %s: %s", env_name, exc)
            return False

    def submit_job(self, job_config: AzureMLJob) -> str:
        """Submit a benchmark job to Azure ML."""
        try:
            from azure.ai.ml import command  # type: ignore[import]
            from azure.ai.ml.entities import JobInput, JobOutput  # type: ignore[import]

            ml_client = self._get_ml_client()

            job = command(
                name=job_config.job_name,
                display_name=job_config.display_name,
                description=job_config.description,
                experiment_name=job_config.experiment_name,
                compute=job_config.compute_target,
                environment=job_config.environment,
                command=job_config.command,
                tags=job_config.tags,
            )

            submitted_job = ml_client.jobs.create_or_update(job)
            job_id = submitted_job.name
            run_url = submitted_job.studio_url or ""

            log.info("Job submitted: %s", job_id)
            log.info("Studio URL: %s", run_url)

            return job_id

        except Exception as exc:
            log.error("Failed to submit job %s: %s", job_config.job_name, exc)
            return ""

    def wait_for_job(self, job_id: str, timeout_sec: int = 3600) -> str:
        """Wait for a job to complete."""
        ml_client = self._get_ml_client()
        t_start = time.time()

        while time.time() - t_start < timeout_sec:
            try:
                job = ml_client.jobs.get(job_id)
                status = job.status

                log.info("Job %s status: %s", job_id, status)

                if status in ("Completed", "Failed", "Canceled"):
                    return status

                time.sleep(30)

            except Exception as exc:
                log.error("Error checking job status: %s", exc)
                time.sleep(30)

        log.warning("Job %s timed out after %ds", job_id, timeout_sec)
        return "Timeout"

    def download_outputs(self, job_id: str, output_dir: pathlib.Path) -> bool:
        """Download job outputs."""
        try:
            ml_client = self._get_ml_client()
            output_dir.mkdir(parents=True, exist_ok=True)
            ml_client.jobs.download(name=job_id, download_path=str(output_dir))
            log.info("Outputs downloaded to: %s", output_dir)
            return True
        except Exception as exc:
            log.error("Failed to download outputs: %s", exc)
            return False

    def list_jobs(self, experiment_name: str) -> list[dict[str, Any]]:
        """List jobs in an experiment."""
        try:
            ml_client = self._get_ml_client()
            jobs = ml_client.jobs.list(parent_job_name=None)
            return [
                {
                    "name": j.name,
                    "status": j.status,
                    "display_name": j.display_name,
                    "created": str(j.creation_context.created_at) if j.creation_context else "",
                }
                for j in jobs
                if hasattr(j, "experiment_name") and j.experiment_name == experiment_name
            ]
        except Exception as exc:
            log.error("Failed to list jobs: %s", exc)
            return []


# ---------------------------------------------------------------------------
# Azure Storage Client
# ---------------------------------------------------------------------------
class AzureStorageClient:
    """Azure Blob Storage client for benchmark artifacts."""

    def __init__(self, account_name: str, container_name: str) -> None:
        self.account_name = account_name
        self.container_name = container_name
        self._client = None

    def _get_client(self) -> Any:
        """Get blob service client."""
        if self._client:
            return self._client

        try:
            from azure.storage.blob import BlobServiceClient  # type: ignore[import]
            from azure.identity import DefaultAzureCredential  # type: ignore[import]

            account_url = f"https://{self.account_name}.blob.core.windows.net"
            credential = DefaultAzureCredential()
            self._client = BlobServiceClient(account_url=account_url, credential=credential)

        except ImportError:
            log.error("azure-storage-blob not installed. Run: pip install azure-storage-blob")
            raise

        return self._client

    def upload_file(self, local_path: pathlib.Path, blob_name: str) -> bool:
        """Upload a file to Azure Blob Storage."""
        try:
            client = self._get_client()
            container_client = client.get_container_client(self.container_name)

            with open(local_path, "rb") as f:
                container_client.upload_blob(
                    name=blob_name,
                    data=f,
                    overwrite=True,
                    metadata={
                        "project": "Windows-AGI-Benchmark",
                        "vendor": "Microsoft Corporation",
                        "uploaded_at": datetime.datetime.utcnow().isoformat(),
                    },
                )

            log.info("Uploaded: %s → %s/%s", local_path, self.container_name, blob_name)
            return True

        except Exception as exc:
            log.error("Upload failed: %s", exc)
            return False

    def upload_directory(self, local_dir: pathlib.Path, prefix: str = "") -> int:
        """Upload all files in a directory."""
        uploaded = 0
        for file_path in local_dir.rglob("*"):
            if file_path.is_file():
                relative = file_path.relative_to(local_dir)
                blob_name = f"{prefix}/{relative}" if prefix else str(relative)
                if self.upload_file(file_path, blob_name):
                    uploaded += 1
        log.info("Uploaded %d files to %s/%s", uploaded, self.container_name, prefix)
        return uploaded

    def download_file(self, blob_name: str, local_path: pathlib.Path) -> bool:
        """Download a file from Azure Blob Storage."""
        try:
            client = self._get_client()
            blob_client = client.get_blob_client(
                container=self.container_name, blob=blob_name
            )
            local_path.parent.mkdir(parents=True, exist_ok=True)
            with open(local_path, "wb") as f:
                data = blob_client.download_blob()
                data.readinto(f)
            log.info("Downloaded: %s/%s → %s", self.container_name, blob_name, local_path)
            return True
        except Exception as exc:
            log.error("Download failed: %s", exc)
            return False

    def list_blobs(self, prefix: str = "") -> list[str]:
        """List blobs in container."""
        try:
            client = self._get_client()
            container_client = client.get_container_client(self.container_name)
            return [b.name for b in container_client.list_blobs(name_starts_with=prefix)]
        except Exception as exc:
            log.error("List blobs failed: %s", exc)
            return []


# ---------------------------------------------------------------------------
# Teams Notifier
# ---------------------------------------------------------------------------
class TeamsNotifier:
    """Microsoft Teams webhook notifier."""

    def __init__(self, webhook_url: str) -> None:
        self.webhook_url = webhook_url

    def send_benchmark_start(self, pipeline_name: str, suites: list[str]) -> bool:
        """Send benchmark start notification."""
        return self._send({
            "@type": "MessageCard",
            "@context": "http://schema.org/extensions",
            "themeColor": "0078D4",
            "summary": f"Benchmark Started: {pipeline_name}",
            "sections": [{
                "activityTitle": f"🚀 Benchmark Started: {pipeline_name}",
                "activitySubtitle": "Windows AGI Benchmark Lab — Microsoft Corporation",
                "facts": [
                    {"name": "Suites", "value": ", ".join(suites)},
                    {"name": "Started", "value": datetime.datetime.utcnow().isoformat()},
                    {"name": "Environment", "value": "Azure ML"},
                ],
            }],
        })

    def send_benchmark_complete(
        self,
        pipeline_name: str,
        duration_sec: float,
        results_url: str,
        success: bool,
    ) -> bool:
        """Send benchmark completion notification."""
        color = "107C10" if success else "D13438"
        status = "✅ Completed" if success else "❌ Failed"

        return self._send({
            "@type": "MessageCard",
            "@context": "http://schema.org/extensions",
            "themeColor": color,
            "summary": f"Benchmark {status}: {pipeline_name}",
            "sections": [{
                "activityTitle": f"{status}: {pipeline_name}",
                "activitySubtitle": "Windows AGI Benchmark Lab — Microsoft Corporation",
                "facts": [
                    {"name": "Duration", "value": f"{duration_sec:.1f}s"},
                    {"name": "Completed", "value": datetime.datetime.utcnow().isoformat()},
                    {"name": "Results", "value": results_url},
                ],
            }],
            "potentialAction": [{
                "@type": "OpenUri",
                "name": "View Results",
                "targets": [{"os": "default", "uri": results_url}],
            }] if results_url else [],
        })

    def _send(self, payload: dict[str, Any]) -> bool:
        """Send Teams webhook message."""
        if not self.webhook_url:
            log.debug("Teams webhook not configured — skipping notification")
            return False

        try:
            import requests  # type: ignore[import]
            response = requests.post(
                self.webhook_url,
                json=payload,
                timeout=10,
            )
            response.raise_for_status()
            log.info("Teams notification sent")
            return True
        except Exception as exc:
            log.warning("Teams notification failed: %s", exc)
            return False


# ---------------------------------------------------------------------------
# Pipeline Orchestrator
# ---------------------------------------------------------------------------
class BenchmarkPipeline:
    """Azure ML benchmark pipeline orchestrator."""

    def __init__(self, config: BenchmarkPipelineConfig) -> None:
        self.config = config
        self.ml_client = AzureMLClient(
            subscription_id=SUBSCRIPTION_ID,
            resource_group=RESOURCE_GROUP,
            workspace_name=WORKSPACE_NAME,
        )
        self.storage_client = AzureStorageClient(
            account_name=config.storage_account,
            container_name=config.storage_container,
        )
        self.teams = TeamsNotifier(TEAMS_WEBHOOK)
        self.jobs: list[AzureMLJob] = []

    def setup_infrastructure(self) -> bool:
        """Create compute clusters and environments."""
        log.info("Setting up Azure ML infrastructure...")

        # Create compute clusters
        for cluster_name, cluster_config in COMPUTE_CONFIGS.items():
            self.ml_client.create_compute_cluster(cluster_name, cluster_config)

        # Create environments
        for env_name, env_config in ENVIRONMENTS.items():
            self.ml_client.create_environment(env_name, env_config)

        log.info("Infrastructure setup complete")
        return True

    def build_jobs(self) -> list[AzureMLJob]:
        """Build job configurations for each suite."""
        jobs: list[AzureMLJob] = []
        timestamp = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")

        for suite in self.config.suites:
            for compute_target in self.config.compute_targets:
                # Determine environment based on compute target
                if "gpu" in compute_target:
                    environment = "benchmark-gpu-cuda:latest"
                else:
                    environment = "benchmark-cpu:latest"

                # Build command
                models_arg = " ".join(self.config.models)
                export_arg = " ".join(self.config.export_formats)
                command = (
                    f"python benchmark/runner.py "
                    f"--suite {suite} "
                    f"--models {models_arg} "
                    f"--export {export_arg} "
                    f"--report-dir ${{outputs.reports}} "
                    f"{'--charts' if self.config.generate_charts else ''}"
                )

                job = AzureMLJob(
                    job_name=f"bench-{suite}-{compute_target}-{timestamp}",
                    display_name=f"Benchmark: {suite} on {compute_target}",
                    description=f"Windows AGI Benchmark Lab — {suite} suite on {compute_target}",
                    compute_target=compute_target,
                    environment=environment,
                    command=command,
                    inputs={},
                    outputs={"reports": {"type": "uri_folder"}},
                    tags={
                        "suite": suite,
                        "compute": compute_target,
                        "project": "Windows-AGI-Benchmark",
                        "vendor": "Microsoft Corporation",
                        "timestamp": timestamp,
                    },
                    experiment_name=f"agi-benchmark-{suite}",
                )
                jobs.append(job)

        return jobs

    def run(self) -> bool:
        """Execute the full benchmark pipeline."""
        log.info("Starting benchmark pipeline: %s", self.config.pipeline_name)
        t_start = time.time()

        # Notify start
        if self.config.notify_teams:
            self.teams.send_benchmark_start(
                self.config.pipeline_name,
                self.config.suites,
            )

        # Build jobs
        self.jobs = self.build_jobs()
        log.info("Built %d jobs", len(self.jobs))

        # Submit all jobs
        submitted_jobs: list[tuple[AzureMLJob, str]] = []
        for job in self.jobs:
            job_id = self.ml_client.submit_job(job)
            if job_id:
                job.job_id = job_id
                job.status = "submitted"
                job.started_at = datetime.datetime.utcnow().isoformat()
                submitted_jobs.append((job, job_id))
                log.info("Submitted: %s → %s", job.job_name, job_id)
            else:
                job.status = "failed"
                log.error("Failed to submit: %s", job.job_name)

        # Wait for all jobs
        all_success = True
        for job, job_id in submitted_jobs:
            status = self.ml_client.wait_for_job(job_id)
            job.status = status
            job.completed_at = datetime.datetime.utcnow().isoformat()

            if status == "Completed":
                log.info("Job completed: %s", job_id)
                # Download outputs
                output_dir = pathlib.Path(f"benchmark/reports/azure/{job_id}")
                self.ml_client.download_outputs(job_id, output_dir)
                # Upload to storage
                self.storage_client.upload_directory(
                    output_dir,
                    prefix=f"runs/{job_id}",
                )
            else:
                log.error("Job failed: %s (status=%s)", job_id, status)
                all_success = False

        # Save pipeline summary
        elapsed = time.time() - t_start
        summary = {
            "pipeline_name": self.config.pipeline_name,
            "started_at": datetime.datetime.utcfromtimestamp(t_start).isoformat() + "Z",
            "completed_at": datetime.datetime.utcnow().isoformat() + "Z",
            "duration_sec": round(elapsed, 2),
            "total_jobs": len(self.jobs),
            "successful_jobs": sum(1 for j in self.jobs if j.status == "Completed"),
            "failed_jobs": sum(1 for j in self.jobs if j.status != "Completed"),
            "jobs": [asdict(j) for j in self.jobs],
        }

        summary_path = pathlib.Path("benchmark/reports/azure/pipeline_summary.json")
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        with open(summary_path, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)

        # Upload summary
        self.storage_client.upload_file(
            summary_path,
            f"pipelines/{self.config.pipeline_name}/summary.json",
        )

        # Notify completion
        if self.config.notify_teams:
            results_url = (
                f"https://portal.azure.com/#resource/subscriptions/{SUBSCRIPTION_ID}"
                f"/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices"
                f"/workspaces/{WORKSPACE_NAME}/experiments"
            )
            self.teams.send_benchmark_complete(
                self.config.pipeline_name,
                elapsed,
                results_url,
                all_success,
            )

        log.info(
            "Pipeline complete: %d/%d jobs succeeded in %.1fs",
            summary["successful_jobs"], summary["total_jobs"], elapsed,
        )

        return all_success


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """Azure ML pipeline entry point."""
    parser = argparse.ArgumentParser(description="Azure ML Benchmark Pipeline — Microsoft AGI Lab")
    parser.add_argument("--deploy", action="store_true", help="Deploy infrastructure")
    parser.add_argument("--run", action="store_true", help="Run benchmark pipeline")
    parser.add_argument("--suite", nargs="+", default=["cpu", "memory", "onnx"])
    parser.add_argument("--compute", nargs="+", default=["cpu-small"])
    parser.add_argument("--models", nargs="+", default=["llama3", "phi4"])
    parser.add_argument("--export", nargs="+", default=["csv", "json"])
    parser.add_argument("--charts", action="store_true")
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--notify", action="store_true", help="Send Teams notifications")
    parser.add_argument("--pipeline-name", default="agi-benchmark-pipeline")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if not SUBSCRIPTION_ID:
        log.error("AZURE_SUBSCRIPTION_ID environment variable not set")
        log.error("Set: export AZURE_SUBSCRIPTION_ID=<your-subscription-id>")
        return 1

    config = BenchmarkPipelineConfig(
        pipeline_name=args.pipeline_name,
        suites=args.suite,
        compute_targets=args.compute,
        models=args.models,
        export_formats=args.export,
        generate_charts=args.charts,
        generate_report=args.report,
        notify_teams=args.notify,
        storage_account=STORAGE_ACCOUNT,
        storage_container=STORAGE_CONTAINER,
        tags={
            "Project": "Windows-AGI-Benchmark",
            "Vendor": "Microsoft Corporation",
            "License": "Exclusive",
        },
    )

    pipeline = BenchmarkPipeline(config)

    if args.deploy:
        log.info("Deploying Azure ML infrastructure...")
        pipeline.setup_infrastructure()

    if args.run:
        log.info("Running benchmark pipeline...")
        success = pipeline.run()
        return 0 if success else 1

    if not args.deploy and not args.run:
        parser.print_help()
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
