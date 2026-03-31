param (
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = "*",
    [Parameter(Mandatory = $false)]
    [ValidateSet("NetworkPortGroupsOverviewReport", "NetworkAccessOverviewExport", "NetworkAccessDetailedReport", "NetworkPortGroupsExport", "All")]
    [string]$ReportType = "All"
)

# Network Access Overview Report
Import-Module Export-Array -Force
Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force

function Export-NetworkReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportName,
        [Parameter(Mandatory = $true)]
        [PSObject[]]$Content,
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [Parameter(Mandatory = $false)]
        [bool]$AutoOpen = $false
    )

    # Export to CSV
    $csvPath = $(Join-Path $LogPath "$ReportName.csv").ToString()
    $fileExported = Export-ArrayToCsvFile -Content $Content -OutputPath $csvPath
    Write-LogMessage "Exported results to CSV file: $fileExported"  -Level INFO

    # Export to HTML
    $htmlFolder = Join-Path $(Get-DevToolsWebPath) "Network"
    if (-not (Test-Path $htmlFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $htmlFolder
    }
    $htmlPath = $(Join-Path $htmlFolder "$ReportName.html").ToString()
    $fileExported = Export-ArrayToHtmlFile -Content $Content -Title $ReportName -AutoOpen $AutoOpen -OutputPath $htmlPath -AddToDevToolsWebPath "Server/Network/Overview"
    Write-LogMessage "Exported results to HTML file: $fileExported"  -Level INFO
}
function Add-HostInfoToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [array]$ComputerInfos,
        [Parameter(Mandatory = $true)]
        [array]$htmlContent
    )

    foreach ($computer in $ComputerInfos) {
        if (-not $computer.Type.Contains("Server")) {
            continue
        }
        $isAlreadyIpaddress = $computer.Name -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"
        if ($isAlreadyIpaddress) {
            $hostname = $(Get-HostDnsAddress -HostIpAddress $computer.Name -Quiet $true) ?? "N/A"
            if (-not $hostname) {
                $hostname = $computer.Name
            }
            $htmlContent = Add-HtmlContent -AddString "<tr><td>$($hostname)</td><td>$($computer.Name)</td><td>$($computer.Purpose)</td></tr>" -htmlContent $htmlContent
        }
        else {
            $ipAddress = Get-ComputerIpAddress -ComputerName $computer.Name -Quiet $true
            if (-not $ipAddress) {
                $ipAddress = "N/A"
            }
            $htmlContent = Add-HtmlContent -AddString "<tr><td>$($computer.Name)</td><td>$($ipAddress)</td><td>$($computer.Purpose)</td></tr>" -htmlContent $htmlContent
        }
    }
    return $htmlContent
}

function Add-HtmlContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AddString,
        [Parameter(Mandatory = $false)]
        [string[]]$htmlContent
    )
    if ([string]::IsNullOrEmpty($AddString)) {
        $htmlContent += ""
        return $htmlContent
    }
    if ($htmlContent) {
        $htmlContent += $AddString
    }
    else {
        $htmlContent = @($AddString)
    }
    Write-LogMessage "HTML ADDED -> $AddString" -Level INFO
    return $htmlContent
}
#-------------------------------------------------------------------------------------------------
# Main script
#-------------------------------------------------------------------------------------------------

$scriptLogPath = Join-Path $(Get-CommonLogFilesPath) "Network"
if (-not (Test-Path $scriptLogPath -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $scriptLogPath
    }
    catch {
        Write-LogMessage "Failed to create directory at $scriptLogPath. Using current directory." -ForegroundColor Yellow
        $scriptLogPath = $PWD.Path
    }
}

if ($ReportType -eq "NetworkAccessOverviewExport" -or $ReportType -eq "All") {
    $title = "Network Access Overview Export for $($env:COMPUTERNAME.ToLower())"
    $ReportAllConsumerDetails = $false

    $serverConfig = Get-ServerConfiguration -ComputerName $ComputerName -ReportAllConsumerDetails $ReportAllConsumerDetails
    $serverConfigNew = @()
    $totalObjects = $serverConfig.Count
    $currentObjectCount = 0
    foreach ($obj in $serverConfig) {
        $currentObjectCount++
        Write-Progress -Activity "Processing network access overview" -Status "Processing network pattern $currentObjectCount of $totalObjects" -PercentComplete (($currentObjectCount / $totalObjects) * 100)
        $matchResult = $obj.ProviderHost -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"

        if ($obj.InternetAccess -and -not $matchResult) {
            $IpAddress = Get-ComputerIpAddress -ComputerName $obj.ProviderHost -Quiet $true
            if ($IpAddress) {
                $obj.ProviderHost = $obj.ProviderHost + " (" + $IpAddress + ")"
            }
        }
        $serverConfigNew += $obj
    }
    Export-NetworkReport -ReportName $title -Content $serverConfigNew -LogPath $scriptLogPath
}

if ($ReportType -eq "NetworkAccessDetailedReport" -or $ReportType -eq "All") {
    $title = "Network Access Detailed Report"
    $ReportAllConsumerDetails = $true
    $serverConfig = Get-ServerConfiguration -ComputerName $ComputerName -ReportAllConsumerDetails $ReportAllConsumerDetails
    $totalObjects = $serverConfig.Count
    $currentObjectCount = 0
    foreach ($obj in $serverConfig) {
        $currentObjectCount++
        Write-Progress -Activity "Processing network access details" -Status "Processing object $currentObjectCount of $totalObjects" -PercentComplete (($currentObjectCount / $totalObjects) * 100)

        $matchResult = $obj.ProviderHost -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"
        if (-not $matchResult) {
            $obj.ProviderHostIpAddress = Get-ComputerIpAddress -ComputerName $obj.ProviderHost -Quiet $true
        }
        else {
            $obj.ProviderHostIpAddress = $obj.ProviderHost
            $obj.ProviderHost = $(Get-HostDnsAddress -HostIpAddress $obj.ProviderHost -Quiet $true) ?? "N/A"
        }

        $matchResult = $obj.ConsumerHost -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"
        if (-not $matchResult) {
            $obj.ConsumerHostIpAddress = Get-ComputerIpAddress -ComputerName $obj.ConsumerHost -Quiet $true
        }
        else {
            $obj.ConsumerHostIpAddress = $obj.ConsumerHost
            $obj.ConsumerHost = $(Get-HostDnsAddress -HostIpAddress $obj.ConsumerHost -Quiet $true) ?? "N/A"
        }

        # if ($obj.InternetAccess) {
        #     $IpAddress = Get-ComputerIpAddress -ComputerName $obj.ProviderHost -Quiet $true
        #     if ($IpAddress) {
        #         $obj.ProviderHost = $obj.ProviderHost + " (" + $IpAddress + ")"
        #     }
        # }
        $serverConfigNew += $obj
    }
    Export-NetworkReport -ReportName $title -Content $serverConfig -LogPath $scriptLogPath
}

if ($ReportType -eq "NetworkPortGroupsOverviewReport" -or $ReportType -eq "All") {
    $title = "Network Port Groups Overview Report"
    $portGroups = Get-PortGroupJson
    $outputFile = $(Join-Path $scriptLogPath $($title.ToTitleCase() + ".html")).ToString()

    $computerInfos = Get-ComputerInfoJson

    # Write heading in markdown

    $htmlContent = @()
    $htmlContent = Add-HtmlContent -AddString "<hr>" -htmlContent $htmlContent
    $htmlContent = Add-HtmlContent -AddString "<div style='font-size: 24px; font-weight: bold; margin: 20px 0;'>Complete list of all port openings that is needed to keep Dedge and FkKonto running for both test and production environments</div>" -htmlContent $htmlContent

    foreach ($portGroup in $portGroups) {
        $htmlContent = Add-HtmlContent -AddString '<div style="border: 1px solid #ccc; padding: 10px; border-radius: 5px; background-color: #f9f9f9;">' -htmlContent $htmlContent
        $htmlContent = Add-HtmlContent -AddString "<br>" -htmlContent $htmlContent

        $htmlContent = Add-HtmlContent -AddString "<h2>Network Port Group: $($portGroup.Id)</h2>" -htmlContent $htmlContent
        $htmlContent = Add-HtmlContent -AddString "<p>Description: $($portGroup.Description)</p>" -htmlContent $htmlContent
        $htmlContent = Add-HtmlContent -AddString "<h3>Ports</h3>" -htmlContent $htmlContent
        $htmlContent = Add-HtmlContent -AddString "<table border='1'>" -htmlContent $htmlContent
        $htmlContent = Add-HtmlContent -AddString "<tr><th>Port(s) or Port Range</th><th>Protocol</th><th>Description</th></tr>" -htmlContent $htmlContent
        foreach ($port in $portGroup.Ports) {
            $portDisplay = if ($port.Port.Start -and $port.Port.End) {
                if ($port.Port.Start -eq $port.Port.End) {
                    $port.Port.Start
                }
                else {
                    "$($port.Port.Start)-$($port.Port.End)"
                }
            }
            else {
                "N/A"
            }
            $htmlContent = Add-HtmlContent -AddString "<tr><td>$portDisplay</td><td>$($port.Protocols -join ",")</td><td>$($port.Description)</td></tr>" -htmlContent $htmlContent
        }
        $htmlContent = Add-HtmlContent -AddString "</table>" -htmlContent $htmlContent
        $htmlContent = Add-HtmlContent -AddString "<br>" -htmlContent $htmlContent

        try {
            if ($portGroup.ProviderHosts) {
                $htmlContent = Add-HtmlContent -AddString "<h3>Provider Hosts</h3>" -htmlContent $htmlContent
                $htmlContent = Add-HtmlContent -AddString "<table border='1'>" -htmlContent $htmlContent
                $htmlContent = Add-HtmlContent -AddString "<tr><th>Provider Host</th><th>Provider IP Address</th><th>Purpose</th></tr>" -htmlContent $htmlContent
                foreach ($providerHost in $portGroup.ProviderHosts) {
                    if ($providerHost.isRegex) {
                        $computerInfosFiltered = @($computerInfos | Where-Object { $_.Name -match "$($providerHost.pattern)" })
                    }
                    elseif ($providerHost.pattern -eq "*") {
                        $computerInfosFiltered = @([PSCustomObject]@{Name = "*"; Purpose = "All Dedge Servers and Workstations"; Type = "Servers and Workstations" })
                    }
                    else {
                        $computerInfosFiltered = $($computerInfos | Where-Object { $_.Name -eq "$($providerHost.pattern)" }) ?? @([PSCustomObject]@{Name = $providerHost.pattern; Purpose = $($portGroup.Description.ToLower().Replace("ports", "handler").Replace("port", "handler").ToTitleCase().ToString()); Type = "Server" })
                    }

                    $htmlContent = Add-HostInfoToMarkdown -Pattern $providerHost -Description $portGroup.Description -ComputerInfos $computerInfosFiltered -htmlContent $htmlContent
                }
                $htmlContent = Add-HtmlContent -AddString "</table>" -htmlContent $htmlContent
            }
        }
        catch {
            Write-LogMessage "Failed to add provider hosts to markdown. " -Level ERROR -Exception $_
        }
        $htmlContent = Add-HtmlContent -AddString "<br>" -htmlContent $htmlContent
        try {
            if ($portGroup.ConsumerHosts) {
                $htmlContent = Add-HtmlContent -AddString "<h3>Consumer Hosts</h3>" -htmlContent $htmlContent
                $htmlContent = Add-HtmlContent -AddString "<table border='1'>" -htmlContent $htmlContent
                $htmlContent = Add-HtmlContent -AddString "<tr><th>Consumer Host</th><th>Consumer IP Address</th><th>Purpose</th></tr>" -htmlContent $htmlContent
                foreach ($consumerHost in $portGroup.ConsumerHosts) {
                    if ($consumerHost.isRegex) {
                        $computerInfosFiltered = @($computerInfos | Where-Object { $_.Name -match "$($consumerHost.pattern)" })
                    }
                    elseif ($consumerHost.pattern -eq "*") {
                        $computerInfosFiltered = @([PSCustomObject]@{Name = "*"; Purpose = "All Dedge Servers and Workstations"; Type = "Servers and Workstations" })
                    }
                    else {
                        $computerInfosFiltered = $($computerInfos | Where-Object { $_.Name -eq "$($consumerHost.pattern)" }) ?? @([PSCustomObject]@{Name = $consumerHost.pattern; Purpose = $($portGroup.Description.ToLower().Replace("ports", "handler").Replace("port", "handler").ToTitleCase().ToString()); Type = "Server" })
                    }
                    if ($computerInfosFiltered.Count -eq 0) {
                        $x = 1
                    }

                    $htmlContent = Add-HostInfoToMarkdown -Pattern $consumerHost -Description $portGroup.Description -ComputerInfos $computerInfosFiltered -htmlContent $htmlContent
                }
                $htmlContent = Add-HtmlContent -AddString "</table>" -htmlContent $htmlContent
            }
        }
        catch {
            Write-LogMessage "Failed to add consumer hosts to markdown. " -Level ERROR -Exception $_
        }
        $htmlContent = Add-HtmlContent -AddString "</div>" -htmlContent $htmlContent
        $htmlContent = Add-HtmlContent -AddString "<br>" -htmlContent $htmlContent
    }
    $null = Save-HtmlOutput -Title $title -Content $htmlContent -OutputFile $outputFile -AddToDevToolsWebPath $true -DevToolsWebDirectory "Network" -AutoOpen $false

    $outputFileWord = $outputFile.Replace(".html", ".docx")
    Save-UsingPandoc -InputFile $outputFile -OutputFile $outputFileWord -AutoOpen $true
}

if ($ReportType -eq "NetworkPortGroupsExport" -or $ReportType -eq "All") {
    $title = "Network Port Groups Export"
    $flattenedPortGroups = ConvertTo-FlattenedArrayRows -InputObject $portGroups
    Export-NetworkReport -ReportName $title -Content $flattenedPortGroups -LogPath $scriptLogPath
}

