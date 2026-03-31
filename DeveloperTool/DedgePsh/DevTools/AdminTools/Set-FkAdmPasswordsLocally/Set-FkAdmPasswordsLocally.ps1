Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force

# Store passwords for FKDEVADM, FKTSTADM, FKPRDADM
Set-FkAdmPasswordsAsSecureStrings

# Test retrieval for all 3 environments
$servers = @("t-no1fkmdev-db", "t-no1fkmtst-db", "p-no1fkmprd-db")

Write-Host "`n--- SecureString results ---" -ForegroundColor Cyan
foreach ($server in $servers) {
    $secure = Get-FkAdmPasswordForServer -ServerName $server
    Write-Host "$($server): $($secure) (Type: $($secure.GetType().Name))" -ForegroundColor Green
}

Write-Host "`n--- PlainText results ---" -ForegroundColor Cyan
foreach ($server in $servers) {
    $plain = Get-FkAdmPasswordForServer -ServerName $server -AsPlainText
    Write-Host "$($server): $($plain)" -ForegroundColor Green
}