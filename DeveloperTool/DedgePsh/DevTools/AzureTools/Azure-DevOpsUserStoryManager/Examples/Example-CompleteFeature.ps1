# Example: Complete Feature Implementation Workflow
# This script demonstrates a complete workflow for finishing a user story

param(
    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,
    
    [Parameter(Mandatory = $true)]
    [string]$FeatureName,
    
    [string[]]$ImplementationFiles,
    [string]$DocumentationPath
)

$scriptPath = Join-Path $PSScriptRoot "..\Azure-DevOpsUserStoryManager.ps1"

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Complete Feature Implementation Workflow                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Work Item: $WorkItemId" -ForegroundColor Yellow
Write-Host "Feature:   $FeatureName`n" -ForegroundColor Yellow

# Step 1: Update description
Write-Host "[1/6] Updating description..." -ForegroundColor Green
& $scriptPath -WorkItemId $WorkItemId -Action Update `
    -Description "Implemented $FeatureName with full error handling, comprehensive logging, and unit tests. Ready for review."

# Step 2: Add completion comment
Write-Host "[2/6] Adding completion comment..." -ForegroundColor Green
$comment = @"
Feature implementation complete for $FeatureName

Completed:
✓ Core functionality implemented
✓ Error handling added
✓ Logging integrated
✓ Unit tests created
✓ Documentation updated

Ready for code review and testing.
"@
& $scriptPath -WorkItemId $WorkItemId -Action Comment -Comment $comment

# Step 3: Link implementation files
if ($ImplementationFiles) {
    Write-Host "[3/6] Linking implementation files..." -ForegroundColor Green
    foreach ($file in $ImplementationFiles) {
        $fileName = Split-Path $file -Leaf
        & $scriptPath -WorkItemId $WorkItemId -Action Link `
            -Url $file `
            -Title "Implementation: $fileName"
    }
}
else {
    Write-Host "[3/6] No implementation files specified, skipping..." -ForegroundColor Yellow
}

# Step 4: Attach documentation if provided
if ($DocumentationPath -and (Test-Path $DocumentationPath)) {
    Write-Host "[4/6] Attaching documentation..." -ForegroundColor Green
    & $scriptPath -WorkItemId $WorkItemId -Action Attach -FilePath $DocumentationPath
}
else {
    Write-Host "[4/6] No documentation path specified, skipping..." -ForegroundColor Yellow
}

# Step 5: Add tags
Write-Host "[5/6] Adding tags..." -ForegroundColor Green
& $scriptPath -WorkItemId $WorkItemId -Action AddTags -Tags "Implemented;Tested;ReadyForReview"

# Step 6: Change status to Resolved
Write-Host "[6/6] Changing status to Resolved..." -ForegroundColor Green
& $scriptPath -WorkItemId $WorkItemId -Action Status -State "Resolved"

Write-Host "`n✓ Feature implementation workflow completed!" -ForegroundColor Green
Write-Host "Work item $WorkItemId is now marked as Resolved and ready for review.`n" -ForegroundColor Cyan

<#
.EXAMPLE
.\Example-CompleteFeature.ps1 -WorkItemId 12345 -FeatureName "User Authentication" `
    -ImplementationFiles @("DevTools/Auth/Login.ps1", "DevTools/Auth/Session.ps1") `
    -DocumentationPath "C:\docs\auth-spec.pdf"
#>
