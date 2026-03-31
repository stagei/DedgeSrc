@description('Required In workflow we replace createdBy with person that runs pipeline')
param createdBy string = ''
param date string = utcNow('d')
param location string = resourceGroup().location
param vmName string = 'p-no1fkmprd-app'
param vmSize string= 'Standard_D4ds_v5'
param vnetName string= 'p-Dedge-network-vnet'
param vnetRG string= 'p-Dedge-network-rg'
param subnetName string= 'FrontendSubnet'
param keyvaultname string='p-Dedge-shared-kv'
param tags object = {
  Description: 'Dedge Applikasjonsserver for Produksjons-miljø'
  Environment: 'Production'
  Owner: 'svein.morten.erikstad@Dedge.no'
  CostCenter: 'Dedge'
  BusinessUnit: 'Dedge'
  CreatedBy: createdBy
  DeploymentDate: date
  DeploymentType: 'Github actions'
}
 
resource getadminpwd 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyvaultname
  scope: resourceGroup('p-Dedge-rg')
}
 
module vm 'br:fkbicepmodules.azurecr.io/bicep/custom/virtualmachinewithnic:v3.0.0' = {
  name: vmName
  params: {
    location: location
    domainjoin: true
    adminpassword: getadminpwd.getSecret('adm-local')
    adminUsername: 'adm-local'
    createdatadisk: false
    imagereference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2025-Datacenter'
      version: 'latest'
    }
 
    tags: tags
 
    virtualMachineName: vmName
    vmSize: vmSize
    vnetName: vnetName
    vnetRescourceGroup:vnetRG
    subnetName: subnetName
 
  //   dataDisks: [
  //     {
  //       name: '${vmName}-DataE'
  //       diskSizeGB: 1000
  //       lun: 0
  //       createOption: 'Empty'
  //       caching: 'ReadWrite'
  //       writeAcceleratorEnabled: false
  //       managedDisk: {
  //         storageAccountType: 'Premium_LRS'
  //       }
  //     }
  //  ]
  }
} 
