<#
.SYNOPSIS
    Proxy module for Cursor IDE commands — /azstory, /sysdocs, /devdocs.

.DESCRIPTION
    Imports AzureFunctions and GlobalFunctions, then provides thin proxy functions
    that add Cursor-command-specific defaults and combine multiple core calls.

    Core functions live in the modules they relate to:
      - AzureFunctions: Invoke-AdoRestApi, New-AdoWorkItem, Set-AdoWorkItemField, Get-AdoWorkItem
      - GlobalFunctions: Convert-MermaidToBase64, Publish-ToDocView, Find-ReferencedRules, Get-ProjectTech

    This module adds Cursor-specific orchestration on top.
#>
Import-Module GlobalFunctions -Force
Import-Module AzureFunctions -Force

function New-CursorWorkItem {
    <#
    .SYNOPSIS
        Creates an ADO work item with Cursor defaults: auto-assigns current user, auto-tags AzStory.
    .PARAMETER Title
        Norwegian work item title.
    .PARAMETER Type
        Work item type. Default: User Story.
    .PARAMETER Description
        HTML description (optional).
    .PARAMETER Tags
        Semicolon-separated tags. "AzStory" is always prepended.
    .PARAMETER ParentId
        Parent work item ID for hierarchy linking.
    .OUTPUTS
        PSCustomObject with id, url, title, state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [ValidateSet('Epic', 'User Story', 'Task', 'Bug')]
        [string]$Type = 'User Story',

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Tags,

        [Parameter()]
        [int]$ParentId = 0
    )

    $userEmail = switch ($env:USERNAME) {
        "FKGEISTA" { "geir.helge.starholm@Dedge.no" }
        "FKSVEERI" { "svein.morten.erikstad@Dedge.no" }
        "FKMISTA"  { "mina.marie.starholm@Dedge.no" }
        "FKCELERI" { "Celine.Andreassen.Erikstad@Dedge.no" }
        default    { "geir.helge.starholm@Dedge.no" }
    }

    $allTags = if ($Tags) {
        $tagList = ($Tags -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ('AzStory' -notin $tagList) { $tagList = @('AzStory') + $tagList }
        $tagList -join ';'
    }
    else { "AzStory" }

    $wi = New-AdoWorkItem -Type $Type -Title $Title -Description $Description `
        -AssignedTo $userEmail -Tags $allTags -ParentId $ParentId

    return [PSCustomObject]@{
        id    = $wi.id
        url   = $wi._links.html.href
        title = $wi.fields.'System.Title'
        state = $wi.fields.'System.State'
    }
}

function Set-CursorWorkItemDescription {
    <#
    .SYNOPSIS
        Sets the HTML description on a work item. Accepts a string or file path for very large content.
    .PARAMETER WorkItemId
        The work item ID.
    .PARAMETER HtmlDescription
        HTML description string.
    .PARAMETER HtmlFile
        Path to an .html file (alternative to HtmlDescription for very large content).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$WorkItemId,

        [Parameter(ParameterSetName = 'String')]
        [string]$HtmlDescription,

        [Parameter(ParameterSetName = 'File')]
        [string]$HtmlFile
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $HtmlDescription = Get-Content -Path $HtmlFile -Raw -Encoding utf8
    }

    Set-AdoWorkItemField -WorkItemId $WorkItemId -Fields @{
        "System.Description" = $HtmlDescription
    }
}

function Set-CursorWorkItemState {
    <#
    .SYNOPSIS
        Changes work item state and returns the transition (previousState → newState).
    .PARAMETER WorkItemId
        The work item ID.
    .PARAMETER State
        Target state.
    .OUTPUTS
        PSCustomObject with id, previousState, newState.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$WorkItemId,

        [Parameter(Mandatory)]
        [ValidateSet('New', 'Active', 'Resolved', 'Closed', 'Removed')]
        [string]$State
    )

    $current = Get-AdoWorkItem -WorkItemId $WorkItemId -Fields "System.State"
    $previousState = $current.fields.'System.State'

    Set-AdoWorkItemField -WorkItemId $WorkItemId -Fields @{
        "System.State" = $State
    }

    return [PSCustomObject]@{
        id            = $WorkItemId
        previousState = $previousState
        newState      = $State
    }
}

function Convert-CursorMermaid {
    <#
    .SYNOPSIS
        Renders mermaid code to base64 SVG with Cursor defaults (white background, 900px width).
    .PARAMETER MermaidCode
        Mermaid diagram source.
    .PARAMETER Name
        Diagram name for temp files. Default: "diagram".
    .OUTPUTS
        Base64 string ready for <img src="data:image/svg+xml;base64,..."> embedding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MermaidCode,

        [Parameter()]
        [string]$Name = "diagram"
    )

    Convert-MermaidToBase64 -MermaidCode $MermaidCode -Name $Name -Background "white" -Width 900
}

function Publish-CursorSysDocs {
    <#
    .SYNOPSIS
        Full /sysdocs publish pipeline: detect tech, publish to DocView, copy referenced rules.
    .PARAMETER SourceFile
        Path to the README.md or documentation file.
    .PARAMETER ProjectRoot
        Path to the project folder (for rule scanning).
    .PARAMETER GitRoot
        Path to the git repository root (for finding .cursor/rules/).
    .PARAMETER RelativePath
        Relative path for DocView target directory (e.g. "DedgePsh\DevTools\DatabaseTools").
    .PARAMETER DescriptiveTitle
        Filename for the published doc.
    .OUTPUTS
        PSCustomObject with docViewUrl, tech, rulesCopied.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$GitRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$DescriptiveTitle
    )

    $tech = Get-ProjectTech -ProjectPath $ProjectRoot

    $result = Publish-ToDocView -SourceFile $SourceFile -Tech $tech `
        -RelativePath $RelativePath -DescriptiveTitle $DescriptiveTitle

    $rulesDir = Join-Path $GitRoot ".cursor\rules"
    $targetDir = Split-Path $result.TargetPath -Parent
    $rulesCopied = @()

    if (Test-Path $rulesDir) {
        $rulesCopied = Find-ReferencedRules -ProjectRoot $ProjectRoot `
            -RulesDir $rulesDir -TargetDir $targetDir
    }

    return [PSCustomObject]@{
        docViewUrl  = $result.DocViewUrl
        tech        = $tech
        targetPath  = $result.TargetPath
        rulesCopied = $rulesCopied
    }
}

Export-ModuleMember -Function *
