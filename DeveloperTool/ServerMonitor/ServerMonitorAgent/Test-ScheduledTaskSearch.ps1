#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests the scheduled task search functionality to diagnose why tasks aren't being found
#>

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Testing scheduled task search`n" -ForegroundColor Cyan

# Get current user
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "📋 Current User Information:" -ForegroundColor Cyan
Write-Host "   Full Name: $currentUser" -ForegroundColor White
$currentUserParts = $currentUser -split '\\'
if ($currentUserParts.Length -gt 1) {
    Write-Host "   Domain: $($currentUserParts[0])" -ForegroundColor Gray
    Write-Host "   Username: $($currentUserParts[1])" -ForegroundColor Gray
}

# Load Task Scheduler COM object
Write-Host "`n🔍 Searching for scheduled tasks..." -ForegroundColor Cyan
try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    
    # Recursively get all tasks
    function Get-AllTasksRecursive {
        param($folder)
        $tasks = @()
        
        try {
            # Get tasks in current folder
            $folderTasks = $folder.GetTasks(0)
            foreach ($task in $folderTasks) {
                $tasks += $task
            }
            
            # Get tasks in subfolders
            $subfolders = $folder.GetFolders(0)
            foreach ($subfolder in $subfolders) {
                $tasks += Get-AllTasksRecursive $subfolder
            }
        } catch {
            Write-Host "   ⚠️  Error accessing folder: $($folder.Path) - $_" -ForegroundColor Yellow
        }
        
        return $tasks
    }
    
    $allTasks = Get-AllTasksRecursive $rootFolder
    Write-Host "   Found $($allTasks.Count) total tasks`n" -ForegroundColor Green
    
    # Filter by current user
    Write-Host "🔍 Filtering tasks by current user: $currentUser`n" -ForegroundColor Cyan
    $matchingTasks = @()
    
    foreach ($task in $allTasks) {
        try {
            $definition = $task.Definition
            $principal = $definition.Principal
            $taskUser = $principal.UserId
            $taskAccount = $principal.Account
            $taskDisplayName = $principal.DisplayName
            
            $userInfo = $taskUser ?? $taskAccount ?? $taskDisplayName ?? "Unknown"
            
            # Check if matches current user
            $matches = $false
            if ($userInfo -eq $currentUser) {
                $matches = $true
            } elseif ($userInfo -like "*\$($currentUserParts[-1])") {
                $matches = $true
            } elseif ($userInfo -eq $currentUserParts[-1]) {
                $matches = $true
            }
            
            if ($matches) {
                $matchingTasks += $task
                Write-Host "✅ Match: $($task.Path)" -ForegroundColor Green
                Write-Host "      User: $userInfo" -ForegroundColor Gray
                Write-Host "      State: $($task.State)" -ForegroundColor Gray
                Write-Host "      Last Run: $($task.LastRunTime)" -ForegroundColor Gray
            } else {
                Write-Host "   Skip: $($task.Path) (User: $userInfo)" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "   ⚠️  Error checking task $($task.Path): $_" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n📊 Summary:" -ForegroundColor Cyan
    Write-Host "   Total tasks: $($allTasks.Count)" -ForegroundColor White
    Write-Host "   Tasks matching user '$currentUser': $($matchingTasks.Count)" -ForegroundColor $(if ($matchingTasks.Count -gt 0) { "Green" } else { "Red" })
    
    if ($matchingTasks.Count -eq 0) {
        Write-Host "`n⚠️  No tasks found matching current user!" -ForegroundColor Yellow
        Write-Host "   This could mean:" -ForegroundColor Gray
        Write-Host "   - Tasks are owned by a different user" -ForegroundColor Gray
        Write-Host "   - Tasks use a different user format (SID, etc.)" -ForegroundColor Gray
        Write-Host "   - User information is not accessible" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
}

$totalElapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow

