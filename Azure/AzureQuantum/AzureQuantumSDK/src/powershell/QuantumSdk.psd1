@{
    RootModule        = "QuantumSdk.psm1"
    ModuleVersion     = "2.0.0"
    GUID              = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    Author            = "Windows-AGI-Mesh Team"
    CompanyName       = "Microsoft"
    Copyright         = "(c) 2026 Microsoft. All rights reserved."
    Description       = "PowerShell module for Windows-AGI-Mesh-QuantumSDK. Provides cmdlets for quantum experiments, LLM inference, MAIA-300 dispatch, Brainwave FPGA routing, Majorana QEC, and Hollow-Core Fiber photonic transport."
    PowerShellVersion = "7.2"
    FunctionsToExport = @(
        "Invoke-QuantumExperiment",
        "Invoke-MajoranaExperiment",
        "Invoke-BatchExperiment",
        "Get-QuantumSdkInfo",
        "Get-QuantumBackends",
        "Get-SamplingStats",
        "Invoke-LLMInference",
        "Invoke-MAIA300Task",
        "Invoke-BrainwaveFPGATask",
        "Send-PhotonicData",
        "Invoke-MajoranaQEC",
        "Get-ResourceEstimate",
        "Invoke-QuantumBenchmark",
        "Start-QuantumTraining",
        "Get-ClusterTopology",
        "Register-QuantumNode",
        "Get-ModelRegistry",
        "Invoke-QuantumFactorize",
        "Get-HardwareStatus",
        "Export-ExperimentResults",
        "Import-ExperimentConfig",
        "Test-QuantumBackend",
        "Measure-QuantumFidelity",
        "Get-MoERoutingStats",
        "Invoke-AlignmentCheck",
        "Get-PhotonicLinkStats",
        "Set-QuantumBackend",
        "Reset-KVCache",
        "Get-WeightShardInfo",
        "Invoke-QuantumSampling"
    )
    CmdletsToExport   = @()
    AliasesToExport   = @(
        "qexp",
        "qinfer",
        "qbench",
        "qfactor",
        "qinfo"
    )
    PrivateData = @{
        PSData = @{
            Tags         = @("Quantum", "LLM", "AI", "Azure", "MAIA300", "Majorana", "FPGA", "PhotonicFiber")
            LicenseUri   = "https://github.com/microsoft/windows-agi-mesh-quantumsdk/blob/main/LICENSE"
            ProjectUri   = "https://github.com/microsoft/windows-agi-mesh-quantumsdk"
            ReleaseNotes = "v2.0.0: Added MAIA-300, Brainwave FPGA, Majorana QEC, HCF photonic, 5B-param LLM support."
        }
    }
}
