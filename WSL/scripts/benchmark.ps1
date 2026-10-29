# =============================================================================
# Windows AGI Benchmark Lab — PowerShell Benchmark Runner
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
# Windows 11 / PowerShell 7+ benchmark runner
# Supports: Native Windows, WSL2 passthrough, Azure Cloud Shell
#
# Usage:
#   .\scripts\benchmark.ps1 -Suite all -GPU amd -Charts -Report
#   .\scripts\benchmark.ps1 -Suite cpu,memory -Export csv,json
#   .\scripts\benchmark.ps1 -Full
# =============================================================================

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Benchmark suites to run")]
    [ValidateSet("all", "cpu", "memory", "ollama", "onnx", "pytorch", "llamacpp", "assembly", "gpu", "system")]
    [string[]]$Suite = @("cpu", "memory"),

    [Parameter(HelpMessage = "GPU vendor")]
    [ValidateSet("auto", "amd", "nvidia", "none")]
    [string]$GPU = "auto",

    [Parameter(HelpMessage = "LLM models to benchmark")]
    [string[]]$Models = @("llama3", "phi4"),

    [Parameter(HelpMessage = "Export formats")]
    [ValidateSet("csv", "json")]
    [string[]]$Export = @("csv", "json"),

    [Parameter(HelpMessage = "Generate charts")]
    [switch]$Charts,

    [Parameter(HelpMessage = "Generate HTML report")]
    [switch]$Report,

    [Parameter(HelpMessage = "Run all suites with charts and report")]
    [switch]$Full,

    [Parameter(HelpMessage = "Benchmark duration in seconds")]
    [int]$Duration = 60,

    [Parameter(HelpMessage = "Output directory")]
    [string]$OutputDir = "benchmark\reports",

    [Parameter(HelpMessage = "Use WSL2 for Linux benchmarks")]
    [switch]$UseWSL2,

    [Parameter(HelpMessage = "Dry run — show commands without executing")]
    [switch]$DryRun,

    [Parameter(HelpMessage = "Verbose output")]
    [switch]$Verbose
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$ErrorActionPreference = "Continue"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $OutputDir "benchmark_$Timestamp.log"
$ProjectName = "Windows AGI Benchmark Lab"
$Vendor = "Microsoft Corporation"
$Version = "1.0.0"

# Full mode overrides
if ($Full) {
    $Suite = @("all")
    $Charts = $true
    $Report = $true
}

# ---------------------------------------------------------------------------
# Colors & Logging
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan -NoNewline
    Write-Host ""
    Add-Content -Path $LogFile -Value "[STEP] $Message" -ErrorAction SilentlyContinue
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "INFO"  { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "[$ts] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message" -ErrorAction SilentlyContinue
}

function Write-Header {
    $line = "=" * 65
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $ProjectName" -ForegroundColor Cyan
    Write-Host "  $Vendor — Exclusive License" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Timestamp:  $Timestamp"
    Write-Host "  Suite:      $($Suite -join ', ')"
    Write-Host "  GPU:        $GPU"
    Write-Host "  Models:     $($Models -join ', ')"
    Write-Host "  Export:     $($Export -join ', ')"
    Write-Host "  Charts:     $Charts"
    Write-Host "  Report:     $Report"
    Write-Host "  WSL2:       $UseWSL2"
    Write-Host "  Output:     $OutputDir"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# System Detection
# ---------------------------------------------------------------------------
function Get-SystemInfo {
    Write-Step "Collecting System Information"

    $info = [PSCustomObject]@{
        Hostname    = $env:COMPUTERNAME
        OS          = (Get-WmiObject Win32_OperatingSystem).Caption
        OSVersion   = [System.Environment]::OSVersion.Version.ToString()
        Architecture = $env:PROCESSOR_ARCHITECTURE
        CPU         = (Get-WmiObject Win32_Processor | Select-Object -First 1).Name
        Cores       = (Get-WmiObject Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
        LogicalCPUs = (Get-WmiObject Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        RAM_GB      = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        PowerShell  = $PSVersionTable.PSVersion.ToString()
        WSL2        = $false
        Docker      = $false
    }

    # Check WSL2
    try {
        $wslOutput = wsl --status 2>&1
        $info.WSL2 = $LASTEXITCODE -eq 0
    } catch { }

    # Check Docker
    try {
        docker --version 2>&1 | Out-Null
        $info.Docker = $LASTEXITCODE -eq 0
    } catch { }

    Write-Log "Host:     $($info.Hostname)"
    Write-Log "OS:       $($info.OS)"
    Write-Log "CPU:      $($info.CPU)"
    Write-Log "Cores:    $($info.Cores)P / $($info.LogicalCPUs)L"
    Write-Log "RAM:      $($info.RAM_GB) GB"
    Write-Log "WSL2:     $($info.WSL2)"
    Write-Log "Docker:   $($info.Docker)"

    return $info
}

function Detect-GPU {
    Write-Step "Detecting GPU"

    if ($GPU -ne "auto") {
        Write-Log "GPU vendor specified: $GPU"
        return $GPU
    }

    # Try NVIDIA
    try {
        $nvidiaSmi = nvidia-smi --query-gpu=name --format=csv,noheader 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Detected NVIDIA GPU: $($nvidiaSmi | Select-Object -First 1)"
            return "nvidia"
        }
    } catch { }

    # Try AMD via WMI
    try {
        $gpus = Get-WmiObject Win32_VideoController
        foreach ($gpu in $gpus) {
            if ($gpu.Name -match "AMD|Radeon|RX") {
                Write-Log "Detected AMD GPU: $($gpu.Name)"
                return "amd"
            }
        }
    } catch { }

    Write-Log "No discrete GPU detected — CPU-only mode"
    return "none"
}

# ---------------------------------------------------------------------------
# WSL2 Command Execution
# ---------------------------------------------------------------------------
function Invoke-WSL2Command {
    param(
        [string]$Script,
        [string[]]$Arguments = @(),
        [string]$WorkingDir = "."
    )

    $wslDir = "/mnt/c/$(($WorkingDir -replace '\\', '/').TrimStart('C:/'))"
    $displayCmd = "python3 $Script $($Arguments -join ' ')"

    if ($DryRun) {
        Write-Log "[DRY RUN] WSL2: $displayCmd"
        return 0
    }

    Write-Log "WSL2: $displayCmd"
    wsl --cd $wslDir python3 $Script @Arguments
    return $LASTEXITCODE
}

function Invoke-PythonBenchmark {
    param(
        [string]$Script,
        [string[]]$Arguments = @(),
        [string]$OutputFile = ""
    )

    $argList = @($Script)
    if ($Arguments) {
        $argList += $Arguments
    }
    if ($OutputFile) {
        $argList += @("--output", $OutputFile)
    }
    if ($Verbose) {
        $argList += "--verbose"
    }

    $displayCmd = "python3 $($argList -join ' ')"

    if ($UseWSL2) {
        return Invoke-WSL2Command -Script $Script -Arguments $argList[1..($argList.Count - 1)] -WorkingDir (Get-Location).Path
    } else {
        if ($DryRun) {
            Write-Log "[DRY RUN] $displayCmd"
            return 0
        }
        Write-Log "Running: $displayCmd"
        & python3 @argList
        return $LASTEXITCODE
    }
}

# ---------------------------------------------------------------------------
# Benchmark Functions
# ---------------------------------------------------------------------------
function Run-CPUBenchmark {
    Write-Step "CPU Benchmark"
    $outFile = Join-Path $OutputDir "cpu_results.json"
    $result = Invoke-PythonBenchmark -Script "benchmark/benchmark_cpu.py" -OutputFile $outFile
    if ($result -eq 0) {
        Write-Log "CPU benchmark complete ✅"
    } else {
        Write-Log "CPU benchmark failed ⚠️" -Level "WARN"
    }
}

function Run-MemoryBenchmark {
    Write-Step "Memory Benchmark"
    $outFile = Join-Path $OutputDir "memory_results.json"
    $result = Invoke-PythonBenchmark -Script "benchmark/benchmark_cpu.py" -OutputFile $outFile
    if ($result -eq 0) {
        Write-Log "Memory benchmark complete ✅"
    } else {
        Write-Log "Memory benchmark failed ⚠️" -Level "WARN"
    }
}

function Run-OllamaBenchmark {
    Write-Step "Ollama LLM Benchmark"

    # Check if Ollama is running
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
        Write-Log "Ollama is running"
    } catch {
        Write-Log "Ollama not running at localhost:11434 — skipping" -Level "WARN"
        Write-Log "Start with: ollama serve" -Level "WARN"
        return
    }

    $modelsArg = $Models -join " "
    $outFile = Join-Path $OutputDir "ollama_results.json"
    $result = Invoke-PythonBenchmark `
        -Script "benchmark/benchmark_ollama.py" `
        -Arguments "--models $modelsArg" `
        -OutputFile $outFile

    if ($result -eq 0) {
        Write-Log "Ollama benchmark complete ✅"
    } else {
        Write-Log "Ollama benchmark failed ⚠️" -Level "WARN"
    }
}

function Run-ONNXBenchmark {
    Write-Step "ONNX Runtime Benchmark"

    # Check if onnxruntime is installed
    $checkResult = python3 -c "import onnxruntime; print('ok')" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "onnxruntime not installed — run: pip install onnxruntime" -Level "WARN"
        return
    }

    $outFile = Join-Path $OutputDir "onnx_results.json"
    $result = Invoke-PythonBenchmark -Script "benchmark/benchmark_onnx.py" -OutputFile $outFile

    if ($result -eq 0) {
        Write-Log "ONNX benchmark complete ✅"
    } else {
        Write-Log "ONNX benchmark failed ⚠️" -Level "WARN"
    }
}

function Run-PyTorchBenchmark {
    Write-Step "PyTorch Benchmark"

    $checkResult = python3 -c "import torch; print('ok')" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "PyTorch not installed — run: pip install torch" -Level "WARN"
        return
    }

    $device = if ($GPU -eq "nvidia" -or $GPU -eq "amd") { "cuda" } else { "cpu" }
    $outFile = Join-Path $OutputDir "pytorch_results.json"
    $result = Invoke-PythonBenchmark `
        -Script "benchmark/benchmark_pytorch.py" `
        -Arguments "--device $device --vendor $(if ($GPU -eq 'none') { 'auto' } else { $GPU })" `
        -OutputFile $outFile

    if ($result -eq 0) {
        Write-Log "PyTorch benchmark complete ✅"
    } else {
        Write-Log "PyTorch benchmark failed ⚠️" -Level "WARN"
    }
}

function Run-AssemblyBenchmark {
    Write-Step "Assembly Benchmark (via WSL2)"

    if (-not $UseWSL2) {
        Write-Log "Assembly benchmarks require WSL2 — use -UseWSL2 flag" -Level "WARN"
        return
    }

    # x86_64
    if (Test-Path "build/x86_64/bench_c") {
        Write-Log "Running x86_64 C benchmark..."
        Invoke-WSL2Command -Command "./build/x86_64/bench_c" | Tee-Object -FilePath (Join-Path $OutputDir "assembly_x86_results.txt")
    }

    # ARM64 via QEMU
    if (Test-Path "build/arm64/bench_arm64") {
        Write-Log "Running ARM64 benchmark via QEMU..."
        Invoke-WSL2Command -Command "qemu-aarch64 -L /usr/aarch64-linux-gnu build/arm64/bench_arm64" | `
            Tee-Object -FilePath (Join-Path $OutputDir "assembly_arm64_results.txt")
    }

    # RISC-V via QEMU
    if (Test-Path "build/riscv64/bench_riscv64") {
        Write-Log "Running RISC-V benchmark via QEMU..."
        Invoke-WSL2Command -Command "qemu-riscv64 -L /usr/riscv64-linux-gnu build/riscv64/bench_riscv64" | `
            Tee-Object -FilePath (Join-Path $OutputDir "assembly_riscv64_results.txt")
    }

    Write-Log "Assembly benchmarks complete ✅"
}

function Run-GPUMetrics {
    Write-Step "GPU Metrics Collection"

    $detectedGPU = if ($GPU -eq "auto") { Detect-GPU } else { $GPU }

    if ($detectedGPU -eq "amd") {
        $outFile = Join-Path $OutputDir "amd_metrics.json"
        Invoke-PythonBenchmark `
            -Script "collectors/amd_rocm.py" `
            -Arguments "--benchmark --duration $Duration" `
            -OutputFile $outFile
    } elseif ($detectedGPU -eq "nvidia") {
        $outFile = Join-Path $OutputDir "nvidia_metrics.json"
        Invoke-PythonBenchmark `
            -Script "collectors/nvidia_cuda.py" `
            -Arguments "--benchmark --duration $Duration" `
            -OutputFile $outFile
    } else {
        Write-Log "No GPU — skipping GPU metrics"
    }
}

function Run-SystemMetrics {
    Write-Step "System Metrics Collection"
    $outFile = Join-Path $OutputDir "system_metrics.json"
    Invoke-PythonBenchmark -Script "collectors/system_metrics.py" -OutputFile $outFile
}

function Generate-Charts {
    if (-not $Charts) { return }

    Write-Step "Generating Charts"
    $csvFile = Join-Path $OutputDir "benchmark_latest.csv"
    $args = @("benchmark/generate_charts.py", "--input", $csvFile, "--output", $OutputDir, "--sample")
    if ($VerbosePreference -eq "Continue") { $args += "--verbose" }
    $cmd = "python3 benchmark/generate_charts.py --input `"$csvFile`" --output `"$OutputDir`" --sample"
    if ($VerbosePreference -eq "Continue") { $cmd += " --verbose" }

    if ($UseWSL2) {
        Invoke-WSL2Command -Command $cmd
    } elseif (-not $DryRun) {
        & python3 @args
    } else {
        Write-Log "[DRY RUN] $cmd"
    }

    Write-Log "Charts saved to: $OutputDir"
}

function Generate-Report {
    if (-not $Report) { return }

    Write-Step "Generating HTML Report"
    $csvFile = Join-Path $OutputDir "benchmark_latest.csv"
    $jsonFile = Join-Path $OutputDir "benchmark_latest.json"
    $htmlFile = Join-Path $OutputDir "report_$Timestamp.html"

    $args = @("benchmark/generate_html_report.py", "--csv", $csvFile, "--json", $jsonFile, "--output", $htmlFile)
    $cmd = "python3 benchmark/generate_html_report.py --csv `"$csvFile`" --json `"$jsonFile`" --output `"$htmlFile`""

    if ($UseWSL2) {
        Invoke-WSL2Command -Command $cmd
    } elseif (-not $DryRun) {
        & python3 @args
        # Open in browser
        if (Test-Path $htmlFile) {
            Start-Process $htmlFile
        }
    } else {
        Write-Log "[DRY RUN] $cmd"
    }

    Write-Log "HTML report: $htmlFile"
}

# ---------------------------------------------------------------------------
# Windows-Specific Benchmarks
# ---------------------------------------------------------------------------
function Run-WindowsNativeBenchmark {
    Write-Step "Windows Native Performance Counters"

    if ($DryRun) {
        Write-Log "[DRY RUN] Windows performance counter collection"
        return
    }

    $results = @{
        timestamp   = (Get-Date -Format "o")
        hostname    = $env:COMPUTERNAME
        cpu_usage   = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        ram_used_gb = [math]::Round(((Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize - (Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory) / 1MB, 2)
        ram_total_gb = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        disk_read_mb_s = 0
        disk_write_mb_s = 0
    }

    # Disk I/O via performance counters
    try {
        $diskCounters = Get-Counter "\PhysicalDisk(_Total)\Disk Read Bytes/sec", "\PhysicalDisk(_Total)\Disk Write Bytes/sec" -ErrorAction SilentlyContinue
        if ($diskCounters) {
            $results.disk_read_mb_s = [math]::Round($diskCounters.CounterSamples[0].CookedValue / 1MB, 2)
            $results.disk_write_mb_s = [math]::Round($diskCounters.CounterSamples[1].CookedValue / 1MB, 2)
        }
    } catch { }

    $outFile = Join-Path $OutputDir "windows_metrics.json"
    $results | ConvertTo-Json | Set-Content -Path $outFile
    Write-Log "Windows metrics saved: $outFile"
}

# ---------------------------------------------------------------------------
# Docker Stack Management
# ---------------------------------------------------------------------------
function Start-DockerStack {
    param([string]$DockerProfile = "amd")

    Write-Step "Starting Docker Stack (profile: $DockerProfile)"

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Log "Docker not found — install Docker Desktop" -Level "WARN"
        return
    }

    $composeArgs = @(
        "-f", "docker/docker-compose.yml",
        "-f", "docker/docker-compose.monitoring.yml"
    )

    if ($DockerProfile -eq "amd") {
        $composeArgs += @("-f", "docker/docker-compose.amd.yml")
    } elseif ($DockerProfile -eq "nvidia") {
        $composeArgs += @("-f", "docker/docker-compose.nvidia.yml")
    }

    $composeArgs += @("--profile", $DockerProfile, "up", "-d")
    $cmdDisplay = "docker compose $($composeArgs -join ' ')"

    if ($DryRun) {
        Write-Log "[DRY RUN] $cmdDisplay"
    } else {
        Write-Log "Starting: $cmdDisplay"
        & docker compose @composeArgs
        Write-Log "Docker stack started ✅"
        Write-Log "OpenWebUI:  http://localhost:3000"
        Write-Log "Grafana:    http://localhost:3001"
        Write-Log "Prometheus: http://localhost:9090"
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Main {
    # Create output directory
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    Write-Header

    $startTime = Get-Date
    $sysInfo = Get-SystemInfo
    $detectedGPU = Detect-GPU

    if ($GPU -eq "auto") {
        $GPU = $detectedGPU
    }

    # Run selected suites
    foreach ($s in $Suite) {
        switch ($s.ToLower()) {
            "all" {
                Run-CPUBenchmark
                Run-MemoryBenchmark
                Run-OllamaBenchmark
                Run-ONNXBenchmark
                Run-PyTorchBenchmark
                Run-AssemblyBenchmark
                Run-GPUMetrics
                Run-SystemMetrics
                Run-WindowsNativeBenchmark
            }
            "cpu"       { Run-CPUBenchmark }
            "memory"    { Run-MemoryBenchmark }
            "ollama"    { Run-OllamaBenchmark }
            "onnx"      { Run-ONNXBenchmark }
            "pytorch"   { Run-PyTorchBenchmark }
            "llamacpp"  { Run-LlamaCppBenchmark }
            "assembly"  { Run-AssemblyBenchmark }
            "gpu"       { Run-GPUMetrics }
            "system"    { Run-SystemMetrics }
            default     { Write-Log "Unknown suite: $s — skipping" -Level "WARN" }
        }
    }

    # Post-processing
    Generate-Charts
    Generate-Report

    # Summary
    $elapsed = (Get-Date) - $startTime
    $elapsedStr = "{0:mm}m {0:ss}s" -f $elapsed

    Write-Host ""
    Write-Host ("=" * 65) -ForegroundColor Cyan
    Write-Host "  Benchmark Complete" -ForegroundColor Cyan
    Write-Host ("=" * 65) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Duration:  $elapsedStr"
    Write-Host "  Output:    $OutputDir"
    Write-Host "  Log:       $LogFile"
    Write-Host ""
    Write-Host "  $Vendor — $ProjectName v$Version" -ForegroundColor Cyan
    Write-Host ("=" * 65) -ForegroundColor Cyan
}

Main
