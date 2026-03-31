Import-Module Agent-Handler -Force
Import-Module GlobalFunctions -Force
try {
    Write-LogMessage "Starting Agent-HandlerAutoDeploy" -Level JOB_STARTED
    # Look for files in the agent folder that have not been processed
    $agentFolder = Join-Path $env:OptPath "agent"
    $agentFiles = Get-ChildItem -Path $agentFolder -Filter "*.ps1"
    foreach ($agentFile in $agentFiles) {
        $failCounter += Start-HandleSingleFileAgentTaskProcess -FilePath $agentFile.FullName
        if ($failCounter -gt 0) {
            Write-LogMessage "Failed to process agent file $($agentFile.FullName)" -Level ERROR
        }
    }

    Start-AgentTaskProcessFileWatcher
    Write-LogMessage "Agent-HandlerAutoDeploy completed" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Agent-HandlerAutoDeploy failed" -Level JOB_FAILED -Exception $_
    exit 1
}

