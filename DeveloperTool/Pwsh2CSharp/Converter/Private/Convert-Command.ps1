function Convert-Command {
    <#
    .SYNOPSIS
        Converts a CommandAst to C# using the CmdletMappings.json table
        and delegate handlers for complex cmdlets.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$Ast,
        [hashtable]$Context
    )

    $cmdName = Get-CommandName -Ast $Ast
    $params  = Get-CommandParams -Ast $Ast

    # Check if it is a call operator: & $script @args
    if ($cmdName -eq '&' -or $Ast.InvocationOperator -eq 'Ampersand') {
        return Convert-InvocationCommand -Ast $Ast -Context $Context
    }

    # Look up mapping
    $mappings = Get-CmdletMapping
    $mapping  = $null
    if ($mappings.ContainsKey($cmdName)) {
        $mapping = $mappings[$cmdName]
    }

    # Track required usings
    if ($mapping -and $mapping.using) {
        foreach ($u in $mapping.using) {
            if ($u -and -not $Context.Usings.Contains($u)) {
                [void]$Context.Usings.Add($u)
            }
        }
    }

    if ($mapping) {
        switch ($mapping.emit) {
            'simple' {
                return Convert-SimpleCmdlet -CmdName $cmdName -Pattern $mapping.pattern -Params $params -Context $Context
            }
            'delegate' {
                return Convert-DelegateCmdlet -CmdName $cmdName -Params $params -Context $Context
            }
            'comment' {
                $argText = ($params | ForEach-Object { if ($_.Value) { $_.Value.Extent.Text } }) -join ' '
                return $mapping.pattern -replace '\{0\}', $argText
            }
            'discard' {
                return ''
            }
            'pipeline' {
                return "/* pipeline cmdlet $cmdName handled by pipeline converter */"
            }
        }
    }

    # No mapping: emit as TODO with original source
    return Convert-UnmappedCommand -CmdName $cmdName -Ast $Ast -Params $params -Context $Context
}

function Convert-SimpleCmdlet {
    param(
        [string]$CmdName,
        [string]$Pattern,
        [array]$Params,
        [hashtable]$Context
    )

    # Collect positional arguments
    $positionals = @()
    foreach ($p in $Params) {
        if ($null -eq $p.Name -and $null -ne $p.Value) {
            $positionals += Convert-Expression -Ast $p.Value -Context $Context
        }
    }

    # Also check first named arg as fallback
    if ($positionals.Count -eq 0) {
        foreach ($p in $Params) {
            if ($null -ne $p.Value) {
                $positionals += Convert-Expression -Ast $p.Value -Context $Context
                break
            }
        }
    }

    $argStr = $positionals -join ', '
    return $Pattern -replace '\{0\}', $argStr
}

function Convert-DelegateCmdlet {
    <#
    .SYNOPSIS
        Handles cmdlets that need custom C# emission logic based on their parameters.
    #>
    param(
        [string]$CmdName,
        [array]$Params,
        [hashtable]$Context
    )

    switch ($CmdName) {

        'Write-LogMessage' {
            $msg = $null; $level = 'Info'
            foreach ($p in $Params) {
                if ($p.Name -eq 'Level' -and $p.Value) {
                    $level = $p.Value.Extent.Text.Trim("'", '"')
                    # Map PS level names to NLog method names
                    $level = switch ($level.ToUpperInvariant()) {
                        'INFO'  { 'Info' }
                        'WARN'  { 'Warn' }
                        'ERROR' { 'Error' }
                        'DEBUG' { 'Debug' }
                        'TRACE' { 'Trace' }
                        'FATAL' { 'Fatal' }
                        default { 'Info' }
                    }
                }
                elseif ($null -eq $p.Name -and $null -ne $p.Value) {
                    $msg = Convert-Expression -Ast $p.Value -Context $Context
                }
            }
            if (-not $msg) { $msg = '""' }
            return "Logger.$level($msg)"
        }

        'Get-Content' {
            $path = $null; $raw = $false; $encoding = $null
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Raw')      { $raw = $true }
                elseif ($p.Name -eq 'Encoding' -and $p.Value) { $encoding = $p.Value.Extent.Text.Trim("'", '"') }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }

            if ($encoding) {
                return "File.ReadAllText($path, Encoding.GetEncoding(""$encoding""))"
            }
            if ($raw) { return "File.ReadAllText($path)" }
            return "File.ReadAllLines($path)"
        }

        'Set-Content' {
            $path = $null; $value = $null; $encoding = $null
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Value' -and $p.Value) { $value = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Encoding' -and $p.Value) { $encoding = $p.Value.Extent.Text.Trim("'", '"') }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $value) { $value = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }
            if (-not $value) { $value = '""' }

            if ($encoding) {
                return "File.WriteAllText($path, $value, Encoding.GetEncoding(""$encoding""))"
            }
            return "File.WriteAllText($path, $value)"
        }

        'Out-File' {
            $path = $null; $inputObj = $null
            foreach ($p in $Params) {
                if ($p.Name -in 'FilePath', 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'InputObject' -and $p.Value) { $inputObj = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }
            if (-not $inputObj) { $inputObj = '""' }
            return "File.WriteAllText($path, $inputObj)"
        }

        'Test-Path' {
            $path = $null; $pathType = $null
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'PathType' -and $p.Value) { $pathType = $p.Value.Extent.Text.Trim("'", '"') }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }

            switch ($pathType) {
                'Leaf'      { return "File.Exists($path)" }
                'Container' { return "Directory.Exists($path)" }
                default     { return "Path.Exists($path)" }
            }
        }

        'New-Item' {
            $path = $null; $itemType = 'Directory'
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'ItemType' -and $p.Value) {
                    if ($p.Name -eq 'Path') { $path = Convert-Expression -Ast $p.Value -Context $Context }
                    if ($p.Name -eq 'ItemType') { $itemType = $p.Value.Extent.Text.Trim("'", '"') }
                }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }

            if ($itemType -eq 'File') { return "File.Create($path).Dispose()" }
            return "Directory.CreateDirectory($path)"
        }

        'Remove-Item' {
            $path = $null; $recurse = $false
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Recurse') { $recurse = $true }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }

            if ($recurse) { return "Directory.Delete($path, true)" }
            return "File.Delete($path)"
        }

        'Copy-Item' {
            $source = $null; $dest = $null; $recurse = $false
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $source = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Destination' -and $p.Value) { $dest = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Recurse') { $recurse = $true }
                elseif ($null -eq $p.Name -and $null -ne $p.Value) {
                    if (-not $source) { $source = Convert-Expression -Ast $p.Value -Context $Context }
                    elseif (-not $dest) { $dest = Convert-Expression -Ast $p.Value -Context $Context }
                }
            }
            if (-not $source) { $source = '""' }
            if (-not $dest)   { $dest = '""' }
            return "File.Copy($source, $dest, true)"
        }

        'Get-ChildItem' {
            $path = $null; $filter = $null; $recurse = $false; $fileOnly = $false; $dirOnly = $false
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Filter' -and $p.Value) { $filter = $p.Value.Extent.Text.Trim("'", '"') }
                elseif ($p.Name -eq 'Recurse') { $recurse = $true }
                elseif ($p.Name -eq 'File')      { $fileOnly = $true }
                elseif ($p.Name -eq 'Directory')  { $dirOnly = $true }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }

            $searchOpt = if ($recurse) { 'SearchOption.AllDirectories' } else { 'SearchOption.TopDirectoryOnly' }
            $filterStr = if ($filter) { """$filter""" } else { '"*"' }

            if ($fileOnly) { return "Directory.EnumerateFiles($path, $filterStr, $searchOpt)" }
            if ($dirOnly)  { return "Directory.EnumerateDirectories($path, $filterStr, $searchOpt)" }
            return "Directory.EnumerateFileSystemEntries($path, $filterStr, $searchOpt)"
        }

        'Split-Path' {
            $path = $null; $parent = $false; $leaf = $false; $ext = $false
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Parent')    { $parent = $true }
                elseif ($p.Name -eq 'Leaf')      { $leaf = $true }
                elseif ($p.Name -eq 'Extension') { $ext = $true }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }

            if ($leaf) { return "Path.GetFileName($path)" }
            if ($ext)  { return "Path.GetExtension($path)" }
            return "Path.GetDirectoryName($path)"
        }

        'ConvertTo-Json' {
            $obj = $null; $depth = $null
            foreach ($p in $Params) {
                if ($p.Name -eq 'Depth' -and $p.Value) { $depth = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'InputObject' -and $p.Value) { $obj = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $obj) { $obj = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $obj) { $obj = 'null' }

            if ($depth) {
                return "JsonSerializer.Serialize($obj, new JsonSerializerOptions { MaxDepth = $depth, WriteIndented = true })"
            }
            return "JsonSerializer.Serialize($obj, new JsonSerializerOptions { WriteIndented = true })"
        }

        'Start-Sleep' {
            $seconds = $null; $ms = $null
            foreach ($p in $Params) {
                if ($p.Name -eq 'Seconds' -and $p.Value) { $seconds = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Milliseconds' -and $p.Value) { $ms = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($null -eq $p.Name -and $null -ne $p.Value) { $seconds = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if ($Context.SharedState) { $Context.SharedState.HasAsync = $true }
            if ($ms) { return "await Task.Delay($ms)" }
            if ($seconds) { return "await Task.Delay(TimeSpan.FromSeconds($seconds))" }
            return "await Task.Delay(1000)"
        }

        'Stop-Process' {
            $id = $null; $name = $null
            foreach ($p in $Params) {
                if ($p.Name -eq 'Id' -and $p.Value) { $id = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Name' -and $p.Value) { $name = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($null -eq $p.Name -and $null -ne $p.Value) { $id = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if ($id) { return "Process.GetProcessById($id).Kill()" }
            if ($name) { return "foreach (var p in Process.GetProcessesByName($name)) p.Kill()" }
            return "/* TODO: Stop-Process */ throw new NotImplementedException()"
        }

        'Invoke-RestMethod' {
            return Convert-InvokeRestMethod -Params $Params -Context $Context
        }

        'Invoke-WebRequest' {
            return Convert-InvokeRestMethod -Params $Params -Context $Context
        }

        'Get-CimInstance' {
            $className = $null
            foreach ($p in $Params) {
                if ($p.Name -eq 'ClassName' -and $p.Value) { $className = $p.Value.Extent.Text.Trim("'", '"') }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $className) { $className = $p.Value.Extent.Text.Trim("'", '"') }
            }
            if (-not $className) { $className = 'unknown' }
            return "new ManagementObjectSearcher(""SELECT * FROM $className"").Get()"
        }

        'Import-Csv' {
            $path = $null; $delimiter = $null; $header = $null
            foreach ($p in $Params) {
                if ($p.Name -in 'Path', 'LiteralPath' -and $p.Value) { $path = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($p.Name -eq 'Delimiter' -and $p.Value) { $delimiter = $p.Value.Extent.Text.Trim("'", '"') }
                elseif ($p.Name -eq 'Header' -and $p.Value) { $header = Convert-Expression -Ast $p.Value -Context $Context }
                elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $path) { $path = Convert-Expression -Ast $p.Value -Context $Context }
            }
            if (-not $path) { $path = '""' }
            $delim = if ($delimiter) { "'$delimiter'" } else { "','" }
            return "CsvHelper.ReadCsv($path, $delim) /* TODO: implement CSV helper */"
        }

        default {
            return Convert-UnmappedCommand -CmdName $CmdName -Ast $null -Params $Params -Context $Context
        }
    }
}

function Convert-InvokeRestMethod {
    param([array]$Params, [hashtable]$Context)

    if ($Context.SharedState) { $Context.SharedState.HasAsync = $true }

    $uri = $null; $method = 'Get'; $body = $null; $contentType = $null; $headers = $null
    foreach ($p in $Params) {
        if ($p.Name -eq 'Uri' -and $p.Value)         { $uri = Convert-Expression -Ast $p.Value -Context $Context }
        elseif ($p.Name -eq 'Method' -and $p.Value)   { $method = $p.Value.Extent.Text.Trim("'", '"') }
        elseif ($p.Name -eq 'Body' -and $p.Value)     { $body = Convert-Expression -Ast $p.Value -Context $Context }
        elseif ($p.Name -eq 'ContentType' -and $p.Value) { $contentType = $p.Value.Extent.Text.Trim("'", '"') }
        elseif ($p.Name -eq 'Headers' -and $p.Value)  { $headers = Convert-Expression -Ast $p.Value -Context $Context }
        elseif ($null -eq $p.Name -and $null -ne $p.Value -and -not $uri) { $uri = Convert-Expression -Ast $p.Value -Context $Context }
    }
    if (-not $uri) { $uri = '""' }

    $csMethod = (Get-Culture).TextInfo.ToTitleCase($method.ToLowerInvariant())
    if ($body) {
        return "await httpClient.${csMethod}Async($uri, new StringContent($body, Encoding.UTF8, ""$contentType""))"
    }
    return "await httpClient.${csMethod}Async($uri)"
}

function Convert-InvocationCommand {
    param(
        [System.Management.Automation.Language.CommandAst]$Ast,
        [hashtable]$Context
    )

    $elements = @($Ast.CommandElements)
    if ($elements.Count -lt 2) {
        return Write-AiTag -TagName 'PROCESS_INVOCATION' `
            -OriginalSource $Ast.Extent.Text `
            -AstTypeName 'CommandAst' `
            -Hint 'Invocation operator with insufficient elements' `
            -Context $Context
    }

    $target = Convert-Expression -Ast $elements[1] -Context $Context
    $argParts = @()
    for ($i = 2; $i -lt $elements.Count; $i++) {
        if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst]) {
            $argParts += """$($elements[$i].ParameterName)"""
        }
        else {
            $argParts += Convert-Expression -Ast $elements[$i] -Context $Context
        }
    }
    $argStr = $argParts -join ' + " " + '

    [void]$Context.Usings.Add('System.Diagnostics')

    $bestEffort = @"
var psi = new ProcessStartInfo
{
    FileName = $target,
    Arguments = $argStr,
    UseShellExecute = false,
    RedirectStandardOutput = true,
    CreateNoWindow = true
};
using var proc = Process.Start(psi);
var output = proc!.StandardOutput.ReadToEnd();
proc.WaitForExit();
var exitCode = proc.ExitCode
"@

    return Write-AiTag -TagName 'PROCESS_INVOCATION' `
        -OriginalSource $Ast.Extent.Text `
        -AstTypeName 'CommandAst' `
        -Hint "Process invocation — verify arguments and exit code handling" `
        -BestEffort $bestEffort `
        -Context $Context
}

function Convert-UnmappedCommand {
    param(
        [string]$CmdName,
        [System.Management.Automation.Language.CommandAst]$Ast,
        [array]$Params,
        [hashtable]$Context
    )

    $srcText = if ($Ast) { $Ast.Extent.Text } else { $CmdName }

    # Detect DB2/ODBC-related commands and tag accordingly
    $db2Cmdlets = @('Invoke-Db2Query', 'Invoke-Db2QueryAny', 'Invoke-McpDb2Query')
    if ($CmdName -in $db2Cmdlets) {
        return Write-AiTag -TagName 'DB2_QUERY' `
            -OriginalSource $srcText `
            -AstTypeName 'CommandAst' `
            -Hint "DB2 query cmdlet '$CmdName' — convert to IBM.Data.Db2 (DB2Connection/DB2Command)" `
            -Context $Context
    }

    # Detect New-Object for DB2/ODBC connections
    if ($CmdName -eq 'New-Object') {
        $typeArg = Get-FirstPositionalArg -Params $Params
        if ($typeArg -match 'Odbc|DB2|OdbcConnection') {
            return Write-AiTag -TagName 'DB2_CONNECTION' `
                -OriginalSource $srcText `
                -AstTypeName 'CommandAst' `
                -Hint "ODBC/DB2 connection — convert to DB2Connection from IBM.Data.Db2" `
                -Context $Context
        }
    }

    $argParts = @()
    foreach ($p in $Params) {
        if ($p.Name) {
            $argParts += "-$($p.Name)"
        }
        if ($null -ne $p.Value) {
            $argParts += $p.Value.Extent.Text
        }
    }
    $argStr = $argParts -join ' '
    $csMethodName = Convert-FunctionNameToCSharp -Name $CmdName

    return Write-AiTag -TagName 'UNHANDLED_CMDLET' `
        -OriginalSource $srcText `
        -AstTypeName 'CommandAst' `
        -Hint "No mapping for '$CmdName' — needs manual C# conversion" `
        -BestEffort "$csMethodName($argStr)" `
        -Context $Context
}
