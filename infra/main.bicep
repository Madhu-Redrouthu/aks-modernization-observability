targetScope = 'resourceGroup'

@description('Azure region for AKS, ACR, and Log Analytics.')
param location string = resourceGroup().location

@description('Environment name.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Resource naming prefix.')
param projectPrefix string = 'aksmod'

@description('Alert email receiver for Azure Monitor Action Group.')
param alertEmail string = 'rmadhu1909@gmail.com'

var uniqueSuffix = uniqueString(resourceGroup().id)
var acrName = take('${projectPrefix}${environment}acr${uniqueSuffix}', 50)
var tags = {
  Environment: environment
  Project: 'AKS-Modernization-Observability'
  ManagedBy: 'Bicep'
}

// 1. Log Analytics Workspace for Container Insights & KQL
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${projectPrefix}-${environment}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// 2. Azure Container Registry (ACR)
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// 3. Azure Kubernetes Service (AKS) with Autoscaling & Container Insights
resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: '${projectPrefix}-${environment}-aks'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${projectPrefix}-${environment}'
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 2
        minCount: 1
        maxCount: 4
        enableAutoScaling: true
        vmSize: 'Standard_B2s'
        osType: 'Linux'
        mode: 'System'
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
    }
  }
}

// 4. Grant AKS Kubelet Identity AcrPull permission on ACR
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource aksAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// 5. Azure Monitor Action Group & KQL Alert Rule for Pod Restarts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${projectPrefix}-${environment}-ag'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'AKSOpsAG'
    enabled: true
    emailReceivers: [
      {
        name: 'CloudOpsEmail'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource podRestartAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${projectPrefix}-${environment}-pod-restart-alert'
  location: location
  tags: tags
  properties: {
    description: 'Triggers when AKS pod container restarts exceed threshold in 15 minutes.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalytics.id
    ]
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'KubePodInventory | where PodRestartCount > 3 | summarize Restarts = max(PodRestartCount) by Namespace, Name'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

output aksClusterName string = aks.name
output acrLoginServer string = acr.properties.loginServer
output logAnalyticsWorkspaceId string = logAnalytics.id
