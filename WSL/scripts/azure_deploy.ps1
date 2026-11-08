[CmdletBinding()]
param([string]$ResourceGroup = "rg-wsl-zenith", [string]$Location = "eastus")
$ErrorActionPreference = "Stop"
Write-Host "Deployment preview only: $ResourceGroup in $Location"
Write-Host "Use a protected Azure environment and OIDC credentials to execute deployment."
