Import-Module GlobalFunctions -Force
function New-AdoTaskFromTemplate {
    param(
        [Parameter(Mandatory = $true)]
        $task,
        [Parameter(Mandatory = $true)]
        $serverPart,
        [Parameter(Mandatory = $true)]
        $server,
        [Parameter(Mandatory = $true)]
        $serverTemplate,
        [Parameter(Mandatory = $false)]
        $database
    )

    # Initialize arrays to prevent accumulation from previous calls
    $serverTasks = @()
    $adoTasks = @()
    $adoRelationships = @()

    # Create a deep copy of the task
    $newTask = $task | ConvertTo-Json -Depth 20 | ConvertFrom-Json

    # Replace all occurrences of placeholders

    # Replace placeholders in taskname
    $newTask.taskname = $newTask.taskname -replace '<serverpart>', $serverPart
    $newTask.taskname = $newTask.taskname -replace '<serverPart>', $serverPart
    if (-not [string]::IsNullOrWhiteSpace($database)) {
        $newTask.taskname = $newTask.taskname -replace '<databasename>', $database
    }

    # Replace placeholders in description
    $newTask.description = $newTask.description -replace '<serverpart>', $serverPart
    $newTask.description = $newTask.description -replace '<serverPart>', $serverPart
    if (-not [string]::IsNullOrWhiteSpace($database)) {
        $newTask.description = $newTask.description -replace '<databasename>', $database
    }

    # Replace placeholders in comment
    $newTask.comment = $newTask.comment -replace '<serverpart>', $serverPart
    $newTask.comment = $newTask.comment -replace '<serverPart>', $serverPart
    if (-not [string]::IsNullOrWhiteSpace($database)) {
        $newTask.comment = $newTask.comment -replace '<databasename>', $database
    }

    # Replace in prerequisite tasks
    if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
        for ($j = 0; $j -lt $newTask.prerequisiteTasks.Count; $j++) {
            $newTask.prerequisiteTasks[$j] = $newTask.prerequisiteTasks[$j] -replace '<serverpart>', $serverPart
            if (-not [string]::IsNullOrWhiteSpace($database)) {
                $newTask.prerequisiteTasks[$j] = $newTask.prerequisiteTasks[$j] -replace '<databasename>', $database
            }
        }
    }

    $newTask.prerequisiteComment = $newTask.prerequisiteComment -replace '<serverpart>', $serverPart
    if (-not [string]::IsNullOrWhiteSpace($database)) {
        $newTask.prerequisiteComment = $newTask.prerequisiteComment -replace '<databasename>', $database
    }

    # Add the task to the server's task list used in file output *.json
    $serverTasks += $newTask

    # Create ADO task format with database info
    $adoTask = @{
        op    = "add"
        path  = "/fields/System.Title"
        value = $newTask.taskname
    }

    $descriptionWithComment = ""
    if (-not [string]::IsNullOrWhiteSpace($newTask.description)) {
        $descriptionWithComment = $newTask.description
    }
    if (-not [string]::IsNullOrWhiteSpace($newTask.comment)) {
        if ($descriptionWithComment -ne "") {
            $descriptionWithComment += "`n`n"
        }
        $descriptionWithComment += "Comment: $($newTask.comment)"
    }
    if (-not [string]::IsNullOrWhiteSpace($newTask.prerequisiteComment)) {
        if ($descriptionWithComment -ne "") {
            $descriptionWithComment += "`n`n"
        }
        $descriptionWithComment += "Prerequisites Note: $($newTask.prerequisiteComment)"
    }
    if (-not [string]::IsNullOrWhiteSpace($database)) {
        $value = "$($server.ToUpper());$($database.ToUpper());SRVMIG;DBMIG;AZDB2MIG"
    }
    else {
        $value = "$($server.ToUpper());SRVMIG;DBMIG;AZDB2MIG"
    }

    $adoFields = @(
        $adoTask,
        @{
            op    = "add"
            path  = "/fields/System.Description"
            value = $($descriptionWithComment + $newTask.prerequisiteComment)
        },
        @{
            op    = "add"
            path  = "/fields/System.Tags"
            value = $value
        }
    )

    # Still add prerequisites as a text field for reference
    if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
        if ($newTask.prerequisiteTasks.Count -gt 1) {
            write-host "Prerequisites: $($newTask.prerequisiteTasks -join "; ")"
        }
        $prereqList = $newTask.prerequisiteTasks -join "; "
        # Add prerequisites to the acceptance criteria field
        # This will create a parent-child relationship in ADO where this task is the parent
        # and the prerequisites are the children, as defined later in adoRelationships
        $adoFields += @{
            op    = "add"
            path  = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"
            value = "Prerequisites:$prereqList"
        }
    }

    $taskId = "$($newTask.taskname)"
    # Add start date (today) and target date
    $adoFields += @{
        op    = "add"
        path  = "/fields/Microsoft.VSTS.Scheduling.StartDate"
        value = (Get-Date -Format "yyyy-MM-dd")
    }
    $adoFields += @{
        op    = "add"
        path  = "/fields/Microsoft.VSTS.Scheduling.TargetDate"
        value = "2025-05-16"
    }
    $adoTasks += @{
        id       = $taskId
        taskname = $newTask.taskname
        fields   = $adoFields
        server   = $server  # Add server info to help with hierarchy

    }

    # Store relationship info for later processing
    if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
        foreach ($prereq in $newTask.prerequisiteTasks) {
            $prereqTaskId = "$($prereq)"
            $adoRelationships += @{
                sourceId         = $taskId
                targetId         = $prereqTaskId
                relationshipType = "Successor"
            }
        }
    }

    return @{
        serverTasks      = $serverTasks
        adoTasks         = $adoTasks
        adoRelationships = $adoRelationships
    }
}

# Define new paths based on requested structure
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatesDir = Join-Path $scriptDir "Templates"
$templatesFile = Join-Path $templatesDir "serverTemplates.json"
$outputDir = Join-Path $scriptDir "Output"
$outputJsonTasksDir = Join-Path $outputDir "JsonTasks"
$outputADOTasksDir = Join-Path $outputDir "AzureDevOpsTasks"

Remove-Item -Recurse -Force $outputDir -ErrorAction Ignore | Out-Null

# Create output directories if they don't exist
if (-not (Test-Path $templatesDir)) {
    New-Item -ItemType Directory -Path $templatesDir -Force
    Write-Host "Created templates directory: $templatesDir"
}

if (-not (Test-Path $outputJsonTasksDir)) {
    New-Item -ItemType Directory -Path $outputJsonTasksDir -Force
    Write-Host "Created JSON tasks output directory: $outputJsonTasksDir"
}

if (-not (Test-Path $outputADOTasksDir)) {
    New-Item -ItemType Directory -Path $outputADOTasksDir -Force
    Write-Host "Created Azure DevOps tasks output directory: $outputADOTasksDir"
}

# Check if template file exists
if (-not (Test-Path $templatesFile)) {
    Write-Error "Template file not found at $templatesFile. Please create this file before running the script."
    exit 1
}

$serverTemplates = Get-Content -Path $templatesFile -Raw | ConvertFrom-Json

# $serversInfos = $(Get-ComputerInfoJson) | Where-Object { $_.Name -match "(p-no|t-no1)(?:[a-z]{3}|[a-z]{6})(-web|-db|-soa|-app)" -and $_.Platform -eq "Azure" -and $_.Name -notmatch "01$" -and $_.Name -notmatch "02$" }

foreach ($serverTemplate in $serverTemplates) {
    Write-Host "Generating tasks for template: $($serverTemplate.templateName)"

    # Check if the template has a serverDatabases property
    $hasServerDatabases = $null -ne $serverTemplate.PSObject.Properties['serverDatabases'] -and $serverTemplate.serverDatabases.Length -gt 0

    # Loop through servers in the template
    for ($i = 0; $i -lt $serverTemplate.servers.Length; $i++) {
        $server = $serverTemplate.servers[$i]
        $serverPart = $serverTemplate.serverPart[$i]

        Write-Host "  Processing server: $server (serverPart: $serverPart)"

        # Create a new task list for this specific server
        $serverTasks = @()
        $adoTasks = @()
        $adoRelationships = @()

        # Find the database configuration for this server if available
        $databaseConfig = $null
        if ($hasServerDatabases) {
            $databaseConfig = $serverTemplate.serverDatabases | Where-Object { $_.serverName -eq "$serverPart-db" } | Select-Object -First 1

            if ($databaseConfig) {
                Write-Host "    Found database configuration for server. Associated databases: $($databaseConfig.databases -join ', ')"
            }
        }

        # Process each task in the template
        foreach ($task in $serverTemplate.serverTasks) {
            # Check if the task contains a <databasename> placeholder
            $containsDatabasePlaceholder = $task.taskname -match '<databasename>' -or
            $task.description -match '<databasename>' -or
            $task.comment -match '<databasename>' -or
                                            ($task.prerequisiteTasks -and ($task.prerequisiteTasks -join ' ') -match '<databasename>') -or
            $task.prerequisiteComment -match '<databasename>'
            if ($task.taskname.Contains("<serverPart>-app-VerifyKerberosConfig-<databasename>")) {
                Write-Host "    Processing task: $($task.taskname)"
            }
            # If the task contains database placeholders and we have database config
            if ($containsDatabasePlaceholder -and $databaseConfig -and $databaseConfig.databases.Length -gt 0) {
                # Create a task for each database
                foreach ($database in $databaseConfig.databases) {
                    # Create a deep copy of the task

                    $result = New-AdoTaskFromTemplate -task $task -serverPart $serverPart -server $server -database $database -serverTemplate $serverTemplate
                    foreach ($newTask in $result.serverTasks) {
                        $serverTasks += $newTask
                    }
                    foreach ($newTask in $result.adoTasks) {
                        $adoTasks += $newTask
                    }
                    foreach ($newTask in $result.adoRelationships) {
                        $adoRelationships += $newTask
                    }
                }
            }
            else {
                $result = New-AdoTaskFromTemplate -task $task -serverPart $serverPart -server $server -serverTemplate $serverTemplate
                foreach ($newTask in $result.serverTasks) {
                    $serverTasks += $newTask
                }
                foreach ($newTask in $result.adoTasks) {
                    $adoTasks += $newTask
                }
                foreach ($newTask in $result.adoRelationships) {
                    $adoRelationships += $newTask
                }
            }
        }
        #         # Replace all occurrences of <serverpart> or <serverPart> with the actual server part
        #         $newTask.taskname = $newTask.taskname -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart
        #         $newTask.description = $newTask.description -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart
        #         $newTask.comment = $newTask.comment -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart

        #         # Replace in prerequisite tasks
        #         if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
        #             for ($j = 0; $j -lt $newTask.prerequisiteTasks.Count; $j++) {
        #                 $newTask.prerequisiteTasks[$j] = $newTask.prerequisiteTasks[$j] -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart
        #             }
        #         }

        #         $newTask.prerequisiteComment = $newTask.prerequisiteComment -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart

        #         # Add the task to the server's task list
        #         $serverTasks += $newTask

        #         # Create ADO task format (optimized for Azure DevOps REST API)
        #         $adoTask = @{
        #             op = "add"
        #             path = "/fields/System.Title"
        #             value = $newTask.taskname
        #         }

        #         $descriptionWithComment = ""
        #         if (-not [string]::IsNullOrWhiteSpace($newTask.description)) {
        #             $descriptionWithComment = $newTask.description
        #         }
        #         if (-not [string]::IsNullOrWhiteSpace($newTask.comment)) {
        #             if ($descriptionWithComment -ne "") {
        #                 $descriptionWithComment += "`n`n"
        #             }
        #             $descriptionWithComment += "Comment: $($newTask.comment)"
        #         }
        #         if (-not [string]::IsNullOrWhiteSpace($newTask.prerequisiteComment)) {
        #             if ($descriptionWithComment -ne "") {
        #                 $descriptionWithComment += "`n`n"
        #             }
        #             $descriptionWithComment += "Prerequisites Note: $($newTask.prerequisiteComment)"
        #         }

        #         $adoFields = @(
        #             $adoTask,
        #             @{
        #                 op = "add"
        #                 path = "/fields/System.Description"
        #                 value = $descriptionWithComment
        #             },
        #             @{
        #                 op = "add"
        #                 path = "/fields/System.Tags"
        #                 value = "Server=$server;ServerPart=$serverPart;Template=$($serverTemplate.templateName);default=$($newTask.default)"
        #             }
        #         )

        #         # Still add prerequisites as a text field for reference
        #         if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
        #             $prereqList = $newTask.prerequisiteTasks -join "; "
        #             $adoFields += @{
        #                 op = "add"
        #                 path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"
        #                 value = "Prerequisites: $prereqList"
        #             }
        #         }

        #         $taskId = $newTask.taskname

        #         $adoTasks += @{
        #             id = $taskId
        #             taskname = $newTask.taskname
        #             fields = $adoFields
        #             server = $server  # Add server info to help with hierarchy
        #         }

        #         # Store relationship info for later processing
        #         if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
        #             foreach ($prereq in $newTask.prerequisiteTasks) {
        #                 $adoRelationships += @{
        #                     sourceId = $taskId
        #                     targetId = $prereq
        #                     relationshipType = "affected By"
        #                 }
        #             }
        #         }
        #     }
        # }

        # Create a new object to hold the tasks for this server
        $serverTaskObject = @{
            server     = $server
            serverPart = $serverPart
            tasks      = $serverTasks
        }

        # Save to a JSON file named after the server
        $outputPath = Join-Path $outputJsonTasksDir "$server.json"
        $serverTaskObject | ConvertTo-Json -Depth 20 | Set-Content -Path $outputPath

        # Save ADO tasks to a separate JSON file with support for relationships
        $adoOutputPath = Join-Path $outputADOTasksDir "$server.ado.json"
        $adoTaskObject = @{
            server        = $server
            serverPart    = $serverPart
            templateName  = $serverTemplate.templateName
            tasks         = $adoTasks
            relationships = $adoRelationships
        }
        $adoTaskObject | ConvertTo-Json -Depth 20 | Set-Content -Path $adoOutputPath

        Write-Host "  Generated task file: $outputPath"
        Write-Host "  Generated Azure DevOps task file: $adoOutputPath"
    }
}

Write-Host "Task generation complete. Files are in: $outputJsonTasksDir"
Write-Host "Azure DevOps task files are in: $outputADOTasksDir"

