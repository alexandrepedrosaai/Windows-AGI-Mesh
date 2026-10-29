# =============================================================================
# Windows AGI Benchmark Lab — AMD ROCm Metrics Collector
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
AMD ROCm GPU metrics collector.

Collects via rocm-smi:
  - GPU utilization (%)
  - VRAM used / total (GB)
  - Power draw (W)
  - Temperature (°C)
  - Clock speeds (MHz)
  - Fan speed (%)
  - PCIe bandwidth
  - Memory clock
  - Compute unit activity

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

log = logging.getLogger("agi.collector.amd")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Data Model
# ---------------------------------------------------------------------------
@dataclass
class AMDGPUMetrics:
    """AMD GPU metrics snapshot."""

    timestamp: str
    card_id: str
    card_name: str
    gpu_util_pct: float
    vram_used_gb: float
    vram_total_gb: float
    vram_util_pct: float
    power_watts: float
    power_cap_watts: float
    temp_edge_c: float
    temp_junction_c: float
    temp_memory_c: float
    gfx_clock_mhz: float
    mem_clock_mhz: float
    fan_speed_pct: float
    pcie_bw_sent_mb: float
    pcie_bw_recv_mb: float
    compute_unit_active_pct: float
    rocm_version: str
    driver_version: str
    status: str
    error_message: str


# ---------------------------------------------------------------------------
# rocm-smi Interface
# ---------------------------------------------------------------------------
def _run_rocm_smi(*args: str) -> dict[str, Any] | None:
    """Run rocm-smi with given args and return parsed JSON."""
    cmd = ["rocm-smi"] + list(args) + ["--json"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)  # type: ignore[no-any-return]
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        log.debug("rocm-smi error: %s", exc)
    return None


def _get_rocm_version() -> str:
    """Get ROCm version string."""
    try:
        result = subprocess.run(
            ["rocminfo"], capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if "ROCm" in line and "Version" in line:
                    return line.split(":")[-1].strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Try /opt/rocm/bin/rocm_agent_enumerator
    try:
        result = subprocess.run(
            ["cat", "/opt/rocm/.info/version"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    return "unknown"


def _get_driver_version() -> str:
    """Get AMD GPU driver version."""
    try:
        result = subprocess.run(
            ["cat", "/sys/module/amdgpu/version"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return "unknown"


def _safe_float(value: Any, default: float = 0.0) -> float:
    """Safely convert a value to float."""
    if value is None:
        return default
    try:
        s = str(value).replace("%", "").replace("W", "").replace("C", "").replace("MHz", "").strip()
        return float(s)
    except (ValueError, TypeError):
        return default


# ---------------------------------------------------------------------------
# Metrics Collection
# ---------------------------------------------------------------------------
def collect_gpu_metrics() -> list[AMDGPUMetrics]:
    """Collect metrics for all AMD GPUs."""
    metrics_list: list[AMDGPUMetrics] = []
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"
    rocm_ver = _get_rocm_version()
    driver_ver = _get_driver_version()

    # Collect all metrics in one call
    all_data = _run_rocm_smi(
        "--showuse",
        "--showtemp",
        "--showpower",
        "--showmemuse",
        "--showclocks",
        "--showfan",
        "--showproductname",
        "--showmeminfo", "vram",
    )

    if not all_data:
        # Try individual calls
        use_data = _run_rocm_smi("--showuse") or {}
        temp_data = _run_rocm_smi("--showtemp") or {}
        power_data = _run_rocm_smi("--showpower") or {}
        mem_data = _run_rocm_smi("--showmeminfo", "vram") or {}
        clock_data = _run_rocm_smi("--showclocks") or {}
        fan_data = _run_rocm_smi("--showfan") or {}
        name_data = _run_rocm_smi("--showproductname") or {}

        # Merge all data by card
        all_data = {}
        for d in [use_data, temp_data, power_data, mem_data, clock_data, fan_data, name_data]:
            for card_id, card_data in d.items():
                if card_id not in all_data:
                    all_data[card_id] = {}
                if isinstance(card_data, dict):
                    all_data[card_id].update(card_data)

    if not all_data:
        log.warning("No AMD GPU data available from rocm-smi")
        return [AMDGPUMetrics(
            timestamp=timestamp,
            card_id="none",
            card_name="No AMD GPU detected",
            gpu_util_pct=0.0,
            vram_used_gb=0.0,
            vram_total_gb=0.0,
            vram_util_pct=0.0,
            power_watts=0.0,
            power_cap_watts=0.0,
            temp_edge_c=0.0,
            temp_junction_c=0.0,
            temp_memory_c=0.0,
            gfx_clock_mhz=0.0,
            mem_clock_mhz=0.0,
            fan_speed_pct=0.0,
            pcie_bw_sent_mb=0.0,
            pcie_bw_recv_mb=0.0,
            compute_unit_active_pct=0.0,
            rocm_version=rocm_ver,
            driver_version=driver_ver,
            status="no_gpu",
            error_message="No AMD GPU detected",
        )]

    for card_id, card_data in all_data.items():
        if not isinstance(card_data, dict):
            continue

        # GPU utilization
        gpu_util = _safe_float(card_data.get("GPU use (%)", card_data.get("GPU Use (%)", 0)))

        # VRAM
        vram_used_bytes = _safe_float(card_data.get("VRAM Total Used Memory (B)", 0))
        vram_total_bytes = _safe_float(card_data.get("VRAM Total Memory (B)", 0))
        vram_used_gb = round(vram_used_bytes / (1024**3), 3)
        vram_total_gb = round(vram_total_bytes / (1024**3), 3)
        vram_util_pct = round(vram_used_gb / vram_total_gb * 100, 1) if vram_total_gb > 0 else 0.0

        # Power
        power_w = _safe_float(card_data.get(
            "Average Graphics Package Power (W)",
            card_data.get("Current Socket Graphics Package Power (W)", 0)
        ))
        power_cap_w = _safe_float(card_data.get("Max Graphics Package Power (W)", 0))

        # Temperature
        temp_edge = _safe_float(card_data.get("Temperature (Sensor edge) (C)", 0))
        temp_junction = _safe_float(card_data.get("Temperature (Sensor junction) (C)", 0))
        temp_memory = _safe_float(card_data.get("Temperature (Sensor memory) (C)", 0))

        # Clocks
        gfx_clock = _safe_float(card_data.get("sclk clock speed:", card_data.get("GFX Clock (MHz)", 0)))
        mem_clock = _safe_float(card_data.get("mclk clock speed:", card_data.get("MEM Clock (MHz)", 0)))

        # Fan
        fan_pct = _safe_float(card_data.get("Fan speed (%)", 0))

        # PCIe bandwidth
        pcie_sent = _safe_float(card_data.get("Sent throughput (MB/s)", 0))
        pcie_recv = _safe_float(card_data.get("Received throughput (MB/s)", 0))

        # Card name
        card_name = str(card_data.get("Card series", card_data.get("Card model", card_id)))

        metrics_list.append(AMDGPUMetrics(
            timestamp=timestamp,
            card_id=card_id,
            card_name=card_name,
            gpu_util_pct=gpu_util,
            vram_used_gb=vram_used_gb,
            vram_total_gb=vram_total_gb,
            vram_util_pct=vram_util_pct,
            power_watts=power_w,
            power_cap_watts=power_cap_w,
            temp_edge_c=temp_edge,
            temp_junction_c=temp_junction,
            temp_memory_c=temp_memory,
            gfx_clock_mhz=gfx_clock,
            mem_clock_mhz=mem_clock,
            fan_speed_pct=fan_pct,
            pcie_bw_sent_mb=pcie_sent,
            pcie_bw_recv_mb=pcie_recv,
            compute_unit_active_pct=gpu_util,  # Approximation
            rocm_version=rocm_ver,
            driver_version=driver_ver,
            status="ok",
            error_message="",
        ))

    return metrics_list


# ---------------------------------------------------------------------------
# Prometheus Exporter
# ---------------------------------------------------------------------------
def _format_prometheus(metrics_list: list[AMDGPUMetrics]) -> str:
    """Format metrics as Prometheus exposition format."""
    lines: list[str] = []

    lines.append("# HELP amd_gpu_util_pct GPU utilization percentage")
    lines.append("# TYPE amd_gpu_util_pct gauge")
    lines.append("# HELP amd_gpu_vram_used_gb VRAM used in GB")
    lines.append("# TYPE amd_gpu_vram_used_gb gauge")
    lines.append("# HELP amd_gpu_vram_total_gb VRAM total in GB")
    lines.append("# TYPE amd_gpu_vram_total_gb gauge")
    lines.append("# HELP amd_gpu_power_watts GPU power draw in watts")
    lines.append("# TYPE amd_gpu_power_watts gauge")
    lines.append("# HELP amd_gpu_temp_edge_c GPU edge temperature in Celsius")
    lines.append("# TYPE amd_gpu_temp_edge_c gauge")
    lines.append("# HELP amd_gpu_temp_junction_c GPU junction temperature in Celsius")
    lines.append("# TYPE amd_gpu_temp_junction_c gauge")
    lines.append("# HELP amd_gpu_gfx_clock_mhz GPU graphics clock in MHz")
    lines.append("# TYPE amd_gpu_gfx_clock_mhz gauge")
    lines.append("# HELP amd_gpu_mem_clock_mhz GPU memory clock in MHz")
    lines.append("# TYPE amd_gpu_mem_clock_mhz gauge")
    lines.append("# HELP amd_gpu_fan_speed_pct GPU fan speed percentage")
    lines.append("# TYPE amd_gpu_fan_speed_pct gauge")

    for m in metrics_list:
        labels = f'card="{m.card_id}",name="{m.card_name}"'
        lines.append(f'amd_gpu_util_pct{{{labels}}} {m.gpu_util_pct}')
        lines.append(f'amd_gpu_vram_used_gb{{{labels}}} {m.vram_used_gb}')
        lines.append(f'amd_gpu_vram_total_gb{{{labels}}} {m.vram_total_gb}')
        lines.append(f'amd_gpu_power_watts{{{labels}}} {m.power_watts}')
        lines.append(f'amd_gpu_temp_edge_c{{{labels}}} {m.temp_edge_c}')
        lines.append(f'amd_gpu_temp_junction_c{{{labels}}} {m.temp_junction_c}')
        lines.append(f'amd_gpu_gfx_clock_mhz{{{labels}}} {m.gfx_clock_mhz}')
        lines.append(f'amd_gpu_mem_clock_mhz{{{labels}}} {m.mem_clock_mhz}')
        lines.append(f'amd_gpu_fan_speed_pct{{{labels}}} {m.fan_speed_pct}')

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
) -> list[AMDGPUMetrics]:
    """Collect AMD GPU metrics over a benchmark duration."""
    log.info("AMD ROCm benchmark: duration=%ds interval=%.1fs", duration_sec, interval_sec)

    all_metrics: list[AMDGPUMetrics] = []
    t_start = time.perf_counter()

    while time.perf_counter() - t_start < duration_sec:
        metrics = collect_gpu_metrics()
        all_metrics.extend(metrics)

        for m in metrics:
            log.info(
                "GPU %s | Util: %.1f%% | VRAM: %.2f/%.2f GB | Power: %.1fW | Temp: %.1f°C",
                m.card_name, m.gpu_util_pct,
                m.vram_used_gb, m.vram_total_gb,
                m.power_watts, m.temp_edge_c,
            )

        time.sleep(interval_sec)

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump([asdict(m) for m in all_metrics], f, indent=2)
        log.info("AMD metrics saved: %s (%d records)", output_path, len(all_metrics))

    return all_metrics


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """AMD ROCm metrics collector entry point."""
    parser = argparse.ArgumentParser(description="AMD ROCm Metrics Collector — Microsoft AGI Lab")
    parser.add_argument("--serve", action="store_true", help="Run as Prometheus exporter")
    parser.add_argument("--port", type=int, default=9400, help="Prometheus exporter port")
    parser.add_argument("--benchmark", action="store_true", help="Run benchmark collection")
    parser.add_argument("--duration", type=int, default=60, help="Benchmark duration (seconds)")
    parser.add_argument("--interval", type=float, default=1.0, help="Collection interval (seconds)")
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("benchmark/reports/amd_metrics.json"))
    parser.add_argument("--once", action="store_true", help="Collect once and print")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.serve:
        log.info("Starting AMD ROCm Prometheus exporter on port %d", args.port)
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
        print(f"\nGPU: {m.card_name} ({m.card_id})")
        print(f"  Utilization:  {m.gpu_util_pct:.1f}%")
        print(f"  VRAM:         {m.vram_used_gb:.2f} / {m.vram_total_gb:.2f} GB ({m.vram_util_pct:.1f}%)")
        print(f"  Power:        {m.power_watts:.1f} W (cap: {m.power_cap_watts:.1f} W)")
        print(f"  Temperature:  Edge={m.temp_edge_c:.1f}°C  Junction={m.temp_junction_c:.1f}°C")
        print(f"  GFX Clock:    {m.gfx_clock_mhz:.0f} MHz")
        print(f"  MEM Clock:    {m.mem_clock_mhz:.0f} MHz")
        print(f"  Fan Speed:    {m.fan_speed_pct:.1f}%")
        print(f"  ROCm:         {m.rocm_version}")
        print(f"  Driver:       {m.driver_version}")

    print(json.dumps([asdict(m) for m in metrics]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
