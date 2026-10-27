# =============================================================================
# Windows AGI Benchmark Lab — Assembly Benchmark Orchestrator
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
"""Orchestrates cross-architecture assembly benchmarks via QEMU."""

from __future__ import annotations
import argparse, datetime, json, logging, os, pathlib, platform, subprocess, sys, time
from dataclasses import asdict, dataclass
import psutil

log = logging.getLogger("agi.bench.assembly")
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s")

ARCHITECTURES = {
    "x86_64":  {"binary": "build/x86_64/bench_c",    "qemu": None,           "cc": "gcc"},
    "arm64":   {"binary": "build/arm64/bench_arm64",  "qemu": "qemu-aarch64", "cc": "aarch64-linux-gnu-gcc"},
    "riscv64": {"binary": "build/riscv64/bench_riscv64","qemu":"qemu-riscv64","cc": "riscv64-linux-gnu-gcc"},
    "mips64":  {"binary": "build/mips64/bench_mips64","qemu": "qemu-mips64",  "cc": "mips64-linux-gnuabi64-gcc"},
}

ASSEMBLY_TESTS = {
    "x86_64":  {"asm": "src/x86_64/hello.asm",  "obj": "build/x86_64/hello.o",  "bin": "build/x86_64/hello_x86",  "as": "nasm -f elf64", "ld": "ld"},
    "arm64":   {"asm": "src/arm64/hello.s",      "obj": "build/arm64/hello.o",   "bin": "build/arm64/hello_arm64", "as": "aarch64-linux-gnu-as", "ld": "aarch64-linux-gnu-ld"},
    "riscv64": {"asm": "src/riscv64/hello.s",    "obj": "build/riscv64/hello.o", "bin": "build/riscv64/hello_riscv64","as":"riscv64-linux-gnu-as","ld":"riscv64-linux-gnu-ld"},
}

@dataclass
class AsmResult:
    timestamp: str; suite: str; benchmark: str; model: str
    prompt_type: str; prompt_tokens: int; output_tokens: int
    ttft_ms: float; total_latency_ms: float; tokens_per_sec: float
    vram_used_gb: float; ram_used_gb: float; gpu_util_pct: float
    cpu_util_pct: float; power_watts: float; temp_celsius: float
    context_length: int; batch_size: int; quantization: str
    backend: str; device: str; gpu_vendor: str; gpu_model: str
    host_os: str; status: str; error_message: str; notes: str

def _detect_host_os() -> str:
    return "WSL2" if "microsoft" in platform.uname().release.lower() else platform.system()

def _make_result(benchmark: str, arch: str, latency_ms: float, status: str="success",
                 error_msg: str="", notes: str="") -> AsmResult:
    mem = psutil.virtual_memory()
    return AsmResult(
        timestamp=datetime.datetime.utcnow().isoformat()+"Z", suite="assembly",
        benchmark=benchmark, model=arch, prompt_type="",
        prompt_tokens=0, output_tokens=0, ttft_ms=0.0,
        total_latency_ms=latency_ms, tokens_per_sec=round(1000/latency_ms,2) if latency_ms>0 else 0.0,
        vram_used_gb=0.0, ram_used_gb=round(mem.used/(1024**3),2),
        gpu_util_pct=0.0, cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=0.0, temp_celsius=0.0, context_length=0, batch_size=1,
        quantization="", backend="native" if not ARCHITECTURES.get(arch,{}).get("qemu") else "qemu",
        device="cpu", gpu_vendor="none", gpu_model="none", host_os=_detect_host_os(),
        status=status, error_message=error_msg, notes=notes)

def build_c_binary(arch: str, config: dict) -> bool:
    binary = pathlib.Path(config["binary"])
    binary.parent.mkdir(parents=True, exist_ok=True)
    if binary.exists():
        log.info("Binary already exists: %s", binary)
        return True
    cc = config["cc"]
    cmd = [cc, "src/c/main.c", "-O2", "-o", str(binary), "-lm", "-static"]
    if arch == "arm64":   cmd += ["-march=armv8-a"]
    if arch == "riscv64": cmd += ["-march=rv64gc", "-mabi=lp64d"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode == 0:
            log.info("Built %s binary: %s", arch, binary)
            return True
        else:
            log.error("Build failed for %s: %s", arch, result.stderr[:300])
            return False
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        log.warning("Cannot build %s: %s", arch, exc)
        return False

def build_asm_binary(arch: str, config: dict) -> bool:
    asm_path = pathlib.Path(config["asm"])
    obj_path = pathlib.Path(config["obj"])
    bin_path = pathlib.Path(config["bin"])
    if not asm_path.exists():
        log.warning("Assembly source not found: %s", asm_path)
        return False
    obj_path.parent.mkdir(parents=True, exist_ok=True)
    as_cmd = config["as"].split() + [str(asm_path), "-o", str(obj_path)]
    ld_cmd = config["ld"].split() + [str(obj_path), "-o", str(bin_path)]
    try:
        r1 = subprocess.run(as_cmd, capture_output=True, text=True, timeout=30)
        if r1.returncode != 0:
            log.error("Assembly failed for %s: %s", arch, r1.stderr[:200])
            return False
        r2 = subprocess.run(ld_cmd, capture_output=True, text=True, timeout=30)
        if r2.returncode != 0:
            log.error("Link failed for %s: %s", arch, r2.stderr[:200])
            return False
        log.info("Built %s assembly: %s", arch, bin_path)
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        log.warning("Cannot build %s assembly: %s", arch, exc)
        return False

def run_binary(arch: str, binary: str, qemu: str | None, timeout: int=120) -> tuple[str, float, str]:
    binary_path = pathlib.Path(binary)
    if not binary_path.exists():
        return "skipped", 0.0, f"Binary not found: {binary}"
    cmd = []
    if qemu:
        if not _check_command(qemu):
            return "skipped", 0.0, f"QEMU not found: {qemu}"
        lib_path = {
            "qemu-aarch64": "/usr/aarch64-linux-gnu",
            "qemu-riscv64": "/usr/riscv64-linux-gnu",
            "qemu-mips64":  "/usr/mips64-linux-gnuabi64",
        }.get(qemu, "")
        cmd = [qemu]
        if lib_path and pathlib.Path(lib_path).exists():
            cmd += ["-L", lib_path]
        cmd.append(str(binary_path))
    else:
        cmd = [str(binary_path)]
    t0 = time.perf_counter()
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        elapsed_ms = round((time.perf_counter()-t0)*1000, 2)
        if result.returncode == 0:
            return "success", elapsed_ms, result.stdout[:500]
        else:
            return "error", elapsed_ms, result.stderr[:300]
    except subprocess.TimeoutExpired:
        return "timeout", timeout*1000.0, f"Timed out after {timeout}s"
    except Exception as exc:
        return "error", 0.0, str(exc)[:300]

def _check_command(cmd: str) -> bool:
    try:
        subprocess.run([cmd,"--version"], capture_output=True, timeout=3)
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False

def bench_architecture(arch: str, config: dict) -> list[AsmResult]:
    results = []
    log.info("Benchmarking architecture: %s", arch)
    # Build C binary
    built = build_c_binary(arch, config)
    if built:
        status, latency_ms, output = run_binary(arch, config["binary"], config.get("qemu"))
        results.append(_make_result(f"c_bench_{arch}", arch, latency_ms, status,
                                    error_msg="" if status=="success" else output,
                                    notes=f"binary={config['binary']} qemu={config.get('qemu')}"))
    else:
        results.append(_make_result(f"c_bench_{arch}", arch, 0.0, "skipped",
                                    error_msg=f"Build failed for {arch}"))
    # Build assembly binary
    if arch in ASSEMBLY_TESTS:
        asm_config = ASSEMBLY_TESTS[arch]
        asm_built = build_asm_binary(arch, asm_config)
        if asm_built:
            status, latency_ms, output = run_binary(arch, asm_config["bin"], config.get("qemu"), timeout=30)
            results.append(_make_result(f"asm_hello_{arch}", arch, latency_ms, status,
                                        error_msg="" if status=="success" else output,
                                        notes=f"asm={asm_config['asm']}"))
        else:
            results.append(_make_result(f"asm_hello_{arch}", arch, 0.0, "skipped",
                                        error_msg=f"Assembly build failed for {arch}"))
    return results

def main() -> int:
    parser = argparse.ArgumentParser(description="Assembly Benchmark — Microsoft AGI Lab")
    parser.add_argument("--arch", nargs="+", default=list(ARCHITECTURES.keys()))
    parser.add_argument("--output", default="benchmark/reports/assembly_results.json")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()
    if args.verbose: logging.getLogger().setLevel(logging.DEBUG)

    all_results = []
    for arch in args.arch:
        if arch not in ARCHITECTURES:
            log.warning("Unknown architecture: %s", arch)
            continue
        results = bench_architecture(arch, ARCHITECTURES[arch])
        all_results.extend(results)

    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump({"suite":"assembly","results":[asdict(r) for r in all_results]}, f, indent=2)
    log.info("Results saved: %s (%d records)", out_path, len(all_results))
    print(json.dumps([asdict(r) for r in all_results]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
