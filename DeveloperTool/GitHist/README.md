# GitHist

Automated pipeline that extracts git history from all Azure DevOps repositories, generates LLM-powered business summaries, and publishes an interactive web presentation.

## Quick Start

```powershell
# Refresh all existing datasets (clones repos first, then re-runs every step)
.\Start-FullPipeline.ps1

# Skip the git clone/pull step (if repos are already up to date)
.\Start-FullPipeline.ps1 -SkipClone

# Force regenerate Ollama summaries even when git history hasn't changed
.\Start-FullPipeline.ps1 -Force

# Create a new dataset for a specific author and date range
.\Start-FullPipeline.ps1 -AuthorFilter 'FKGEISTA' -AuthorEmail 'geir.helge.starholm@Dedge.no' -Since '2023-09-01'

# All authors from 2015
.\Start-FullPipeline.ps1 -AuthorFilter '' -AuthorEmail '' -Since '2015-01-01'
```

## Pipeline Steps

| Step | Script | Output |
|------|--------|--------|
| 0 | Azure-DevOpsCloneRepositories.ps1 *(external)* | Clones/pulls all repos to `C:\opt\src` |
| 1 | `Step1-Get-ProjectWorkList.ps1` | `ProjectWorkList.txt` |
| 2 | `Step2-Export-GitHistoryTree.ps1` | `Projects_<author>_<from>_<to>/GitHistory.md` per project |
| 3 | `Step3-Analyze-GitExtractWithOllama.ps1` | `PresentationSummary.md` per project (Ollama LLM) |
| 4 | `Presentation/Step4-Export-PresentationData.ps1` | `Projects_*.json` + `datasets.json` |
| 5 | `Step5-Publish-GitHistWeb.ps1` *(manual)* | Copies Presentation/ to IIS server |

`Start-FullPipeline.ps1` orchestrates steps 0-4 automatically. Step 5 is run separately after the pipeline completes.

## Parameters

### Start-FullPipeline.ps1

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-AuthorFilter` | `""` | Windows username (e.g. `FKGEISTA`) or empty for all authors |
| `-AuthorEmail` | `""` | Git author email for commit filtering |
| `-Since` | `""` | Start date (e.g. `2023-09-01` or `9 months ago`) |
| `-TargetPath` | `C:\opt\src` | Root folder containing all source repos |
| `-SkipClone` | *switch* | Skip the git clone/pull step |
| `-Force` | *switch* | Regenerate all outputs even if unchanged |

When called **without parameters**, the script auto-detects existing `Projects_*` folders and refreshes each one.

### Step5-Publish-GitHistWeb.ps1

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ComputerName` | `dedge-server` | Target IIS server hostname |
| `-SetupIIS` | *switch* | Run IIS-DeployApp to create/update the virtual app (first deploy only) |

## Project Structure

```
GitHist/
  Start-FullPipeline.ps1          # Orchestrator (steps 0-4)
  Step1-Get-ProjectWorkList.ps1   # Discover repos with matching commits
  Step2-Export-GitHistoryTree.ps1  # Extract git history per project
  Step3-Analyze-GitExtractWithOllama.ps1  # LLM business summaries
  Step5-Publish-GitHistWeb.ps1    # Deploy to IIS
  ProjectWorkList.txt             # Generated: curated repo list
  team-info.md                    # Team member config (usernames, emails, SMS)
  Projects_all_20150101_*/        # Generated: extract folders
  Presentation/
    Step4-Export-PresentationData.ps1  # Build JSON for web UI
    index.html                        # Interactive timeline + project cards
    autodoc-viewer.html               # Mermaid diagram popout viewer
    datasets.json                     # Manifest for the UI dataset picker
    Projects_*.json                   # Aggregated project data per dataset
  _old/                           # Archived one-off scripts
```

## Web Application

After the pipeline completes, the Presentation folder contains a static web app served by IIS at `http://dedge-server/GitHist/`.

Features: interactive D3 timeline, project cards, author/date/tag filtering, AutoDocJson integration with inline Mermaid diagrams.

## Prerequisites

- PowerShell 7+ (`pwsh.exe`)
- Git for Windows
- Ollama with `qwen3:8b` model (for Step 3)
- `GlobalFunctions` and `OllamaHandler` modules on `$env:PSModulePath`
- Azure DevOps PAT configured (see `team-info.md`)
