[CmdletBinding()]
param([string]$Workload = "wsl-zenith")
$ErrorActionPreference = "Stop"
Write-Host "Preparing $Workload for WSL2, WebGPU, WebNN, and WebTransport"
wsl --status
