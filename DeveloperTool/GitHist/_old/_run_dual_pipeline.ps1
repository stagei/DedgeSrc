Import-Module GlobalFunctions -Force

$overallStart = Get-Date
Write-LogMessage "[DualPipeline] === DUAL PIPELINE START ===" -Level INFO

# Run 1: All authors from 2015
Write-LogMessage "[DualPipeline] --- Run 1/2: All authors since 2015-01-01 ---" -Level INFO
& "$PSScriptRoot\_run_full_pipeline.ps1" -AuthorFilter '' -AuthorEmail '' -Since '2015-01-01' -SkipClone -Force
Write-LogMessage "[DualPipeline] --- Run 1/2 complete ---" -Level INFO

# Run 2: Geir Helge Starholm from 2023-09-01
Write-LogMessage "[DualPipeline] --- Run 2/2: FKGEISTA since 2023-09-01 ---" -Level INFO
& "$PSScriptRoot\_run_full_pipeline.ps1" -AuthorFilter 'FKGEISTA' -AuthorEmail 'geir.helge.starholm@Dedge.no' -Since '2023-09-01' -SkipClone -Force
Write-LogMessage "[DualPipeline] --- Run 2/2 complete ---" -Level INFO

$elapsed = (Get-Date) - $overallStart
Write-LogMessage "[DualPipeline] === BOTH PIPELINES COMPLETE === (total: $($elapsed.ToString('hh\:mm\:ss')))" -Level INFO

try {
    $smsReceiver = switch ($env:USERNAME) {
        "FKGEISTA" { "+4797188358" }
        "FKSVEERI" { "+4795762742" }
        "FKMISTA"  { "+4799348397" }
        default    { "+4797188358" }
    }
    Send-Sms -Receiver $smsReceiver -Message "Both Git History pipelines complete. Total: $($elapsed.ToString('hh\:mm\:ss'))." -ErrorAction SilentlyContinue
    Write-LogMessage "[DualPipeline] SMS sent" -Level INFO
} catch {
    Write-LogMessage "[DualPipeline] SMS failed: $($_.Exception.Message)" -Level WARN
}
