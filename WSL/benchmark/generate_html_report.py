# =============================================================================
# Windows AGI Benchmark Lab — HTML Report Generator
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
HTML report generator for benchmark results.

Produces a self-contained, interactive HTML report with:
  - Executive summary
  - System information
  - GPU comparison tables
  - Runtime comparison tables
  - Interactive charts (Chart.js)
  - Architecture comparison
  - Quantization analysis
  - Recommendations
  - Full raw data table
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import pathlib
import platform
import sys
from typing import Any

import pandas as pd
import psutil

log = logging.getLogger("agi.bench.report")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

VERSION = "1.0.0"
VENDOR = "Microsoft Corporation"
PROJECT = "Windows AGI Benchmark Lab"


# ---------------------------------------------------------------------------
# Data Loading
# ---------------------------------------------------------------------------
def load_data(csv_path: pathlib.Path, json_path: pathlib.Path) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Load benchmark data from CSV and JSON."""
    df = pd.DataFrame()
    meta: dict[str, Any] = {}

    if csv_path.exists():
        df = pd.read_csv(csv_path)
        numeric_cols = [
            "tokens_per_sec", "ttft_ms", "total_latency_ms",
            "vram_used_gb", "ram_used_gb", "gpu_util_pct",
            "cpu_util_pct", "power_watts", "temp_celsius",
            "context_length", "batch_size",
        ]
        for col in numeric_cols:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0.0)

    if json_path.exists():
        with open(json_path, encoding="utf-8") as f:
            data = json.load(f)
        meta = data.get("meta", {})
        if "system" in data:
            meta["system"] = data["system"]

    return df, meta


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------
def compute_stats(df: pd.DataFrame) -> dict[str, Any]:
    """Compute summary statistics."""
    if df.empty:
        return {}

    success_df = df[df["status"] == "success"].copy()

    stats: dict[str, Any] = {
        "total_benchmarks": len(df),
        "successful": len(success_df),
        "failed": len(df[df["status"] == "error"]),
        "skipped": len(df[df["status"] == "skipped"]),
        "suites": sorted(df["suite"].unique().tolist()) if "suite" in df.columns else [],
        "gpu_vendors": sorted(df["gpu_vendor"].unique().tolist()) if "gpu_vendor" in df.columns else [],
        "gpu_models": sorted(df["gpu_model"].unique().tolist()) if "gpu_model" in df.columns else [],
        "models_tested": sorted(df["model"].unique().tolist()) if "model" in df.columns else [],
    }

    if not success_df.empty:
        tps_df = success_df[success_df["tokens_per_sec"] > 0]
        if not tps_df.empty:
            stats["avg_tokens_per_sec"] = round(tps_df["tokens_per_sec"].mean(), 2)
            stats["max_tokens_per_sec"] = round(tps_df["tokens_per_sec"].max(), 2)
            stats["best_gpu"] = tps_df.loc[tps_df["tokens_per_sec"].idxmax(), "gpu_model"]

        ttft_df = success_df[success_df["ttft_ms"] > 0]
        if not ttft_df.empty:
            stats["avg_ttft_ms"] = round(ttft_df["ttft_ms"].mean(), 2)
            stats["min_ttft_ms"] = round(ttft_df["ttft_ms"].min(), 2)

        pw_df = success_df[success_df["power_watts"] > 0]
        if not pw_df.empty:
            stats["avg_power_watts"] = round(pw_df["power_watts"].mean(), 2)

    return stats


def compute_gpu_table(df: pd.DataFrame) -> list[dict[str, Any]]:
    """Compute per-GPU summary table."""
    if df.empty:
        return []

    success_df = df[df["status"] == "success"].copy()
    if success_df.empty:
        return []

    rows = []
    for (vendor, model), group in success_df.groupby(["gpu_vendor", "gpu_model"]):
        tps_vals = group[group["tokens_per_sec"] > 0]["tokens_per_sec"]
        ttft_vals = group[group["ttft_ms"] > 0]["ttft_ms"]
        vram_vals = group[group["vram_used_gb"] > 0]["vram_used_gb"]
        pw_vals = group[group["power_watts"] > 0]["power_watts"]
        temp_vals = group[group["temp_celsius"] > 0]["temp_celsius"]

        avg_tps = round(tps_vals.mean(), 2) if not tps_vals.empty else 0.0
        avg_pw = round(pw_vals.mean(), 2) if not pw_vals.empty else 0.0
        ppw = round(avg_tps / avg_pw, 4) if avg_pw > 0 else 0.0

        rows.append({
            "vendor": vendor.upper(),
            "model": model,
            "avg_tps": avg_tps,
            "max_tps": round(tps_vals.max(), 2) if not tps_vals.empty else 0.0,
            "avg_ttft_ms": round(ttft_vals.mean(), 2) if not ttft_vals.empty else 0.0,
            "avg_vram_gb": round(vram_vals.mean(), 2) if not vram_vals.empty else 0.0,
            "avg_power_w": avg_pw,
            "avg_temp_c": round(temp_vals.mean(), 2) if not temp_vals.empty else 0.0,
            "perf_per_watt": ppw,
            "benchmarks": len(group),
        })

    return sorted(rows, key=lambda x: x["avg_tps"], reverse=True)


def compute_runtime_table(df: pd.DataFrame) -> list[dict[str, Any]]:
    """Compute per-runtime summary table."""
    if df.empty or "suite" not in df.columns:
        return []

    success_df = df[df["status"] == "success"].copy()
    if success_df.empty:
        return []

    rows = []
    for suite, group in success_df.groupby("suite"):
        tps_vals = group[group["tokens_per_sec"] > 0]["tokens_per_sec"]
        ttft_vals = group[group["ttft_ms"] > 0]["ttft_ms"]

        rows.append({
            "runtime": suite.upper(),
            "avg_tps": round(tps_vals.mean(), 2) if not tps_vals.empty else 0.0,
            "max_tps": round(tps_vals.max(), 2) if not tps_vals.empty else 0.0,
            "avg_ttft_ms": round(ttft_vals.mean(), 2) if not ttft_vals.empty else 0.0,
            "benchmarks": len(group),
            "success_rate": round(len(group) / max(len(df[df["suite"] == suite]), 1) * 100, 1),
        })

    return sorted(rows, key=lambda x: x["avg_tps"], reverse=True)


# ---------------------------------------------------------------------------
# HTML Template
# ---------------------------------------------------------------------------
def _render_html(
    stats: dict[str, Any],
    gpu_table: list[dict[str, Any]],
    runtime_table: list[dict[str, Any]],
    meta: dict[str, Any],
    df: pd.DataFrame,
    generated_at: str,
) -> str:
    """Render the full HTML report."""

    # Prepare chart data
    gpu_labels = json.dumps([r["model"] for r in gpu_table])
    gpu_tps = json.dumps([r["avg_tps"] for r in gpu_table])
    gpu_ttft = json.dumps([r["avg_ttft_ms"] for r in gpu_table])
    gpu_vram = json.dumps([r["avg_vram_gb"] for r in gpu_table])
    gpu_power = json.dumps([r["avg_power_w"] for r in gpu_table])
    gpu_ppw = json.dumps([r["perf_per_watt"] for r in gpu_table])
    gpu_colors = json.dumps([
        "#ED1C24" if r["vendor"] == "AMD" else
        "#76B900" if r["vendor"] == "NVIDIA" else
        "#0071C5" if r["vendor"] == "INTEL" else
        "#737373"
        for r in gpu_table
    ])

    runtime_labels = json.dumps([r["runtime"] for r in runtime_table])
    runtime_tps = json.dumps([r["avg_tps"] for r in runtime_table])

    # GPU table rows
    gpu_rows_html = ""
    for i, r in enumerate(gpu_table):
        badge_color = "#ED1C24" if r["vendor"] == "AMD" else "#76B900" if r["vendor"] == "NVIDIA" else "#0071C5"
        rank = "🥇" if i == 0 else "🥈" if i == 1 else "🥉" if i == 2 else f"#{i+1}"
        gpu_rows_html += f"""
        <tr>
            <td>{rank}</td>
            <td><span class="badge" style="background:{badge_color}">{r['vendor']}</span></td>
            <td><strong>{r['model']}</strong></td>
            <td class="metric-good">{r['avg_tps']}</td>
            <td>{r['max_tps']}</td>
            <td>{r['avg_ttft_ms']}</td>
            <td>{r['avg_vram_gb']}</td>
            <td>{r['avg_power_w']}</td>
            <td>{r['avg_temp_c']}</td>
            <td class="metric-good">{r['perf_per_watt']}</td>
            <td>{r['benchmarks']}</td>
        </tr>"""

    # Runtime table rows
    runtime_rows_html = ""
    for i, r in enumerate(runtime_table):
        rank = "🥇" if i == 0 else "🥈" if i == 1 else "🥉" if i == 2 else f"#{i+1}"
        runtime_rows_html += f"""
        <tr>
            <td>{rank}</td>
            <td><strong>{r['runtime']}</strong></td>
            <td class="metric-good">{r['avg_tps']}</td>
            <td>{r['max_tps']}</td>
            <td>{r['avg_ttft_ms']}</td>
            <td>{r['benchmarks']}</td>
            <td>{r['success_rate']}%</td>
        </tr>"""

    # System info
    sys_info = meta.get("system", {})
    system_html = f"""
        <tr><td>Hostname</td><td>{sys_info.get('hostname', platform.node())}</td></tr>
        <tr><td>OS</td><td>{sys_info.get('os', platform.system())}</td></tr>
        <tr><td>WSL2</td><td>{'Yes' if sys_info.get('wsl2', False) else 'No'}</td></tr>
        <tr><td>CPU</td><td>{sys_info.get('cpu', platform.processor())}</td></tr>
        <tr><td>CPU Cores</td><td>{sys_info.get('cores', psutil.cpu_count())}</td></tr>
        <tr><td>RAM</td><td>{sys_info.get('ram_gb', round(psutil.virtual_memory().total / (1024**3), 1))} GB</td></tr>
        <tr><td>GPU Vendor</td><td>{sys_info.get('gpu_vendor', 'unknown').upper()}</td></tr>
        <tr><td>GPU Model</td><td>{sys_info.get('gpu_model', 'unknown')}</td></tr>
        <tr><td>GPU VRAM</td><td>{sys_info.get('gpu_vram_gb', 0)} GB</td></tr>
        <tr><td>ROCm Version</td><td>{sys_info.get('rocm', 'n/a')}</td></tr>
        <tr><td>CUDA Version</td><td>{sys_info.get('cuda', 'n/a')}</td></tr>
    """

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows AGI Benchmark Lab — Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        :root {{
            --bg-primary: #1E1E1E;
            --bg-secondary: #252526;
            --bg-card: #2D2D30;
            --border: #3E3E42;
            --text-primary: #CCCCCC;
            --text-secondary: #9D9D9D;
            --text-heading: #FFFFFF;
            --accent-blue: #0078D4;
            --accent-green: #107C10;
            --accent-red: #D13438;
            --accent-orange: #FF8C00;
            --amd-red: #ED1C24;
            --nvidia-green: #76B900;
            --intel-blue: #0071C5;
        }}
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
        }}
        .header {{
            background: linear-gradient(135deg, #003087 0%, #0078D4 50%, #50E6FF 100%);
            padding: 40px;
            text-align: center;
        }}
        .header h1 {{ font-size: 2.2rem; color: #fff; font-weight: 700; margin-bottom: 8px; }}
        .header p {{ color: rgba(255,255,255,0.85); font-size: 1rem; }}
        .header .meta {{ margin-top: 16px; font-size: 0.85rem; color: rgba(255,255,255,0.7); }}
        .container {{ max-width: 1400px; margin: 0 auto; padding: 32px 24px; }}
        .section {{ margin-bottom: 40px; }}
        .section-title {{
            font-size: 1.4rem; font-weight: 600; color: var(--text-heading);
            border-left: 4px solid var(--accent-blue);
            padding-left: 12px; margin-bottom: 20px;
        }}
        .cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 32px; }}
        .card {{
            background: var(--bg-card); border: 1px solid var(--border);
            border-radius: 8px; padding: 20px; text-align: center;
        }}
        .card .value {{ font-size: 2rem; font-weight: 700; color: var(--accent-blue); }}
        .card .label {{ font-size: 0.85rem; color: var(--text-secondary); margin-top: 4px; }}
        .card.green .value {{ color: #107C10; }}
        .card.red .value {{ color: #D13438; }}
        .card.orange .value {{ color: #FF8C00; }}
        .chart-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(500px, 1fr)); gap: 24px; }}
        .chart-card {{
            background: var(--bg-card); border: 1px solid var(--border);
            border-radius: 8px; padding: 20px;
        }}
        .chart-card h3 {{ font-size: 1rem; color: var(--text-heading); margin-bottom: 16px; }}
        .chart-container {{ position: relative; height: 300px; }}
        table {{ width: 100%; border-collapse: collapse; font-size: 0.9rem; }}
        th {{
            background: var(--bg-secondary); color: var(--text-heading);
            padding: 10px 12px; text-align: left; border-bottom: 2px solid var(--border);
            font-weight: 600; white-space: nowrap;
        }}
        td {{ padding: 9px 12px; border-bottom: 1px solid var(--border); }}
        tr:hover {{ background: rgba(255,255,255,0.03); }}
        .metric-good {{ color: #107C10; font-weight: 600; }}
        .metric-bad {{ color: #D13438; }}
        .badge {{
            display: inline-block; padding: 2px 8px; border-radius: 4px;
            font-size: 0.75rem; font-weight: 700; color: #fff;
        }}
        .table-wrapper {{
            background: var(--bg-card); border: 1px solid var(--border);
            border-radius: 8px; overflow: hidden; overflow-x: auto;
        }}
        .footer {{
            text-align: center; padding: 32px;
            border-top: 1px solid var(--border);
            color: var(--text-secondary); font-size: 0.85rem;
        }}
        .sys-table {{ max-width: 600px; }}
        .sys-table td:first-child {{ color: var(--text-secondary); width: 160px; }}
        .sys-table td:last-child {{ color: var(--text-heading); font-weight: 500; }}
        @media (max-width: 768px) {{
            .chart-grid {{ grid-template-columns: 1fr; }}
            .header h1 {{ font-size: 1.5rem; }}
        }}
    </style>
</head>
<body>

<div class="header">
    <h1>🚀 Windows AGI Benchmark Lab</h1>
    <p>Heterogeneous AI Inference Benchmark Report</p>
    <div class="meta">
        {VENDOR} — Exclusive Property &nbsp;|&nbsp;
        Version {VERSION} &nbsp;|&nbsp;
        Generated: {generated_at}
    </div>
</div>

<div class="container">

    <!-- Executive Summary -->
    <div class="section">
        <div class="section-title">Executive Summary</div>
        <div class="cards">
            <div class="card">
                <div class="value">{stats.get('total_benchmarks', 0)}</div>
                <div class="label">Total Benchmarks</div>
            </div>
            <div class="card green">
                <div class="value">{stats.get('successful', 0)}</div>
                <div class="label">Successful</div>
            </div>
            <div class="card red">
                <div class="value">{stats.get('failed', 0)}</div>
                <div class="label">Failed</div>
            </div>
            <div class="card">
                <div class="value">{stats.get('avg_tokens_per_sec', 0)}</div>
                <div class="label">Avg Tokens/sec</div>
            </div>
            <div class="card green">
                <div class="value">{stats.get('max_tokens_per_sec', 0)}</div>
                <div class="label">Peak Tokens/sec</div>
            </div>
            <div class="card orange">
                <div class="value">{stats.get('avg_ttft_ms', 0)}</div>
                <div class="label">Avg TTFT (ms)</div>
            </div>
            <div class="card">
                <div class="value">{stats.get('avg_power_watts', 0)}</div>
                <div class="label">Avg Power (W)</div>
            </div>
            <div class="card">
                <div class="value">{len(stats.get('suites', []))}</div>
                <div class="label">Suites Run</div>
            </div>
        </div>
    </div>

    <!-- Charts -->
    <div class="section">
        <div class="section-title">Performance Charts</div>
        <div class="chart-grid">

            <div class="chart-card">
                <h3>Tokens per Second — GPU Comparison</h3>
                <div class="chart-container">
                    <canvas id="chartTPS"></canvas>
                </div>
            </div>

            <div class="chart-card">
                <h3>Time to First Token (TTFT) — Lower is Better</h3>
                <div class="chart-container">
                    <canvas id="chartTTFT"></canvas>
                </div>
            </div>

            <div class="chart-card">
                <h3>VRAM Usage (GB)</h3>
                <div class="chart-container">
                    <canvas id="chartVRAM"></canvas>
                </div>
            </div>

            <div class="chart-card">
                <h3>Power Consumption (W)</h3>
                <div class="chart-container">
                    <canvas id="chartPower"></canvas>
                </div>
            </div>

            <div class="chart-card">
                <h3>Performance per Watt (Tok/s/W)</h3>
                <div class="chart-container">
                    <canvas id="chartPPW"></canvas>
                </div>
            </div>

            <div class="chart-card">
                <h3>Runtime Comparison — Avg Tokens/sec</h3>
                <div class="chart-container">
                    <canvas id="chartRuntime"></canvas>
                </div>
            </div>

        </div>
    </div>

    <!-- GPU Table -->
    <div class="section">
        <div class="section-title">GPU Performance Table</div>
        <div class="table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>Rank</th>
                        <th>Vendor</th>
                        <th>GPU Model</th>
                        <th>Avg Tok/s</th>
                        <th>Max Tok/s</th>
                        <th>Avg TTFT (ms)</th>
                        <th>Avg VRAM (GB)</th>
                        <th>Avg Power (W)</th>
                        <th>Avg Temp (°C)</th>
                        <th>Perf/Watt</th>
                        <th>Benchmarks</th>
                    </tr>
                </thead>
                <tbody>
                    {gpu_rows_html}
                </tbody>
            </table>
        </div>
    </div>

    <!-- Runtime Table -->
    <div class="section">
        <div class="section-title">Runtime Comparison Table</div>
        <div class="table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>Rank</th>
                        <th>Runtime</th>
                        <th>Avg Tok/s</th>
                        <th>Max Tok/s</th>
                        <th>Avg TTFT (ms)</th>
                        <th>Benchmarks</th>
                        <th>Success Rate</th>
                    </tr>
                </thead>
                <tbody>
                    {runtime_rows_html}
                </tbody>
            </table>
        </div>
    </div>

    <!-- System Information -->
    <div class="section">
        <div class="section-title">System Information</div>
        <div class="table-wrapper sys-table">
            <table>
                <tbody>
                    {system_html}
                </tbody>
            </table>
        </div>
    </div>

</div>

<div class="footer">
    <p><strong>{PROJECT}</strong></p>
    <p>{VENDOR} — Exclusive License — All Rights Reserved</p>
    <p>Generated: {generated_at} | Version {VERSION}</p>
</div>

<script>
const chartDefaults = {{
    responsive: true,
    maintainAspectRatio: false,
    plugins: {{
        legend: {{ display: false }},
        tooltip: {{ backgroundColor: '#2D2D30', titleColor: '#fff', bodyColor: '#ccc' }}
    }},
    scales: {{
        x: {{ ticks: {{ color: '#9D9D9D', maxRotation: 30 }}, grid: {{ color: '#3E3E42' }} }},
        y: {{ ticks: {{ color: '#9D9D9D' }}, grid: {{ color: '#3E3E42' }} }}
    }}
}};

// Tokens per Second
new Chart(document.getElementById('chartTPS'), {{
    type: 'bar',
    data: {{
        labels: {gpu_labels},
        datasets: [{{ label: 'Tokens/sec', data: {gpu_tps}, backgroundColor: {gpu_colors}, borderRadius: 4 }}]
    }},
    options: {{ ...chartDefaults, plugins: {{ ...chartDefaults.plugins, legend: {{ display: false }} }} }}
}});

// TTFT
new Chart(document.getElementById('chartTTFT'), {{
    type: 'bar',
    data: {{
        labels: {gpu_labels},
        datasets: [{{ label: 'TTFT (ms)', data: {gpu_ttft}, backgroundColor: '#FF8C00', borderRadius: 4 }}]
    }},
    options: chartDefaults
}});

// VRAM
new Chart(document.getElementById('chartVRAM'), {{
    type: 'bar',
    data: {{
        labels: {gpu_labels},
        datasets: [{{ label: 'VRAM (GB)', data: {gpu_vram}, backgroundColor: '#5C2D91', borderRadius: 4 }}]
    }},
    options: chartDefaults
}});

// Power
new Chart(document.getElementById('chartPower'), {{
    type: 'bar',
    data: {{
        labels: {gpu_labels},
        datasets: [{{ label: 'Power (W)', data: {gpu_power}, backgroundColor: '#D13438', borderRadius: 4 }}]
    }},
    options: chartDefaults
}});

// Perf per Watt
new Chart(document.getElementById('chartPPW'), {{
    type: 'bar',
    data: {{
        labels: {gpu_labels},
        datasets: [{{ label: 'Tok/s/W', data: {gpu_ppw}, backgroundColor: '#107C10', borderRadius: 4 }}]
    }},
    options: chartDefaults
}});

// Runtime
new Chart(document.getElementById('chartRuntime'), {{
    type: 'bar',
    data: {{
        labels: {runtime_labels},
        datasets: [{{ label: 'Avg Tok/s', data: {runtime_tps}, backgroundColor: '#0078D4', borderRadius: 4 }}]
    }},
    options: chartDefaults
}});
</script>

</body>
</html>"""

    return html


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """Generate HTML benchmark report."""
    parser = argparse.ArgumentParser(description="HTML Report Generator — Microsoft AGI Lab")
    parser.add_argument("--csv", type=pathlib.Path, default=pathlib.Path("benchmark/reports/benchmark_latest.csv"))
    parser.add_argument("--json", type=pathlib.Path, default=pathlib.Path("benchmark/reports/benchmark_latest.json"))
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("benchmark/reports/report.html"))
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    df, meta = load_data(args.csv, args.json)

    if df.empty:
        log.warning("No data found. Run benchmarks first.")
        df = pd.DataFrame()

    stats = compute_stats(df)
    gpu_table = compute_gpu_table(df)
    runtime_table = compute_runtime_table(df)

    generated_at = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

    html = _render_html(
        stats=stats,
        gpu_table=gpu_table,
        runtime_table=runtime_table,
        meta=meta,
        df=df,
        generated_at=generated_at,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(html)

    log.info("HTML report saved: %s", args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())