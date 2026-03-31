<#
.SYNOPSIS
Wrapper script for interactive or non-interactive Azure DevOps repository cloning.

.DESCRIPTION
Imports SoftwareUtils and calls Copy-AzureRepos.
Use -CloneAll:$true to clone all repositories without prompts.
Use -TargetPath to override the default clone destination path.
Use -PullOnlyIfAllExist with -CloneAll to skip cloning when all Dedge-code repos
already exist — runs git pull on each instead (avoids Azure API call).
#>

param (
    [bool]$CloneAll = $true,
    [string]$TargetPath = (Join-Path $env:OptPath 'src'),
    [bool]$PullOnlyIfAllExist = $true
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $TargetPath -PathType Container)) {
    New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
}

# When -PullOnlyIfAllExist and -CloneAll: if all Dedge-code repos exist, just git pull and exit
if ($CloneAll -and $PullOnlyIfAllExist) {
    $cloneRoot = $TargetPath

    if (-not $env:OptPath) {
        Write-Host '[WARN] OptPath not set. Falling back to full clone.' -ForegroundColor Yellow
    } else {
        # Resolve Dedge-code repo list from config (absolute paths only)
        $configPaths = @(
            (Join-Path $env:OptPath 'FkPythonApps\AiDoc\library\Dedge-code\.Dedge-rag-config.json'),
            (Join-Path $env:OptPath 'src\AiDoc\library\Dedge-code\.Dedge-rag-config.json')
        )
        $configFile = $null
        foreach ($p in $configPaths) {
            if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
                $configFile = $p
                break
            }
        }

        if (-not $configFile) {
            Write-Host '[WARN] Dedge-rag-config.json not found. Falling back to full clone.' -ForegroundColor Yellow
        } else {
            $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
            $repos = $config.repos

            $allExist = $true
            foreach ($repoName in $repos) {
                $repoPath = Join-Path $cloneRoot $repoName
                if (-not (Test-Path -LiteralPath (Join-Path $repoPath '.git') -PathType Container)) {
                    $allExist = $false
                    break
                }
            }

            if ($allExist -and $repos.Count -gt 0) {
                Write-Host "All $($repos.Count) Dedge-code repos exist. Running git pull only..." -ForegroundColor Cyan
                foreach ($repoName in $repos) {
                    $repoPath = Join-Path $cloneRoot $repoName
                    Write-Host "  Pulling $repoName..." -NoNewline
                    try {
                        Push-Location $repoPath
                        git pull 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host " OK" -ForegroundColor Green
                        } else {
                            Write-Host " (exit $LASTEXITCODE)" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host " FAILED: $_" -ForegroundColor Red
                    } finally {
                        Pop-Location
                    }
                }
                Write-Host "Done (pull-only, no clone)." -ForegroundColor Green
                exit 0
            }
        }
    }
}

Import-Module SoftwareUtils -Force
Copy-AzureRepos -CloneAll:$CloneAll -TargetPath $TargetPath

