@description('Required In workflow we replace createdBy with person that runs pipeline')
param createdBy string = ''
param date string = utcNow('d')
param location string = resourceGroup().location
param vmName string = 't-no1inl-app01'
param vmSize string = 'Standard_D4ds_v5'
param vnetName string = 't-Dedge-network-vnet'
param vnetRG string = 't-Dedge-network-rg'
param subnetName string = 'FrontendSubnet'
param keyvaultname string = 't-Dedge-shared-kv'
param tags object = {
  Description: 'Dedge Appserver innlån/fkkonto/INL'
  Environment: 'Test'
  Owner: 'svein.morten.erikstad@Dedge.no'
  CostCenter: 'Dedge'
  BusinessUnit: 'Dedge'
  CreatedBy: createdBy
  DeploymentDate: date
  DeploymentType: 'Github actions'
}

resource getadminpwd 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyvaultname
  scope: resourceGroup('t-Dedge-rg')
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
    vnetRescourceGroup: vnetRG
    subnetName: subnetName
    // dataDisks: [
    //   {
    //     name: '${vmName}-Data'
    //     diskSizeGB: 2048
    //     lun: 0
    //     createOption: 'Empty'
    //     caching: 'ReadWrite'
    //     writeAcceleratorEnabled: false
    //     managedDisk: {
    //       storageAccountType: 'Premium_LRS'
    //     }
    //   }
    // ]
  }
}

// Add Custom Script Extension to configure regional settings
resource vmCustomScript 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  name: '${vmName}/ConfigureRegionalSettings'
  location: location
  dependsOn: [
    vm
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: '''
        powershell.exe -ExecutionPolicy Bypass -Command "
        Set-WinSystemLocale -SystemLocale en-DK;
        Set-WinUserLanguageList -LanguageList en-US, nb-NO -Force;
        Set-WinUserLanguageList -LanguageList nb-NO -Force;
        Set-Culture en-DK;
        Set-WinHomeLocation -GeoId 0xB1;
        $langList = New-WinUserLanguageList -Language nb-NO;
        $langList[0].InputMethodTips.Clear();
        $langList[0].InputMethodTips.Add('0414:00000414');
        Set-WinUserLanguageList -LanguageList $langList -Force;
        Set-TimeZone -Id 'Central European Standard Time';
        Restart-Computer -Force"
      '''
    }
  }
}
