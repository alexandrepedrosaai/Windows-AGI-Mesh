// =============================================================================
// Windows AGI Benchmark Lab — Azure Bicep Infrastructure
// Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
// =============================================================================
// Deploys:
//   - Resource Group
//   - Azure ML Workspace
//   - Azure Container Registry
//   - Azure Storage Account (benchmark artifacts)
//   - Azure Key Vault
//   - Azure Monitor / Log Analytics
//   - Azure Container Instances (benchmark runners)
//   - Azure Functions (trigger + publisher)
//   - Virtual Network
// =============================================================================

targetScope = 'subscription'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
@description('Azure region for all resources')
param location string = 'eastus'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name prefix')
param projectName string = 'agi-bench'

@description('GPU SKU for compute clusters')
@allowed(['Standard_NC6s_v3', 'Standard_NC12s_v3', 'Standard_NC24s_v3', 'Standard_ND40rs_v2'])
param gpuSku string = 'Standard_NC6s_v3'

@description('Number of GPU compute nodes')
@minValue(0)
@maxValue(10)
param gpuNodeCount int = 1

@description('Enable Azure ML workspace')
param enableAzureML bool = true

@description('Enable Azure Container Registry')
param enableACR bool = true

@description('Tags for all resources')
param tags object = {
  Project: 'Windows-AGI-Benchmark'
  Vendor: 'Microsoft Corporation'
  License: 'Exclusive'
  Environment: environment
  ManagedBy: 'Bicep'
}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------
var resourceGroupName = 'rg-${projectName}-${environment}'
var prefix = '${projectName}-${environment}'
var storageAccountName = replace('st${projectName}${environment}', '-', '')
var keyVaultName = 'kv-${prefix}'
var logAnalyticsName = 'log-${prefix}'
var appInsightsName = 'appi-${prefix}'
var acrName = replace('acr${projectName}${environment}', '-', '')
var mlWorkspaceName = 'mlw-${prefix}'
var functionAppName = 'func-${prefix}'
var storageAccountNameFunc = replace('stfunc${projectName}${environment}', '-', '')
var vnetName = 'vnet-${prefix}'
var subnetName = 'snet-${prefix}-compute'

// ---------------------------------------------------------------------------
// Resource Group
// ---------------------------------------------------------------------------
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// Virtual Network
// ---------------------------------------------------------------------------
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  scope: resourceGroup
  params: {
    vnetName: vnetName
    location: location
    tags: tags
    addressPrefix: '10.0.0.0/16'
    subnetName: subnetName
    subnetPrefix: '10.0.1.0/24'
  }
}

// ---------------------------------------------------------------------------
// Storage Account (Benchmark Artifacts)
// ---------------------------------------------------------------------------
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  scope: resourceGroup
  params: {
    storageAccountName: storageAccountName
    location: location
    tags: tags
    sku: 'Standard_LRS'
    containers: [
      'benchmark-results'
      'benchmark-reports'
      'benchmark-charts'
      'model-artifacts'
      'logs'
    ]
  }
}

// ---------------------------------------------------------------------------
// Key Vault
// ---------------------------------------------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  scope: resourceGroup
  params: {
    keyVaultName: keyVaultName
    location: location
    tags: tags
    sku: 'standard'
  }
}

// ---------------------------------------------------------------------------
// Log Analytics Workspace
// ---------------------------------------------------------------------------
module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'loganalytics-deployment'
  scope: resourceGroup
  params: {
    workspaceName: logAnalyticsName
    location: location
    tags: tags
    retentionDays: 90
    sku: 'PerGB2018'
  }
}

// ---------------------------------------------------------------------------
// Application Insights
// ---------------------------------------------------------------------------
module appInsights 'modules/appinsights.bicep' = {
  name: 'appinsights-deployment'
  scope: resourceGroup
  params: {
    appInsightsName: appInsightsName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// ---------------------------------------------------------------------------
// Azure Container Registry
// ---------------------------------------------------------------------------
module acr 'modules/acr.bicep' = if (enableACR) {
  name: 'acr-deployment'
  scope: resourceGroup
  params: {
    acrName: acrName
    location: location
    tags: tags
    sku: 'Standard'
    adminUserEnabled: false
  }
}

// ---------------------------------------------------------------------------
// Azure ML Workspace
// ---------------------------------------------------------------------------
module azureML 'modules/azureml.bicep' = if (enableAzureML) {
  name: 'azureml-deployment'
  scope: resourceGroup
  params: {
    workspaceName: mlWorkspaceName
    location: location
    tags: tags
    storageAccountId: storage.outputs.storageAccountId
    keyVaultId: keyVault.outputs.keyVaultId
    appInsightsId: appInsights.outputs.appInsightsId
    acrId: enableACR ? acr.outputs.acrId : ''
    gpuSku: gpuSku
    gpuNodeCount: gpuNodeCount
  }
}

// ---------------------------------------------------------------------------
// Azure Functions (Benchmark Trigger)
// ---------------------------------------------------------------------------
module functionApp 'modules/functions.bicep' = {
  name: 'functions-deployment'
  scope: resourceGroup
  params: {
    functionAppName: functionAppName
    location: location
    tags: tags
    storageAccountName: storageAccountNameFunc
    appInsightsConnectionString: appInsights.outputs.connectionString
    environmentVariables: {
      BENCHMARK_STORAGE_ACCOUNT: storageAccountName
      BENCHMARK_CONTAINER: 'benchmark-results'
      AZURE_ML_WORKSPACE: mlWorkspaceName
      AZURE_ML_RESOURCE_GROUP: resourceGroupName
      PROJECT_NAME: 'Windows-AGI-Benchmark'
      VENDOR: 'Microsoft Corporation'
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output resourceGroupName string = resourceGroupName
output storageAccountName string = storageAccountName
output storageAccountId string = storage.outputs.storageAccountId
output keyVaultName string = keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output appInsightsConnectionString string = appInsights.outputs.connectionString
output acrLoginServer string = enableACR ? acr.outputs.loginServer : ''
output mlWorkspaceName string = enableAzureML ? azureML.outputs.workspaceName : ''
output functionAppName string = functionApp.outputs.functionAppName
output functionAppUrl string = functionApp.outputs.functionAppUrl