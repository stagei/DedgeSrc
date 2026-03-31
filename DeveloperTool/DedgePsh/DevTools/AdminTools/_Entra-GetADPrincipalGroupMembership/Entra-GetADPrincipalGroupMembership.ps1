#Import-Module -Name Identity-Handler -Force

$appObjects = @()
$apps = dism /Online /Get-Capabilities
foreach ($app in $apps) {
    $appObjects += [PSCustomObject]@{
        Name = $app.Name
        Type = "Windows Capabilities"
    }
}
$capability = $(dism /Online /Get-Capabilities | Select-String "(Capability Identity :|State :)") | ForEach-Object {
    $lines = $_.Line
    if ($lines -match "Capability Identity : (.+)") {
        $capabilityName = $matches[1]
    }
    elseif ($lines -match "State : (.+)") {
        $state = $matches[1]
        [PSCustomObject]@{
            CapabilityIdentity = $capabilityName
            State = $state
        }
    }
}

Capability Identity : Accessibility.Braille~~~~0.0.1.0
State : Not Present
# Get group memberships for the Administrator account
Get-ADPrincipalGroupMembership -Identity "FKPRDADM"

# Get group memberships and display in a table format
Get-ADPrincipalGroupMembership -Identity "FKPRDADM" | Get-ADGroup -Properties Description | Select Name, Description

