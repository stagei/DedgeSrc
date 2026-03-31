param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Platform", "Computer")]
    [string]$ReportType = "Computer",
    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Randomize10")]
    [string]$TestAllPortRanges = "Randomize10"

)
# Port Check Tool for File Sharing and DB2 Connectivity
Import-Module Export-Array -Force
Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force

#-------------------------------------------------------------------------------------------------
# Main script
#-------------------------------------------------------------------------------------------------
if ($ReportType -ne "Computer") {
    Write-LogMessage "ReportType Platform is deprecated. Please use ReportType Computer instead." -Level WARN
    exit 1
}
$ComputerName = $env:COMPUTERNAME
$serverConfig = Get-ServerConfiguration -ComputerName $ComputerName -ReportAllConsumerDetails $true -MatchActiveDatabases $true

# Export server configuration to JSON file
# $outputPath = $(Join-Path $(Get-ApplicationDataPath) "$($ComputerName)_ServerConfig_$(Get-Date -f yyyyMMddHHmmss).json").ToString()
# $serverConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Force
# Write-Host "Exported server configuration to: $outputPath" -ForegroundColor Green

# Create heading with padding
$headings = @(
    "Port Status".PadRight(26),
    "Client Hostname/IP".PadRight(50),
    "Server Hostname/IP".PadRight(50),
    "Port".PadRight(5),
    "Service Type".PadRight(30),
    "Protocol".PadRight(10),
    "Latency".PadRight(10)
)
# Get total length of headings
$totalLength = ($headings | Measure-Object -Sum -Property Length -ErrorAction Stop).Sum + ($headings.Count - 1) * 3 # Add length of " | " separators

$platform = Get-CurrentComputerPlatform
if ($ReportType -eq "Platform") {
    $title = "Dedge Platform Port Verification for platform $platform"
}
else {
    $title = "Dedge Computer Port Verification for computer $($env:COMPUTERNAME.ToLower())"
}
Write-Host ("=" * $totalLength)
Write-Host $(" " + $title)
Write-Host ("-" * $totalLength)
Write-Host ($headings -join " | ")
Write-Host ("=" * $totalLength)

# Create results array to store both display content and raw results
$displayResults = @()
$rawResults = @()

# Build array of all port tests needed
$allTests = @()
foreach ($server in $serverConfig) {
    # Extract port information
    $portInfo = [PSCustomObject]@{
        Icon                  = $null # Will be set later based on port range check
        ProviderHost          = $server.ProviderHost
        ConsumerHost          = $server.ConsumerHost
        Protocol              = $server.Protocol
        Port                  = $server.PortStart
        InternetAccess        = $server.InternetAccess
        IsPortRange           = $server.IsPortRange
        PortDescription       = $server.PortDescription
        PortGroupId           = $server.PortGroupId
        PortGroupDescription  = $server.PortGroupDescription
        PortCompactTitle      = "" # Will be set later based on port range check
        ProviderHostIpAddress = "" # Will be set later based on port range check
        PortTestResultStatus  = "" # Will be set later based on port range check
        PortTestResultLatency = "" # Will be set later based on port range check

    }

    if (($TestAllPortRanges -eq "All" -or ($TestAllPortRanges -eq "Randomize10" -and $($server.PortEnd - $server.PortStart) -le 10)) -and $server.IsPortRange) {

        for ($i = $server.PortStart; $i -le $server.PortEnd; $i++) {
            # Copy $portInfo to $portInfoCopy
            $portInfoCopy = [PSCustomObject]@{
                Icon                  = $portInfo.Icon
                ProviderHost          = $portInfo.ProviderHost
                ConsumerHost          = $portInfo.ConsumerHost
                Protocol             = $portInfo.Protocol
                Port                 = $i
                InternetAccess       = $portInfo.InternetAccess
                IsPortRange          = $portInfo.IsPortRange
                PortDescription      = $portInfo.PortDescription
                PortGroupId          = $portInfo.PortGroupId
                PortGroupDescription = $portInfo.PortGroupDescription
                PortCompactTitle     = $portInfo.PortCompactTitle
                ProviderHostIpAddress = $portInfo.ProviderHostIpAddress
                PortTestResultStatus = $portInfo.PortTestResultStatus
                PortTestResultLatency = $portInfo.PortTestResultLatency
            }
            $allTests += $portInfoCopy
        }
    }
    elseif ($TestAllPortRanges -eq "Randomize10" -and $server.IsPortRange) {
        $server.PortStart++
        for ($i = 0; $i -lt 10; $i++) {
            $randomPort = Get-Random -Minimum $server.PortStart -Maximum $server.PortEnd
            $portInfoCopy = [PSCustomObject]@{
                Icon                  = $portInfo.Icon
                ProviderHost          = $portInfo.ProviderHost
                ConsumerHost          = $portInfo.ConsumerHost
                Protocol             = $portInfo.Protocol
                Port                 = $randomPort
                InternetAccess       = $portInfo.InternetAccess
                IsPortRange          = $portInfo.IsPortRange
                PortDescription      = $($portInfo.PortDescription + " (Randomized)")
                PortGroupId          = $portInfo.PortGroupId
                PortGroupDescription = $portInfo.PortGroupDescription
                PortCompactTitle     = $portInfo.PortCompactTitle
                ProviderHostIpAddress = $portInfo.ProviderHostIpAddress
                PortTestResultStatus = $portInfo.PortTestResultStatus
                PortTestResultLatency = $portInfo.PortTestResultLatency
            }
            $allTests += $portInfoCopy
        }
    }
    else {
        $portInfoCopy = [PSCustomObject]@{
            Icon                  = $portInfo.Icon
            ProviderHost          = $portInfo.ProviderHost
            ConsumerHost          = $portInfo.ConsumerHost
            Protocol             = $portInfo.Protocol
            Port                 = $server.PortStart
            InternetAccess       = $portInfo.InternetAccess
            IsPortRange          = $portInfo.IsPortRange
            PortDescription      = $portInfo.PortDescription
            PortGroupId          = $portInfo.PortGroupId
            PortGroupDescription = $portInfo.PortGroupDescription
            PortCompactTitle     = $portInfo.PortCompactTitle
            ProviderHostIpAddress = $portInfo.ProviderHostIpAddress
            PortTestResultStatus = $portInfo.PortTestResultStatus
            PortTestResultLatency = $portInfo.PortTestResultLatency
        }
        $allTests += $portInfoCopy

        $portInfoCopy = [PSCustomObject]@{
            Icon                  = $portInfo.Icon
            ProviderHost          = $portInfo.ProviderHost
            ConsumerHost          = $portInfo.ConsumerHost
            Protocol             = $portInfo.Protocol
            Port                 = $server.PortEnd
            InternetAccess       = $portInfo.InternetAccess
            IsPortRange          = $portInfo.IsPortRange
            PortDescription      = $portInfo.PortDescription
            PortGroupId          = $portInfo.PortGroupId
            PortGroupDescription = $portInfo.PortGroupDescription
            PortCompactTitle     = $portInfo.PortCompactTitle
            ProviderHostIpAddress = $portInfo.ProviderHostIpAddress
            PortTestResultStatus = $portInfo.PortTestResultStatus
            PortTestResultLatency = $portInfo.PortTestResultLatency
        }
        $allTests += $portInfoCopy
    }
}

$allTests = $allTests | Sort-Object -Property PortGroupId, ProviderHost, Port

$rawResults = @()
$displayResults = @()
$localIpAddress = Get-ComputerIpAddress -ComputerName $env:COMPUTERNAME -Quiet $true

foreach ($test in $allTests) {
    if ($test.Protocol -ne "TCP") {
        continue
    }

    if ([string]::IsNullOrEmpty($test.Port)) {
        continue
    }
    $progress = @{
        Activity        = "Testing port connectivity"
        Status          = "Testing $($test.ProviderHost):$($test.Port)"
        PercentComplete = (([array]::IndexOf($allTests, $test) + 1) / $allTests.Count) * 100
    }
    Write-Progress @progress

    $result = Test-PortConnectivity -Server $test.ProviderHost -Port $test.Port -Timeout 1000

    $matchResult = $test.ProviderHost -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"
    if (-not $matchResult) {
        $test.ProviderHostIpAddress = Get-ComputerIpAddress -ComputerName $test.ProviderHost -Quiet $true
    }
    else {
        $test.ProviderHostIpAddress = $test.ProviderHost
        $test.ProviderHost = $(Get-HostDnsAddress -HostIpAddress $test.ProviderHost -Quiet $true) ?? "N/A"
    }
    $icon = if ($result.Status -eq "Open") { [char]0x2705 } else { [char]0x274C }

    # Add icon to $test
    $test.Icon = $icon
    $test.PortTestResultStatus = $result.Status
    $test.PortTestResultLatency = $result.Latency

    $portString = [string]$test.Port.ToString().PadLeft(5)
    $statusString = "$icon $($result.Status)".PadRight(25)

    $consoleOutput = @(
        $statusString.Substring(0, [Math]::Min($statusString.Length, 26)),
        $($localIpAddress + "/" + $env:COMPUTERNAME).Substring(0, [Math]::Min(($localIpAddress + "/" + $env:COMPUTERNAME).Length, 50)).PadRight(50),
        $($test.ProviderHost.ToLower() + "/" + $test.ProviderHostIpAddress).Substring(0, [Math]::Min(($test.ProviderHost.ToLower() + "/" + $test.ProviderHostIpAddress).Length, 50)).PadRight(50),
        $portString.Substring(0, [Math]::Min($portString.Length, 5)).PadRight(5),
        $test.PortDescription.Substring(0, [Math]::Min($test.PortDescription.Length, 30)).PadRight(30),
        $test.Protocol.Substring(0, [Math]::Min($test.Protocol.Length, 10)).PadRight(10),
        $result.Latency.Substring(0, [Math]::Min($result.Latency.Length, 10)).PadRight(10)
    )

    # Format content with padding for display
    Write-Host ($consoleOutput -join " | ")

    $contentSeperate = [PSCustomObject]@{
        Icon            = $icon
        Status          = $result.Status
        Source          = $env:COMPUTERNAME
        DestinationHost = $result.Server.ToLower()
        DestinationPort = $result.Port
        ServiceType     = $test.PortCompactTitle
        Protocol        = $result.Protocol
        Latency         = $result.Latency
    }

    $rawResults += $test

    # Store raw result for HTML and CSV
    $displayResults += [PSCustomObject]@{
        Status      = "$icon $($result.Status)"
        Source      = $env:COMPUTERNAME
        Destination = "$($result.Server.ToLower()):$($result.Port)"
        ServiceType = $test.PortCompactTitle
        Latency     = $result.Latency
    }
}
Write-Host ("-" * $totalLength)
Write-Host ""

if ($ReportType -eq "Platform") {
    $scriptLogPath = Join-Path $(Get-CommonLogFilesPath) "Platform Port Verification"
}
else {
    $scriptLogPath = Join-Path $(Get-CommonLogFilesPath) "Computer Port Verification"
}

if (-not (Test-Path $scriptLogPath -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $scriptLogPath
    }
    catch {
        Write-Host "Failed to create directory at $scriptLogPath. Using current directory." -ForegroundColor Yellow
        $scriptLogPath = $PWD.Path
    }
}

if ($ReportType -eq "Platform") {
    $outputPath = $(Join-Path $scriptLogPath "$($platform) Platform Port Verification Results.csv").ToString()
}
else {
    $outputPath = $(Join-Path $scriptLogPath "$($ComputerName) Computer Port Verification Results.csv").ToString()
}
Write-Host "Exported results to CSV file: " $(Export-ArrayToCsvFile -Content $rawResults -OutputPath $outputPath) -ForegroundColor Green
if ($ReportType -eq "Platform") {
    $ouputFolder = Join-Path $(Get-DevToolsWebPath) "Platform Port Verification"
}
else {
    $ouputFolder = Join-Path $(Get-DevToolsWebPath) "Computer Port Verification"
}
if (-not (Test-Path $ouputFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $ouputFolder
}
if ($ReportType -eq "Platform") {
    $outputPath = $(Join-Path $ouputFolder "$($platform) Port Check Results.html").ToString()
}
else {
    $outputPath = Join-Path $ouputFolder "$($ComputerName.ToLower()) Port Check Results.html"
}
$result = Export-ArrayToHtmlFile -Content $displayResults -Title $title -AutoOpen:$false -OutputPath $outputPath -NoTitleAutoFormat -AddToDevToolsWebPath $true -DevToolsWebDirectory "Server\$($env:COMPUTERNAME.ToLower())/Network"
Write-Host "Exported results to HTML file: " $result -ForegroundColor Green

