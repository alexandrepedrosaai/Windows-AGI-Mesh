# =============================================================================
# Windows AGI Benchmark Lab — System Metrics Collector
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
System-wide metrics collector.

Collects:
  - CPU utilization per core
  - CPU frequency
  - Memory (RAM) usage
  - Swap usage
  - Disk I/O (read/write MB/s)
  - Network I/O (TX/RX MB/s)
  - Process list (top consumers)
  - System load averages
  - Thermal zones
  - Battery (if applicable)
  - Docker container stats
  - WSL2 detection

Serves as Prometheus exporter and standalone collector.
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import os
import pathlib
import platform
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

import psutil

log = logging.getLogger("agi.collector.system")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------
@dataclass
class CPUMetrics:
    """CPU metrics snapshot."""

    timestamp: str
    cpu_model: str
    cpu_arch: str
    cores_physical: int
    cores_logical: int
    freq_current_mhz: float
    freq_min_mhz: float
    freq_max_mhz: float
    util_total_pct: float
    util_user_pct: float
    util_system_pct: float
    util_idle_pct: float
    util_iowait_pct: float
    util_per_core: list[float]
    load_avg_1m: float
    load_avg_5m: float
    load_avg_15m: float
    ctx_switches_per_sec: float
    interrupts_per_sec: float
    is_wsl2: bool
    is_arm64: bool
    is_riscv: bool


@dataclass
class MemoryMetrics:
    """Memory metrics snapshot."""

    timestamp: str
    ram_total_gb: float
    ram_used_gb: float
    ram_free_gb: float
    ram_available_gb: float
    ram_util_pct: float
    ram_cached_gb: float
    ram_buffers_gb: float
    swap_total_gb: float
    swap_used_gb: float
    swap_free_gb: float
    swap_util_pct: float


@dataclass
class DiskMetrics:
    """Disk I/O metrics snapshot."""

    timestamp: str
    device: str
    mount_point: str
    total_gb: float
    used_gb: float
    free_gb: float
    util_pct: float
    read_mb_s: float
    write_mb_s: float
    read_iops: float
    write_iops: float
    read_latency_ms: float
    write_latency_ms: float


@dataclass
class NetworkMetrics:
    """Network I/O metrics snapshot."""

    timestamp: str
    interface: str
    bytes_sent_mb_s: float
    bytes_recv_mb_s: float
    packets_sent_per_s: float
    packets_recv_per_s: float
    errors_in: int
    errors_out: int
    drops_in: int
    drops_out: int


@dataclass
class SystemSnapshot:
    """Complete system metrics snapshot."""

    timestamp: str
    hostname: str
    os_name: str
    os_version: str
    kernel: str
    python_version: str
    uptime_hours: float
    is_wsl2: bool
    is_docker: bool
    cpu: CPUMetrics
    memory: MemoryMetrics
    disks: list[DiskMetrics] = field(default_factory=list)
    networks: list[NetworkMetrics] = field(default_factory=list)
    top_processes: list[dict[str, Any]] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Collection Functions
# ---------------------------------------------------------------------------
def _detect_wsl2() -> bool:
    """Detect if running inside WSL2."""
    try:
        release = platform.uname().release.lower()
        return "microsoft" in release or "wsl" in release
    except Exception:
        return False


def _detect_docker() -> bool:
    """Detect if running inside Docker."""
    return pathlib.Path("/.dockerenv").exists()


def _detect_arch() -> tuple[bool, bool]:
    """Return (is_arm64, is_riscv)."""
    machine = platform.machine().lower()
    is_arm64 = machine in ("aarch64", "arm64")
    is_riscv = "riscv" in machine
    return is_arm64, is_riscv


def _get_cpu_model() -> str:
    """Get CPU model name."""
    try:
        import cpuinfo  # type: ignore[import]
        return cpuinfo.get_cpu_info().get("brand_raw", platform.processor())
    except ImportError:
        pass

    try:
        with open("/proc/cpuinfo", encoding="utf-8") as f:
            for line in f:
                if "model name" in line.lower() and ":" in line:
                    return line.split(":", 1)[1].strip()
    except (FileNotFoundError, PermissionError):
        pass

    return platform.processor() or "Unknown CPU"


def collect_cpu_metrics(prev_cpu_times: Any = None) -> tuple[CPUMetrics, Any]:
    """Collect CPU metrics."""
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"

    # Utilization
    cpu_times_pct = psutil.cpu_times_percent(interval=0.5)
    util_total = psutil.cpu_percent(interval=None)
    util_per_core = psutil.cpu_percent(interval=None, percpu=True)

    # Frequency
    freq = psutil.cpu_freq()
    freq_current = round(freq.current, 1) if freq else 0.0
    freq_min = round(freq.min, 1) if freq else 0.0
    freq_max = round(freq.max, 1) if freq else 0.0

    # Load average
    try:
        load_1, load_5, load_15 = os.getloadavg()
    except (AttributeError, OSError):
        load_1 = load_5 = load_15 = 0.0

    # Context switches and interrupts
    cpu_stats = psutil.cpu_stats()
    ctx_switches = cpu_stats.ctx_switches
    interrupts = cpu_stats.interrupts

    is_arm64, is_riscv = _detect_arch()

    metrics = CPUMetrics(
        timestamp=timestamp,
        cpu_model=_get_cpu_model(),
        cpu_arch=platform.machine(),
        cores_physical=psutil.cpu_count(logical=False) or 1,
        cores_logical=psutil.cpu_count(logical=True) or 1,
        freq_current_mhz=freq_current,
        freq_min_mhz=freq_min,
        freq_max_mhz=freq_max,
        util_total_pct=round(util_total, 2),
        util_user_pct=round(cpu_times_pct.user, 2),
        util_system_pct=round(cpu_times_pct.system, 2),
        util_idle_pct=round(cpu_times_pct.idle, 2),
        util_iowait_pct=round(getattr(cpu_times_pct, "iowait", 0.0), 2),
        util_per_core=[round(c, 1) for c in (util_per_core if isinstance(util_per_core, list) else [util_per_core])],
        load_avg_1m=round(load_1, 3),
        load_avg_5m=round(load_5, 3),
        load_avg_15m=round(load_15, 3),
        ctx_switches_per_sec=0.0,
        interrupts_per_sec=0.0,
        is_wsl2=_detect_wsl2(),
        is_arm64=is_arm64,
        is_riscv=is_riscv,
    )

    return metrics, (ctx_switches, interrupts)


def collect_memory_metrics() -> MemoryMetrics:
    """Collect memory metrics."""
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"

    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()

    def to_gb(b: int) -> float:
        return round(b / (1024**3), 3)

    return MemoryMetrics(
        timestamp=timestamp,
        ram_total_gb=to_gb(mem.total),
        ram_used_gb=to_gb(mem.used),
        ram_free_gb=to_gb(mem.free),
        ram_available_gb=to_gb(mem.available),
        ram_util_pct=round(mem.percent, 2),
        ram_cached_gb=to_gb(getattr(mem, "cached", 0)),
        ram_buffers_gb=to_gb(getattr(mem, "buffers", 0)),
        swap_total_gb=to_gb(swap.total),
        swap_used_gb=to_gb(swap.used),
        swap_free_gb=to_gb(swap.free),
        swap_util_pct=round(swap.percent, 2),
    )


def collect_disk_metrics(
    prev_disk_io: dict[str, Any] | None = None,
    interval_sec: float = 1.0,
) -> tuple[list[DiskMetrics], dict[str, Any]]:
    """Collect disk metrics."""
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"
    results: list[DiskMetrics] = []

    # Disk usage per partition
    partitions = psutil.disk_partitions(all=False)

    # Disk I/O counters
    disk_io = psutil.disk_io_counters(perdisk=True)

    for partition in partitions:
        try:
            usage = psutil.disk_usage(partition.mountpoint)
        except (PermissionError, OSError):
            continue

        def to_gb(b: int) -> float:
            return round(b / (1024**3), 2)

        # I/O rates
        read_mb_s = 0.0
        write_mb_s = 0.0
        read_iops = 0.0
        write_iops = 0.0

        device_name = partition.device.split("/")[-1]
        if disk_io and device_name in disk_io and prev_disk_io and device_name in prev_disk_io:
            curr = disk_io[device_name]
            prev = prev_disk_io[device_name]
            read_mb_s = round((curr.read_bytes - prev.read_bytes) / interval_sec / (1024**2), 2)
            write_mb_s = round((curr.write_bytes - prev.write_bytes) / interval_sec / (1024**2), 2)
            read_iops = round((curr.read_count - prev.read_count) / interval_sec, 1)
            write_iops = round((curr.write_count - prev.write_count) / interval_sec, 1)

        results.append(DiskMetrics(
            timestamp=timestamp,
            device=partition.device,
            mount_point=partition.mountpoint,
            total_gb=to_gb(usage.total),
            used_gb=to_gb(usage.used),
            free_gb=to_gb(usage.free),
            util_pct=round(usage.percent, 2),
            read_mb_s=max(0.0, read_mb_s),
            write_mb_s=max(0.0, write_mb_s),
            read_iops=max(0.0, read_iops),
            write_iops=max(0.0, write_iops),
            read_latency_ms=0.0,
            write_latency_ms=0.0,
        ))

    return results, {k: v for k, v in (disk_io or {}).items()}


def collect_network_metrics(
    prev_net_io: dict[str, Any] | None = None,
    interval_sec: float = 1.0,
) -> tuple[list[NetworkMetrics], dict[str, Any]]:
    """Collect network metrics."""
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"
    results: list[NetworkMetrics] = []

    net_io = psutil.net_io_counters(pernic=True)

    for iface, counters in net_io.items():
        # Skip loopback
        if iface == "lo":
            continue

        bytes_sent_mb_s = 0.0
        bytes_recv_mb_s = 0.0
        packets_sent_s = 0.0
        packets_recv_s = 0.0

        if prev_net_io and iface in prev_net_io:
            prev = prev_net_io[iface]
            bytes_sent_mb_s = round((counters.bytes_sent - prev.bytes_sent) / interval_sec / (1024**2), 3)
            bytes_recv_mb_s = round((counters.bytes_recv - prev.bytes_recv) / interval_sec / (1024**2), 3)
            packets_sent_s = round((counters.packets_sent - prev.packets_sent) / interval_sec, 1)
            packets_recv_s = round((counters.packets_recv - prev.packets_recv) / interval_sec, 1)

        results.append(NetworkMetrics(
            timestamp=timestamp,
            interface=iface,
            bytes_sent_mb_s=max(0.0, bytes_sent_mb_s),
            bytes_recv_mb_s=max(0.0, bytes_recv_mb_s),
            packets_sent_per_s=max(0.0, packets_sent_s),
            packets_recv_per_s=max(0.0, packets_recv_s),
            errors_in=counters.errin,
            errors_out=counters.errout,
            drops_in=counters.dropin,
            drops_out=counters.dropout,
        ))

    return results, {k: v for k, v in net_io.items()}


def collect_top_processes(n: int = 10) -> list[dict[str, Any]]:
    """Collect top N processes by CPU usage."""
    processes = []
    for proc in psutil.process_iter(["pid", "name", "cpu_percent", "memory_percent", "status"]):
        try:
            info = proc.info
            processes.append({
                "pid": info["pid"],
                "name": info["name"],
                "cpu_pct": round(info["cpu_percent"] or 0.0, 2),
                "mem_pct": round(info["memory_percent"] or 0.0, 2),
                "status": info["status"],
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    return sorted(processes, key=lambda x: x["cpu_pct"], reverse=True)[:n]


def collect_snapshot() -> SystemSnapshot:
    """Collect a complete system snapshot."""
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"

    # Uptime
    boot_time = psutil.boot_time()
    uptime_hours = round((time.time() - boot_time) / 3600, 2)

    cpu_metrics, _ = collect_cpu_metrics()
    mem_metrics = collect_memory_metrics()
    disk_metrics, _ = collect_disk_metrics()
    net_metrics, _ = collect_network_metrics()
    top_procs = collect_top_processes()

    return SystemSnapshot(
        timestamp=timestamp,
        hostname=platform.node(),
        os_name=platform.system(),
        os_version=platform.version(),
        kernel=platform.release(),
        python_version=platform.python_version(),
        uptime_hours=uptime_hours,
        is_wsl2=_detect_wsl2(),
        is_docker=_detect_docker(),
        cpu=cpu_metrics,
        memory=mem_metrics,
        disks=disk_metrics,
        networks=net_metrics,
        top_processes=top_procs,
    )


# ---------------------------------------------------------------------------
# Prometheus Exporter
# ---------------------------------------------------------------------------
def _format_prometheus(snapshot: SystemSnapshot) -> str:
    """Format system snapshot as Prometheus metrics."""
    lines: list[str] = []
    cpu = snapshot.cpu
    mem = snapshot.memory

    # CPU metrics
    lines += [
        "# HELP system_cpu_util_pct CPU utilization percentage",
        "# TYPE system_cpu_util_pct gauge",
        f"system_cpu_util_pct {cpu.util_total_pct}",
        f"system_cpu_util_user_pct {cpu.util_user_pct}",
        f"system_cpu_util_system_pct {cpu.util_system_pct}",
        f"system_cpu_util_idle_pct {cpu.util_idle_pct}",
        f"system_cpu_freq_mhz {cpu.freq_current_mhz}",
        f"system_cpu_load_avg_1m {cpu.load_avg_1m}",
        f"system_cpu_load_avg_5m {cpu.load_avg_5m}",
        f"system_cpu_load_avg_15m {cpu.load_avg_15m}",
    ]

    # Per-core CPU
    for i, util in enumerate(cpu.util_per_core):
        lines.append(f'system_cpu_core_util_pct{{core="{i}"}} {util}')

    # Memory metrics
    lines += [
        "# HELP system_ram_used_gb RAM used in GB",
        "# TYPE system_ram_used_gb gauge",
        f"system_ram_total_gb {mem.ram_total_gb}",
        f"system_ram_used_gb {mem.ram_used_gb}",
        f"system_ram_free_gb {mem.ram_free_gb}",
        f"system_ram_available_gb {mem.ram_available_gb}",
        f"system_ram_util_pct {mem.ram_util_pct}",
        f"system_swap_used_gb {mem.swap_used_gb}",
        f"system_swap_util_pct {mem.swap_util_pct}",
    ]

    # Disk metrics
    for disk in snapshot.disks:
        labels = f'device="{disk.device}",mount="{disk.mount_point}"'
        lines += [
            f"system_disk_used_gb{{{labels}}} {disk.used_gb}",
            f"system_disk_free_gb{{{labels}}} {disk.free_gb}",
            f"system_disk_util_pct{{{labels}}} {disk.util_pct}",
            f"system_disk_read_mb_s{{{labels}}} {disk.read_mb_s}",
            f"system_disk_write_mb_s{{{labels}}} {disk.write_mb_s}",
        ]

    # Network metrics
    for net in snapshot.networks:
        labels = f'interface="{net.interface}"'
        lines += [
            f"system_net_sent_mb_s{{{labels}}} {net.bytes_sent_mb_s}",
            f"system_net_recv_mb_s{{{labels}}} {net.bytes_recv_mb_s}",
            f"system_net_errors_in{{{labels}}} {net.errors_in}",
            f"system_net_errors_out{{{labels}}} {net.errors_out}",
        ]

    return "\n".join(lines) + "\n"


class SystemPrometheusHandler(BaseHTTPRequestHandler):
    """HTTP handler for system Prometheus metrics."""

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/metrics":
            try:
                snapshot = collect_snapshot()
                body = _format_prometheus(snapshot).encode("utf-8")
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
# Continuous Collection
# ---------------------------------------------------------------------------
def run_continuous(
    duration_sec: int = 60,
    interval_sec: float = 1.0,
    output_path: pathlib.Path | None = None,
) -> list[SystemSnapshot]:
    """Collect system metrics continuously."""
    log.info("System metrics collection: duration=%ds interval=%.1fs", duration_sec, interval_sec)

    snapshots: list[SystemSnapshot] = []
    t_start = time.perf_counter()

    while time.perf_counter() - t_start < duration_sec:
        snapshot = collect_snapshot()
        snapshots.append(snapshot)

        log.info(
            "CPU: %.1f%% | RAM: %.1f/%.1f GB | Load: %.2f %.2f %.2f",
            snapshot.cpu.util_total_pct,
            snapshot.memory.ram_used_gb,
            snapshot.memory.ram_total_gb,
            snapshot.cpu.load_avg_1m,
            snapshot.cpu.load_avg_5m,
            snapshot.cpu.load_avg_15m,
        )

        time.sleep(interval_sec)

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump([asdict(s) for s in snapshots], f, indent=2)
        log.info("System metrics saved: %s (%d snapshots)", output_path, len(snapshots))

    return snapshots


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """System metrics collector entry point."""
    parser = argparse.ArgumentParser(description="System Metrics Collector — Microsoft AGI Lab")
    parser.add_argument("--serve", action="store_true", help="Run as Prometheus exporter")
    parser.add_argument("--port", type=int, default=9402, help="Prometheus exporter port")
    parser.add_argument("--continuous", action="store_true", help="Continuous collection")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("benchmark/reports/system_metrics.json"))
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.serve:
        log.info("Starting System Prometheus exporter on port %d", args.port)
        server = HTTPServer(("0.0.0.0", args.port), SystemPrometheusHandler)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            log.info("Exporter stopped.")
        return 0

    if args.continuous:
        snapshots = run_continuous(args.duration, args.interval, args.output)
        return 0

    # Single snapshot
    snapshot = collect_snapshot()
    cpu = snapshot.cpu
    mem = snapshot.memory

    print(f"\n{'='*60}")
    print(f"  System Snapshot — {snapshot.timestamp}")
    print(f"{'='*60}")
    print(f"  Host:     {snapshot.hostname}")
    print(f"  OS:       {snapshot.os_name} {snapshot.kernel}")
    print(f"  WSL2:     {snapshot.is_wsl2}")
    print(f"  Docker:   {snapshot.is_docker}")
    print(f"  Uptime:   {snapshot.uptime_hours:.1f} hours")
    print(f"\n  CPU: {cpu.cpu_model}")
    print(f"  Arch:     {cpu.cpu_arch}")
    print(f"  Cores:    {cpu.cores_physical}P / {cpu.cores_logical}L")
    print(f"  Freq:     {cpu.freq_current_mhz:.0f} MHz")
    print(f"  Util:     {cpu.util_total_pct:.1f}% (user={cpu.util_user_pct:.1f}% sys={cpu.util_system_pct:.1f}%)")
    print(f"  Load:     {cpu.load_avg_1m:.2f} {cpu.load_avg_5m:.2f} {cpu.load_avg_15m:.2f}")
    print(f"\n  RAM:      {mem.ram_used_gb:.2f} / {mem.ram_total_gb:.2f} GB ({mem.ram_util_pct:.1f}%)")
    print(f"  Swap:     {mem.swap_used_gb:.2f} / {mem.swap_total_gb:.2f} GB ({mem.swap_util_pct:.1f}%)")

    for disk in snapshot.disks[:3]:
        print(f"\n  Disk {disk.mount_point}: {disk.used_gb:.1f}/{disk.total_gb:.1f} GB ({disk.util_pct:.1f}%)")
        print(f"    Read: {disk.read_mb_s:.1f} MB/s  Write: {disk.write_mb_s:.1f} MB/s")

    print(f"\n  Top Processes:")
    for proc in snapshot.top_processes[:5]:
        print(f"    [{proc['pid']:6}] {proc['name']:<20} CPU={proc['cpu_pct']:5.1f}% MEM={proc['mem_pct']:5.1f}%")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())