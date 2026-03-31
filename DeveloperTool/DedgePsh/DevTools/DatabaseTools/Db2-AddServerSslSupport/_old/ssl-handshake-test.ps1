
param (
    [Parameter(Mandatory = $true)]
    [string]$ServerName,
    [Parameter(Mandatory = $true)]
    [int]$Port
)
Import-Module GlobalFunctions -Force -ErrorAction Stop

try {
    $tcp = New-Object System.Net.Sockets.TcpClient; $tcp.Connect($ServerName, $Port)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream())
    $ssl.AuthenticateAsClient($ServerName)
    Write-LogMessage "SSL SUCCESS: $($ServerName):$($Port)" -Level INFO
    $ssl.Close()
    $tcp.Close()
}
catch {
    Write-LogMessage "SSL FAILED: $($_.Exception.Message)" -Level WARN
}

