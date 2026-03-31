# Example: Quick User Story Update
# Simple script for quick updates during development

param(
    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet('Started', 'Progress', 'Completed', 'Blocked')]
    [string]$UpdateType,
    
    [string]$Message
)

$scriptPath = Join-Path $PSScriptRoot "..\Azure-DevOpsUserStoryManager.ps1"

Write-Host "`n═══ Quick Work Item Update ═══" -ForegroundColor Cyan
Write-Host "Work Item: $WorkItemId" -ForegroundColor Yellow
Write-Host "Type: $UpdateType`n" -ForegroundColor Yellow

switch ($UpdateType) {
    'Started' {
        Write-Host "Starting work on item..." -ForegroundColor Green
        
        # Add comment
        & $scriptPath -WorkItemId $WorkItemId -Action Comment `
            -Comment "Started work on this item. $(if ($Message) { $Message } else { '' })"
        
        # Change to Active
        & $scriptPath -WorkItemId $WorkItemId -Action Status -State "Active"
        
        Write-Host "✓ Work item set to Active" -ForegroundColor Green
    }
    
    'Progress' {
        Write-Host "Adding progress update..." -ForegroundColor Green
        
        $comment = if ($Message) { 
            "Progress update: $Message" 
        }
        else { 
            "Progress update: Work in progress" 
        }
        
        & $scriptPath -WorkItemId $WorkItemId -Action Comment -Comment $comment
        
        Write-Host "✓ Progress comment added" -ForegroundColor Green
    }
    
    'Completed' {
        Write-Host "Marking as completed..." -ForegroundColor Green
        
        # Add completion comment
        $comment = if ($Message) { 
            "Work completed. $Message" 
        }
        else { 
            "Work completed and ready for review" 
        }
        
        & $scriptPath -WorkItemId $WorkItemId -Action Comment -Comment $comment
        
        # Change to Resolved
        & $scriptPath -WorkItemId $WorkItemId -Action Status -State "Resolved"
        
        # Add completion tag
        & $scriptPath -WorkItemId $WorkItemId -Action AddTags -Tags "Completed"
        
        Write-Host "✓ Work item set to Resolved" -ForegroundColor Green
    }
    
    'Blocked' {
        Write-Host "Marking as blocked..." -ForegroundColor Yellow
        
        $comment = if ($Message) { 
            "⚠️ BLOCKED: $Message" 
        }
        else { 
            "⚠️ BLOCKED: Work cannot proceed" 
        }
        
        & $scriptPath -WorkItemId $WorkItemId -Action Comment -Comment $comment
        
        # Add blocked tag
        & $scriptPath -WorkItemId $WorkItemId -Action AddTags -Tags "Blocked"
        
        Write-Host "✓ Blocked status added" -ForegroundColor Yellow
    }
}

Write-Host "`n✓ Update completed`n" -ForegroundColor Cyan

<#
.EXAMPLE
# Starting work
.\Example-QuickUpdate.ps1 -WorkItemId 12345 -UpdateType Started -Message "Beginning implementation"

.EXAMPLE
# Progress update
.\Example-QuickUpdate.ps1 -WorkItemId 12345 -UpdateType Progress -Message "50% complete, database integration done"

.EXAMPLE
# Completed
.\Example-QuickUpdate.ps1 -WorkItemId 12345 -UpdateType Completed -Message "All tests passing"

.EXAMPLE
# Blocked
.\Example-QuickUpdate.ps1 -WorkItemId 12345 -UpdateType Blocked -Message "Waiting for API access"
#>
