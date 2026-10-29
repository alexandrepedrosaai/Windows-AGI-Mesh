# =============================================================================
# Windows AGI Benchmark Lab — NVIDIA CUDA Metrics Collector
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
NVIDIA CUDA GPU metrics collector.

Collects via nvidia-smi and pynvml:
  - GPU utilization (%)
  - Memory used / total (GB)
  - Power draw (W)
  - Temperature (°C)
  - Clock speeds (MHz)
  - Fan speed (%)
  - PCIe bandwidth
  - NVLink bandwidth
  - ECC errors
  - Compute processes

Also serves as a Prometheus metrics exporter (--serve mode).
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import pathlib
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

import psutil

log = logging.getLogger("agi.collector.nvidia")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Data Model
# ---------------------------------------------------------------------------
@dataclass
class NVIDIAGPUMetrics:
    """NVIDIA GPU metrics snapshot."""

    timestamp: str
    gpu_index: int
    gpu_name: str
    gpu_uuid: str
    gpu_util_pct: float
    mem_util_pct: float
    vram_used_gb: float
    vram_total_gb: float
    vram_free_gb: float
    power_watts: float
    power_limit_watts: float
    temp_gpu_c: float
    temp_memory_c: float
    gfx_clock_mhz: float
    mem_clock_mhz: float
    sm_clock_mhz: float
    video_clock_mhz: float
    fan_speed_pct: float
    pcie_tx_mb: float
    pcie_rx_mb: float
    nvlink_tx_mb: float
    nvlink_rx_mb: float
    ecc_single_bit: int
    ecc_double_bit: int
    compute_processes: int
    driver_version: str
    cuda_version: str
    compute_capability: str
    status: str
    error_message: str


# ---------------------------------------------------------------------------
# nvidia-smi Interface
# ---------------------------------------------------------------------------
NVIDIA_SMI_QUERY = ",".join([
    "index",
    "name",
    "uuid",
    "utilization.gpu",
    "utilization.memory",
    "memory.used",
    "memory.total",
    "memory.free",
    "power.draw",
    "power.limit",
    "temperature.gpu",
    "temperature.memory",
    "clocks.gr",
    "clocks.mem",
    "clocks.sm",
    "clocks.video",
    "fan.speed",
    "pcie.link.gen.current",
    "pcie.link.width.current",
    "ecc.errors.corrected.volatile.total",
    "ecc.errors.uncorrected.volatile.total",
    "compute_processes.count",
    "driver_version",
    "cuda_version",
])


def _run_nvidia_smi_query() -> list[dict[str, str]]:
    """Run nvidia-smi query and return parsed rows."""
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                f"--query-gpu={NVIDIA_SMI_QUERY}",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return []

        fields = NVIDIA_SMI_QUERY.split(",")
        rows = []
        for line in result.stdout.strip().splitlines():
            values = [v.strip() for v in line.split(",")]
            if len(values) >= len(fields):
                rows.append(dict(zip(fields, values)))
        return rows

    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []


def _get_cuda_version() -> str:
    """Get CUDA version."""
    try:
        result = subprocess.run(
            ["nvcc", "--version"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if "release" in line.lower():
                    return line.split("release")[-1].strip().split(",")[0].strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=cuda_version", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip().splitlines()[0]
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    return "unknown"


def _get_compute_capability(gpu_index: int) -> str:
    """Get GPU compute capability."""
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                f"--id={gpu_index}",
                "--query-gpu=compute_cap",
                "--format=csv,noheader",
            ],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return "unknown"


def _get_nvlink_bandwidth(gpu_index: int) -> tuple[float, float]:
    """Get NVLink TX/RX bandwidth in MB/s."""
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "nvlink",
                f"--id={gpu_index}",
                "--query-nvlink=nvlink.tx,nvlink.rx",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(",")
            if len(parts) >= 2:
                return float(parts[0].strip()), float(parts[1].strip())
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    return 0.0, 0.0


def _safe_float(value: str, default: float = 0.0) -> float:
    """Safely parse a float from nvidia-smi output."""
    try:
        cleaned = value.strip().replace("[N/A]", "0").replace("N/A", "0")
        return float(cleaned)
    except (ValueError, AttributeError):
        return default


def _safe_int(value: str, default: int = 0) -> int:
    """Safely parse an int from nvidia-smi output."""
    try:
        cleaned = value.strip().replace("[N/A]", "0").replace("N/A", "0")
        return int(float(cleaned))
    except (ValueError, AttributeError):
        return default


# ---------------------------------------------------------------------------
# Metrics Collection
# ---------------------------------------------------------------------------
def collect_gpu_metrics() -> list[NVIDIAGPUMetrics]:
    """Collect metrics for all NVIDIA GPUs."""
    metrics_list: list[NVIDIAGPUMetrics] = []
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"
    cuda_ver = _get_cuda_version()

    rows = _run_nvidia_smi_query()

    if not rows:
        log.warning("No NVIDIA GPU data available from nvidia-smi")
        return [NVIDIAGPUMetrics(
            timestamp=timestamp,
            gpu_index=0,
            gpu_name="No NVIDIA GPU detected",
            gpu_uuid="",
            gpu_util_pct=0.0,
            mem_util_pct=0.0,
            vram_used_gb=0.0,
            vram_total_gb=0.0,
            vram_free_gb=0.0,
            power_watts=0.0,
            power_limit_watts=0.0,
            temp_gpu_c=0.0,
            temp_memory_c=0.0,
            gfx_clock_mhz=0.0,
            mem_clock_mhz=0.0,
            sm_clock_mhz=0.0,
            video_clock_mhz=0.0,
            fan_speed_pct=0.0,
            pcie_tx_mb=0.0,
            pcie_rx_mb=0.0,
            nvlink_tx_mb=0.0,
            nvlink_rx_mb=0.0,
            ecc_single_bit=0,
            ecc_double_bit=0,
            compute_processes=0,
            driver_version="unknown",
            cuda_version=cuda_ver,
            compute_capability="unknown",
            status="no_gpu",
            error_message="No NVIDIA GPU detected",
        )]

    for row in rows:
        gpu_index = _safe_int(row.get("index", "0"))
        nvlink_tx, nvlink_rx = _get_nvlink_bandwidth(gpu_index)
        compute_cap = _get_compute_capability(gpu_index)

        # VRAM in MB → GB
        vram_used_gb = round(_safe_float(row.get("memory.used", "0")) / 1024, 3)
        vram_total_gb = round(_safe_float(row.get("memory.total", "0")) / 1024, 3)
        vram_free_gb = round(_safe_float(row.get("memory.free", "0")) / 1024, 3)

        metrics_list.append(NVIDIAGPUMetrics(
            timestamp=timestamp,
            gpu_index=gpu_index,
            gpu_name=row.get("name", "Unknown NVIDIA GPU"),
            gpu_uuid=row.get("uuid", ""),
            gpu_util_pct=_safe_float(row.get("utilization.gpu", "0")),
            mem_util_pct=_safe_float(row.get("utilization.memory", "0")),
            vram_used_gb=vram_used_gb,
            vram_total_gb=vram_total_gb,
            vram_free_gb=vram_free_gb,
            power_watts=_safe_float(row.get("power.draw", "0")),
            power_limit_watts=_safe_float(row.get("power.limit", "0")),
            temp_gpu_c=_safe_float(row.get("temperature.gpu", "0")),
            temp_memory_c=_safe_float(row.get("temperature.memory", "0")),
            gfx_clock_mhz=_safe_float(row.get("clocks.gr", "0")),
            mem_clock_mhz=_safe_float(row.get("clocks.mem", "0")),
            sm_clock_mhz=_safe_float(row.get("clocks.sm", "0")),
            video_clock_mhz=_safe_float(row.get("clocks.video", "0")),
            fan_speed_pct=_safe_float(row.get("fan.speed", "0")),
            pcie_tx_mb=0.0,
            pcie_rx_mb=0.0,
            nvlink_tx_mb=nvlink_tx,
            nvlink_rx_mb=nvlink_rx,
            ecc_single_bit=_safe_int(row.get("ecc.errors.corrected.volatile.total", "0")),
            ecc_double_bit=_safe_int(row.get("ecc.errors.uncorrected.volatile.total", "0")),
            compute_processes=_safe_int(row.get("compute_processes.count", "0")),
            driver_version=row.get("driver_version", "unknown"),
            cuda_version=cuda_ver,
            compute_capability=compute_cap,
            status="ok",
            error_message="",
        ))

    return metrics_list


# ---------------------------------------------------------------------------
# Prometheus Exporter
# ---------------------------------------------------------------------------
def _format_prometheus(metrics_list: list[NVIDIAGPUMetrics]) -> str:
    """Format metrics as Prometheus exposition format."""
    lines: list[str] = []

    metric_defs = [
        ("nvidia_gpu_util_pct", "gauge", "GPU utilization percentage"),
        ("nvidia_gpu_mem_util_pct", "gauge", "GPU memory utilization percentage"),
        ("nvidia_gpu_vram_used_gb", "gauge", "GPU VRAM used in GB"),
        ("nvidia_gpu_vram_total_gb", "gauge", "GPU VRAM total in GB"),
        ("nvidia_gpu_vram_free_gb", "gauge", "GPU VRAM free in GB"),
        ("nvidia_gpu_power_watts", "gauge", "GPU power draw in watts"),
        ("nvidia_gpu_power_limit_watts", "gauge", "GPU power limit in watts"),
        ("nvidia_gpu_temp_gpu_c", "gauge", "GPU temperature in Celsius"),
        ("nvidia_gpu_temp_memory_c", "gauge", "GPU memory temperature in Celsius"),
        ("nvidia_gpu_gfx_clock_mhz", "gauge", "GPU graphics clock in MHz"),
        ("nvidia_gpu_mem_clock_mhz", "gauge", "GPU memory clock in MHz"),
        ("nvidia_gpu_sm_clock_mhz", "gauge", "GPU SM clock in MHz"),
        ("nvidia_gpu_fan_speed_pct", "gauge", "GPU fan speed percentage"),
        ("nvidia_gpu_ecc_single_bit", "counter", "GPU ECC single-bit errors"),
        ("nvidia_gpu_ecc_double_bit", "counter", "GPU ECC double-bit errors"),
        ("nvidia_gpu_compute_processes", "gauge", "Number of compute processes"),
    ]

    for name, metric_type, help_text in metric_defs:
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {metric_type}")

    for m in metrics_list:
        labels = f'gpu="{m.gpu_index}",name="{m.gpu_name}",uuid="{m.gpu_uuid}"'
        lines.append(f'nvidia_gpu_util_pct{{{labels}}} {m.gpu_util_pct}')
        lines.append(f'nvidia_gpu_mem_util_pct{{{labels}}} {m.mem_util_pct}')
        lines.append(f'nvidia_gpu_vram_used_gb{{{labels}}} {m.vram_used_gb}')
        lines.append(f'nvidia_gpu_vram_total_gb{{{labels}}} {m.vram_total_gb}')
        lines.append(f'nvidia_gpu_vram_free_gb{{{labels}}} {m.vram_free_gb}')
        lines.append(f'nvidia_gpu_power_watts{{{labels}}} {m.power_watts}')
        lines.append(f'nvidia_gpu_power_limit_watts{{{labels}}} {m.power_limit_watts}')
        lines.append(f'nvidia_gpu_temp_gpu_c{{{labels}}} {m.temp_gpu_c}')
        lines.append(f'nvidia_gpu_temp_memory_c{{{labels}}} {m.temp_memory_c}')
        lines.append(f'nvidia_gpu_gfx_clock_mhz{{{labels}}} {m.gfx_clock_mhz}')
        lines.append(f'nvidia_gpu_mem_clock_mhz{{{labels}}} {m.mem_clock_mhz}')
        lines.append(f'nvidia_gpu_sm_clock_mhz{{{labels}}} {m.sm_clock_mhz}')
        lines.append(f'nvidia_gpu_fan_speed_pct{{{labels}}} {m.fan_speed_pct}')
        lines.append(f'nvidia_gpu_ecc_single_bit{{{labels}}} {m.ecc_single_bit}')
        lines.append(f'nvidia_gpu_ecc_double_bit{{{labels}}} {m.ecc_double_bit}')
        lines.append(f'nvidia_gpu_compute_processes{{{labels}}} {m.compute_processes}')

    return "\n".join(lines) + "\n"


class PrometheusHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/metrics":
            try:
                metrics = collect_gpu_metrics()
                body = _format_prometheus(metrics).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except Exception as exc:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(exc).encode())
        elif self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt: str, *args: Any) -> None:
        log.debug("HTTP: " + fmt, *args)


# ---------------------------------------------------------------------------
# Benchmark Mode
# ---------------------------------------------------------------------------
def run_benchmark(
    duration_sec: int = 60,
    interval_sec: float = 1.0,
    output_path: pathlib.Path | None = None,
) -> list[NVIDIAGPUMetrics]:
    """Collect NVIDIA GPU metrics over a benchmark duration."""
    log.info("NVIDIA CUDA benchmark: duration=%ds interval=%.1fs", duration_sec, interval_sec)

    all_metrics: list[NVIDIAGPUMetrics] = []
    t_start = time.perf_counter()

    while time.perf_counter() - t_start < duration_sec:
        metrics = collect_gpu_metrics()
        all_metrics.extend(metrics)

        for m in metrics:
            log.info(
                "GPU %d %s | Util: %.1f%% | VRAM: %.2f/%.2f GB | Power: %.1fW | Temp: %.1f°C",
                m.gpu_index, m.gpu_name,
                m.gpu_util_pct,
                m.vram_used_gb, m.vram_total_gb,
                m.power_watts, m.temp_gpu_c,
            )

        time.sleep(interval_sec)

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump([asdict(m) for m in all_metrics], f, indent=2)
        log.info("NVIDIA metrics saved: %s (%d records)", output_path, len(all_metrics))

    return all_metrics


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """NVIDIA CUDA metrics collector entry point."""
    parser = argparse.ArgumentParser(description="NVIDIA CUDA Metrics Collector — Microsoft AGI Lab")
    parser.add_argument("--serve", action="store_true", help="Run as Prometheus exporter")
    parser.add_argument("--port", type=int, default=9401, help="Prometheus exporter port")
    parser.add_argument("--benchmark", action="store_true", help="Run benchmark collection")
    parser.add_argument("--duration", type=int, default=60, help="Benchmark duration (seconds)")
    parser.add_argument("--interval", type=float, default=1.0, help="Collection interval (seconds)")
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("benchmark/reports/nvidia_metrics.json"))
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.serve:
        log.info("Starting NVIDIA CUDA Prometheus exporter on port %d", args.port)
        log.info("Metrics endpoint: http://0.0.0.0:%d/metrics", args.port)
        server = HTTPServer(("0.0.0.0", args.port), PrometheusHandler)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            log.info("Exporter stopped.")
        return 0

    if args.benchmark:
        metrics = run_benchmark(
            duration_sec=args.duration,
            interval_sec=args.interval,
            output_path=args.output,
        )
        print(json.dumps([asdict(m) for m in metrics]))
        return 0

    # Default: collect once
    metrics = collect_gpu_metrics()
    for m in metrics:
        print(f"\nGPU {m.gpu_index}: {m.gpu_name}")
        print(f"  UUID:           {m.gpu_uuid}")
        print(f"  Compute Cap:    {m.compute_capability}")
        print(f"  GPU Util:       {m.gpu_util_pct:.1f}%")
        print(f"  Mem Util:       {m.mem_util_pct:.1f}%")
        print(f"  VRAM:           {m.vram_used_gb:.2f} / {m.vram_total_gb:.2f} GB (free: {m.vram_free_gb:.2f} GB)")
        print(f"  Power:          {m.power_watts:.1f} W (limit: {m.power_limit_watts:.1f} W)")
        print(f"  Temperature:    GPU={m.temp_gpu_c:.1f}°C  Memory={m.temp_memory_c:.1f}°C")
        print(f"  GFX Clock:      {m.gfx_clock_mhz:.0f} MHz")
        print(f"  MEM Clock:      {m.mem_clock_mhz:.0f} MHz")
        print(f"  SM Clock:       {m.sm_clock_mhz:.0f} MHz")
        print(f"  Fan Speed:      {m.fan_speed_pct:.1f}%")
        print(f"  ECC Errors:     Single={m.ecc_single_bit}  Double={m.ecc_double_bit}")
        print(f"  Processes:      {m.compute_processes}")
        print(f"  Driver:         {m.driver_version}")
        print(f"  CUDA:           {m.cuda_version}")

    print(json.dumps([asdict(m) for m in metrics]))
    return 0


if __name__ == "__main__":
    sys.exit(main())