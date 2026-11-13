#Requires -Version 7.2
<#
.SYNOPSIS
    Integration tests for QuantumSdk PowerShell module.
.DESCRIPTION
    Tests all exported cmdlets against the contract defined in QuantumSdk.psd1.
    Runs without requiring QDK or hardware — uses PowerShell simulation fallback.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0
$script:TestResults = @()

function Assert-Equal {
    param($Actual, $Expected, [string]$TestName)
    if ($Actual -eq $Expected) {
        $script:PassCount++
        $script:TestResults += [PSCustomObject]@{ Test=$TestName; Status="PASS"; Detail="" }
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        $script:TestResults += [PSCustomObject]@{ Test=$TestName; Status="FAIL"; Detail="Expected=$Expected Actual=$Actual" }
        Write-Host "  [FAIL] $TestName | Expected=$Expected Actual=$Actual" -ForegroundColor Red
    }
}

function Assert-True {
    param($Condition, [string]$TestName)
    Assert-Equal -Actual $Condition -Expected $true -TestName $TestName
}

function Assert-NotNull {
    param($Value, [string]$TestName)
    if ($null -ne $Value) {
        $script:PassCount++
        $script:TestResults += [PSCustomObject]@{ Test=$TestName; Status="PASS"; Detail="" }
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        $script:TestResults += [PSCustomObject]@{ Test=$TestName; Status="FAIL"; Detail="Value is null" }
        Write-Host "  [FAIL] $TestName | Value is null" -ForegroundColor Red
    }
}

function Assert-InRange {
    param($Value, $Min, $Max, [string]$TestName)
    if ($Value -ge $Min -and $Value -le $Max) {
        $script:PassCount++
        $script:TestResults += [PSCustomObject]@{ Test=$TestName; Status="PASS"; Detail="" }
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        $script:TestResults += [PSCustomObject]@{ Test=$TestName; Status="FAIL"; Detail="Value=$Value not in [$Min,$Max]" }
        Write-Host "  [FAIL] $TestName | Value=$Value not in [$Min,$Max]" -ForegroundColor Red
    }
}

# ─── Load module ──────────────────────────────────────────────────────────────
$ModulePath = Join-Path $PSScriptRoot ".." ".." ".." "src" "powershell" "QuantumSdk.psd1"
$ModulePath = (Resolve-Path $ModulePath -ErrorAction SilentlyContinue)?.Path

if ($ModulePath -and (Test-Path $ModulePath)) {
    Import-Module $ModulePath -Force -ErrorAction SilentlyContinue
    Write-Host "Module loaded from: $ModulePath" -ForegroundColor Cyan
} else {
    Write-Host "Module not found at expected path, testing inline..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Windows-AGI-Mesh-QuantumSDK PowerShell Test Suite   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── Test: Get-QuantumSdkInfo ─────────────────────────────────────────────────
Write-Host "▶ Testing Get-QuantumSdkInfo..." -ForegroundColor Yellow
try {
    $info = Get-QuantumSdkInfo
    Assert-NotNull $info "Get-QuantumSdkInfo returns object"
    Assert-Equal $info.ModuleName "Windows-AGI-Mesh-QuantumSDK" "ModuleName correct"
    Assert-NotNull $info.Version "Version present"
    Assert-NotNull $info.Hardware "Hardware section present"
    Assert-NotNull $info.Hardware.Majorana1 "Majorana1 hardware info present"
    Assert-Equal $info.Hardware.Majorana1.PhysicalQubits 8 "Majorana1 physical qubits = 8"
    Assert-Equal $info.Hardware.MAIA300.ChipletsPerRack 96 "MAIA300 chiplets = 96"
    Assert-Equal $info.Hardware.MAIA300.HBM4CapacityGB 288 "MAIA300 HBM4 = 288 GB"
    Assert-Equal $info.Hardware.BrainwaveFPGA.MACUnits 96000 "Brainwave MAC units = 96000"
    Assert-Equal $info.Hardware.HollowCoreFiber.LatencyReductionPct 47.0 "HCF latency reduction = 47%"
    Assert-Equal $info.Hardware.QuantinuumHelios.LogicalQubits 48 "Helios logical qubits = 48"
    Assert-Equal $info.Hardware.IBMNighthawk.Qubits 120 "Nighthawk qubits = 120"
    Assert-Equal $info.LLMModel.Parameters "5B" "LLM parameters = 5B"
    Assert-Equal $info.LLMModel.NumLayers 36 "LLM layers = 36"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-QuantumSdkInfo threw: $_" -ForegroundColor Red
}

# ─── Test: Get-QuantumBackends ────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Get-QuantumBackends..." -ForegroundColor Yellow
try {
    $backends = Get-QuantumBackends
    Assert-True ($backends.Count -ge 10) "At least 10 backends listed"
    $majorana = $backends | Where-Object { $_.BackendId -eq "microsoft.majorana-1" }
    Assert-NotNull $majorana "Majorana-1 backend present"
    Assert-True $majorana.IsTopological "Majorana-1 is topological"
    Assert-Equal $majorana.Qubits 8 "Majorana-1 has 8 qubits"
    $helios = $backends | Where-Object { $_.BackendId -eq "quantinuum.helios" }
    Assert-NotNull $helios "Quantinuum Helios present"
    Assert-Equal $helios.LogicalQubits 48 "Helios has 48 logical qubits"
    $nighthawk = $backends | Where-Object { $_.BackendId -eq "ibm.nighthawk-r2" }
    Assert-NotNull $nighthawk "IBM Nighthawk r2 present"
    Assert-Equal $nighthawk.Qubits 120 "Nighthawk has 120 qubits"
    $sims = Get-QuantumBackends -IncludeSimulators
    Assert-True ($sims.Count -gt $backends.Count) "IncludeSimulators adds more backends"
    $topo = Get-QuantumBackends -TopologicalOnly
    Assert-True ($topo.Count -ge 1) "At least 1 topological backend"
    Assert-True ($topo | ForEach-Object { $_.IsTopological } | Where-Object { $_ -eq $false } | Measure-Object).Count -eq 0 "All topological-only results are topological"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-QuantumBackends threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-QuantumExperiment ──────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-QuantumExperiment..." -ForegroundColor Yellow
try {
    $result = Invoke-QuantumExperiment -Qubits 4 -Ancillas 2 -ThetaZ 0.5 -ThetaY 0.3 -Shots 100
    Assert-NotNull $result "Experiment returns result"
    Assert-InRange $result.Mean 0.0 1.0 "Mean in [0,1]"
    Assert-True ($result.Deviation -ge 0.0) "Deviation >= 0"
    Assert-True ($result.ShotCount -gt 0) "ShotCount > 0"
    Assert-True ($result.QubitCount -eq 4) "QubitCount = 4"
    Assert-True ($result.AncillaCount -eq 2) "AncillaCount = 2"
    Assert-NotNull $result.Backend "Backend present"
    Assert-NotNull $result.TimestampUtc "Timestamp present"
    Assert-True ($result.AboveThreshold -eq ($result.Mean -gt 0.5)) "AboveThreshold consistent with Mean"
    Assert-True ($result.SNR -ge 0.0) "SNR >= 0"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-QuantumExperiment threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-MajoranaExperiment ─────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-MajoranaExperiment..." -ForegroundColor Yellow
try {
    $result = Invoke-MajoranaExperiment -Qubits 4 -Ancillas 2 -ThetaZ 0.5 -ThetaY 0.3 -Shots 50 -BraidDepth 2
    Assert-NotNull $result "Majorana experiment returns result"
    Assert-InRange $result.Mean 0.0 1.0 "Majorana mean in [0,1]"
    Assert-True ($result.Deviation -ge 0.0) "Majorana deviation >= 0"
    Assert-Equal $result.QECCycles 2 "QEC cycles = braid depth"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-MajoranaExperiment threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-MAIA300Task ─────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-MAIA300Task..." -ForegroundColor Yellow
try {
    $result = Invoke-MAIA300Task -BatchSize 4 -SeqLen 512 -HiddenDim 4096 -LayerStart 0 -LayerEnd 9
    Assert-NotNull $result "MAIA300 task returns result"
    Assert-True ($result.EstimatedMemoryGB -gt 0) "Memory estimate > 0"
    Assert-True ($result.EstimatedLatencyMs -gt 0) "Latency estimate > 0"
    Assert-Equal $result.HBM4BandwidthTBs 18.0 "HBM4 bandwidth = 18 TB/s"
    Assert-Equal $result.ComputeTFLOPS_FP8 6400.0 "FP8 TFLOPS = 6400"
    Assert-True $result.IsSuccessful "Task is successful"
    $spec = Invoke-MAIA300Task -BatchSize 1 -SeqLen 256 -UseSpeculativeDecoding -SpecDraftTokens 5
    Assert-True ($spec.EstimatedLatencyMs -lt (Invoke-MAIA300Task -BatchSize 1 -SeqLen 256).EstimatedLatencyMs) "Speculative decoding reduces latency"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-MAIA300Task threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-BrainwaveFPGATask ──────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-BrainwaveFPGATask..." -ForegroundColor Yellow
try {
    $result = Invoke-BrainwaveFPGATask -LayerType attention -SeqLen 512 -HiddenDim 4096
    Assert-NotNull $result "Brainwave task returns result"
    Assert-True ($result.EstimatedLatencyMs -gt 0) "Latency > 0"
    Assert-True ($result.ThroughputTFLOPS -gt 0) "Throughput > 0"
    Assert-True ($result.ThroughputTFLOPS -le 35.0) "Throughput <= 35 TFLOPS (peak)"
    Assert-Equal $result.FPGAModel "Intel Stratix 10 280" "FPGA model correct"
    Assert-Equal $result.MACUnits 96000 "MAC units = 96,000"
    Assert-True $result.IsSuccessful "Task successful"
    Assert-True ($result.SpeedupVsGPU -gt 1.0) "Speedup vs GPU > 1x"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-BrainwaveFPGATask threw: $_" -ForegroundColor Red
}

# ─── Test: Send-PhotonicData ──────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Send-PhotonicData..." -ForegroundColor Yellow
try {
    $result = Send-PhotonicData -DataKB 1024 -FiberLengthKm 100.0
    Assert-NotNull $result "Photonic transport returns result"
    Assert-True ($result.TransportLatencyUs -gt 0) "Transport latency > 0"
    Assert-True ($result.TransportLatencyUs -lt $result.SMFLatencyUs) "HCF faster than SMF"
    Assert-InRange $result.LatencyImprovementPct 40.0 55.0 "Latency improvement ~47%"
    Assert-Equal $result.BandwidthTbps 100.0 "Bandwidth = 100 Tbps"
    Assert-Equal $result.Manufacturer "Heraeus Covantics" "Manufacturer correct"
    Assert-True $result.IsSuccessful "Transport successful"
    $compute = Send-PhotonicData -DataKB 512 -InTransitCompute
    Assert-True ($compute.ComputeLatencyUs -gt 0) "In-transit compute latency > 0"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Send-PhotonicData threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-MajoranaQEC ─────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-MajoranaQEC..." -ForegroundColor Yellow
try {
    $result = Invoke-MajoranaQEC -XSyndrome @(0,1,0,1) -ZSyndrome @(0,0,1,0) -CodeDistance 3
    Assert-NotNull $result "QEC returns result"
    Assert-Equal $result.CodeDistance 3 "Code distance = 3"
    Assert-True ($result.LogicalErrorRate -lt 0.001) "Logical error rate < 0.1%"
    Assert-Equal $result.CorrectionOp "MWPM" "Correction op = MWPM"
    Assert-Equal $result.OverheadRatio "2:1" "Overhead ratio = 2:1"
    Assert-Equal $result.TopoconductorMaterial "InAs/Al" "Topoconductor material correct"
    Assert-True $result.IsCorrectable "Syndrome is correctable"
    $trivial = Invoke-MajoranaQEC -XSyndrome @(0,0,0,0) -ZSyndrome @(0,0,0,0)
    Assert-True $trivial.IsTrivial "Zero syndrome is trivial"
    Assert-Equal $trivial.SyndromeWeight 0 "Trivial syndrome weight = 0"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-MajoranaQEC threw: $_" -ForegroundColor Red
}

# ─── Test: Get-ResourceEstimate ───────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Get-ResourceEstimate..." -ForegroundColor Yellow
try {
    $est = Get-ResourceEstimate -Algorithm "RSA-2048" -LogicalQubits 4000 -Backend "microsoft.majorana-1"
    Assert-NotNull $est "Resource estimate returns result"
    Assert-Equal $est.Algorithm "RSA-2048" "Algorithm name correct"
    Assert-Equal $est.LogicalQubits 4000 "Logical qubits = 4000"
    Assert-True ($est.PhysicalQubits -ge $est.LogicalQubits) "Physical >= logical qubits"
    Assert-Equal $est.OverheadRatio "2:1" "Majorana overhead = 2:1"
    Assert-Equal $est.CodeDistance 3 "Majorana code distance = 3"
    Assert-True ($est.LogicalErrorRate -lt 0.001) "Logical error rate < 0.1%"
    Assert-True ($est.RuntimeSeconds -gt 0) "Runtime > 0"
    $helios_est = Get-ResourceEstimate -Algorithm "Chemistry" -LogicalQubits 100 -Backend "quantinuum.helios"
    Assert-Equal $helios_est.OverheadRatio "2:1" "Helios overhead = 2:1"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-ResourceEstimate threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-QuantumFactorize ────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-QuantumFactorize..." -ForegroundColor Yellow
try {
    $r15 = Invoke-QuantumFactorize -Number 15
    Assert-NotNull $r15 "Factorize 15 returns result"
    Assert-True ($r15.Factor1 * $r15.Factor2 -eq 15) "15 = f1 * f2"
    Assert-True ($r15.Factor1 -gt 1) "Factor1 > 1"
    Assert-True ($r15.Factor2 -gt 1) "Factor2 > 1"
    Assert-True $r15.Verification "Verification passes"
    $r17 = Invoke-QuantumFactorize -Number 17
    Assert-True $r17.IsPrime "17 is prime"
    $r21 = Invoke-QuantumFactorize -Number 21
    Assert-True ($r21.Factor1 * $r21.Factor2 -eq 21) "21 = f1 * f2"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-QuantumFactorize threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-QuantumSampling ─────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-QuantumSampling..." -ForegroundColor Yellow
try {
    $logits = @(1.2, 0.8, 2.1, 0.3, 1.5)
    $result = Invoke-QuantumSampling -Logits $logits -Temperature 0.7 -TopK 3
    Assert-NotNull $result "Sampling returns result"
    Assert-InRange $result.ChosenTokenId 0 4 "Token ID in vocab range"
    Assert-InRange $result.ChosenProb 0.0 1.0 "Probability in [0,1]"
    Assert-True ($result.EntropyBits -ge 0.0) "Entropy >= 0"
    Assert-Equal $result.VocabSize 5 "Vocab size = 5"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-QuantumSampling threw: $_" -ForegroundColor Red
}

# ─── Test: Get-HardwareStatus ─────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Get-HardwareStatus..." -ForegroundColor Yellow
try {
    $status = Get-HardwareStatus
    Assert-NotNull $status "Hardware status returns object"
    Assert-NotNull $status.MAIA300 "MAIA300 status present"
    Assert-NotNull $status.BrainwaveFPGA "Brainwave status present"
    Assert-NotNull $status.Majorana1 "Majorana1 status present"
    Assert-NotNull $status.HollowCoreFiber "HCF status present"
    Assert-Equal $status.MAIA300.Status "Online" "MAIA300 online"
    Assert-Equal $status.Majorana1.PhysicalQubits 8 "Majorana1 physical qubits = 8"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-HardwareStatus threw: $_" -ForegroundColor Red
}

# ─── Test: Get-WeightShardInfo ────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Get-WeightShardInfo..." -ForegroundColor Yellow
try {
    $shards = Get-WeightShardInfo -NumShards 8
    Assert-Equal $shards.Count 8 "8 shards returned"
    $total_layers = ($shards | ForEach-Object { $_.LayerCount } | Measure-Object -Sum).Sum
    Assert-Equal $total_layers 36 "Total layers = 36"
    foreach ($shard in $shards) {
        Assert-True ($shard.SizeGB_BF16 -gt 0) "Shard BF16 size > 0"
        Assert-True ($shard.SizeGB_INT4 -lt $shard.SizeGB_BF16) "INT4 smaller than BF16"
    }
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-WeightShardInfo threw: $_" -ForegroundColor Red
}

# ─── Test: Get-MoERoutingStats ────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Get-MoERoutingStats..." -ForegroundColor Yellow
try {
    $stats = Get-MoERoutingStats -NumExperts 8 -TopK 2 -TokenCount 1000
    Assert-Equal $stats.NumExperts 8 "NumExperts = 8"
    Assert-Equal $stats.TopK 2 "TopK = 2"
    Assert-Equal $stats.ExpertUtilization.Count 8 "8 expert utilization values"
    Assert-True ($stats.LoadBalanceLoss -ge 0.0) "Load balance loss >= 0"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-MoERoutingStats threw: $_" -ForegroundColor Red
}

# ─── Test: Invoke-AlignmentCheck ─────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Invoke-AlignmentCheck..." -ForegroundColor Yellow
try {
    $result = Invoke-AlignmentCheck -Prompt "Explain quantum computing"
    Assert-NotNull $result "Alignment check returns result"
    Assert-True $result.IsSafe "Safe prompt is safe"
    Assert-InRange $result.HarmScore 0.0 1.0 "Harm score in [0,1]"
    Assert-NotNull $result.PolicyVersion "Policy version present"
    Assert-True ($result.CheckLatencyMs -ge 0.0) "Check latency >= 0"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Invoke-AlignmentCheck threw: $_" -ForegroundColor Red
}

# ─── Test: Set-QuantumBackend ─────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Set-QuantumBackend..." -ForegroundColor Yellow
try {
    Set-QuantumBackend -Backend "microsoft.majorana-1"
    $result = Invoke-QuantumExperiment -Qubits 2 -ThetaZ 0.5 -ThetaY 0.3 -Shots 10
    Assert-NotNull $result "Experiment runs after backend change"
    Set-QuantumBackend -Backend "microsoft.simulator.full-state"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Set-QuantumBackend threw: $_" -ForegroundColor Red
}

# ─── Test: Get-ModelRegistry ──────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Get-ModelRegistry..." -ForegroundColor Yellow
try {
    $models = Get-ModelRegistry
    Assert-True ($models.Count -ge 1) "At least 1 model in registry"
    $m = $models[0]
    Assert-Equal $m.Name "windows-agi-mesh-5b" "Model name correct"
    Assert-Equal $m.Parameters "5B" "Parameters = 5B"
    Assert-True $m.IsActive "Model is active"
    Assert-True ($m.SizeGB_BF16 -gt 5.0) "BF16 size > 5 GB"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-ModelRegistry threw: $_" -ForegroundColor Red
}

# ─── Test: Get-PhotonicLinkStats ──────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Testing Get-PhotonicLinkStats..." -ForegroundColor Yellow
try {
    $links = Get-PhotonicLinkStats
    Assert-True ($links.Count -ge 1) "At least 1 photonic link"
    $link = $links[0]
    Assert-Equal $link.ImprovementPct 47.0 "HCF improvement = 47%"
    Assert-Equal $link.BandwidthTbps 100.0 "Bandwidth = 100 Tbps"
    Assert-Equal $link.Manufacturer "Heraeus Covantics" "Manufacturer correct"
    Assert-True $link.IsActive "Link is active"
    Assert-True $link.InTransitCompute "In-transit compute enabled"
} catch {
    $script:FailCount++
    Write-Host "  [FAIL] Get-PhotonicLinkStats threw: $_" -ForegroundColor Red
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $script:PassCount + $script:FailCount + $script:SkipCount
Write-Host "  Total:  $total" -ForegroundColor White
Write-Host "  Passed: $($script:PassCount)" -ForegroundColor Green
Write-Host "  Failed: $($script:FailCount)" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped: $($script:SkipCount)" -ForegroundColor Yellow
$passRate = if ($total -gt 0) { [math]::Round($script:PassCount / $total * 100, 1) } else { 0.0 }
Write-Host "  Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })
Write-Host ""

if ($script:FailCount -gt 0) {
    Write-Host "Failed tests:" -ForegroundColor Red
    $script:TestResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Detail)" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
