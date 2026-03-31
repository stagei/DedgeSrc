function Resolve-TypeName {
    <#
    .SYNOPSIS
        Maps a PowerShell type constraint or accelerator name to its C# equivalent.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PsTypeName
    )

    # Only strip leading [ and trailing ] that wrap the whole type (e.g. [string])
    # but NOT array brackets like int[]
    $cleaned = $PsTypeName.Trim()
    if ($cleaned.StartsWith('[') -and $cleaned.EndsWith(']') -and -not $cleaned.EndsWith('[]')) {
        $cleaned = $cleaned.Substring(1, $cleaned.Length - 2)
    }

    $map = @{
        'string'                                = 'string'
        'System.String'                         = 'string'
        'int'                                   = 'int'
        'int32'                                 = 'int'
        'System.Int32'                          = 'int'
        'int64'                                 = 'long'
        'long'                                  = 'long'
        'System.Int64'                          = 'long'
        'double'                                = 'double'
        'System.Double'                         = 'double'
        'float'                                 = 'float'
        'System.Single'                         = 'float'
        'decimal'                               = 'decimal'
        'System.Decimal'                        = 'decimal'
        'bool'                                  = 'bool'
        'boolean'                               = 'bool'
        'System.Boolean'                        = 'bool'
        'switch'                                = 'bool'
        'SwitchParameter'                       = 'bool'
        'System.Management.Automation.SwitchParameter' = 'bool'
        'byte'                                  = 'byte'
        'System.Byte'                           = 'byte'
        'char'                                  = 'char'
        'System.Char'                           = 'char'
        'datetime'                              = 'DateTime'
        'System.DateTime'                       = 'DateTime'
        'timespan'                              = 'TimeSpan'
        'System.TimeSpan'                       = 'TimeSpan'
        'guid'                                  = 'Guid'
        'System.Guid'                           = 'Guid'
        'uri'                                   = 'Uri'
        'System.Uri'                            = 'Uri'
        'regex'                                 = 'Regex'
        'System.Text.RegularExpressions.Regex'  = 'Regex'
        'void'                                  = 'void'
        'System.Void'                           = 'void'
        'object'                                = 'object'
        'System.Object'                         = 'object'
        'psobject'                              = 'object'
        'PSCustomObject'                        = 'Dictionary<string, object?>'
        'hashtable'                             = 'Dictionary<string, object?>'
        'System.Collections.Hashtable'          = 'Dictionary<string, object?>'
        'ordered'                               = 'OrderedDictionary'
        'System.Collections.Specialized.OrderedDictionary' = 'OrderedDictionary'
        'array'                                 = 'object[]'
        'object[]'                              = 'object[]'
        'string[]'                              = 'string[]'
        'int[]'                                 = 'int[]'
        'int32[]'                               = 'int[]'
        'byte[]'                                = 'byte[]'
        'xml'                                   = 'XmlDocument'
        'System.Xml.XmlDocument'                = 'XmlDocument'
        'ipaddress'                             = 'System.Net.IPAddress'
        'mailaddress'                           = 'System.Net.Mail.MailAddress'
        'securestring'                          = 'SecureString'
        'System.Security.SecureString'          = 'SecureString'
        'scriptblock'                           = 'Func<object>'
        'System.Management.Automation.ScriptBlock' = 'Func<object>'
    }

    if ($map.ContainsKey($cleaned)) {
        return $map[$cleaned]
    }

    # Generic collections: List[T], HashSet[T], Dictionary[K,V], etc.
    # PS uses [System.Collections.Generic.List[string]] or [List[string]]
    if ($cleaned -match '^(?:System\.Collections\.Generic\.)?List\[(.+)\]$') {
        $inner = Resolve-TypeName -PsTypeName $Matches[1]
        return "List<$inner>"
    }
    if ($cleaned -match '^(?:System\.Collections\.Generic\.)?HashSet\[(.+)\]$') {
        $inner = Resolve-TypeName -PsTypeName $Matches[1]
        return "HashSet<$inner>"
    }
    if ($cleaned -match '^(?:System\.Collections\.Generic\.)?Dictionary\[(.+),\s*(.+)\]$') {
        $k = Resolve-TypeName -PsTypeName $Matches[1]
        $v = Resolve-TypeName -PsTypeName $Matches[2]
        return "Dictionary<$k, $v>"
    }

    # ArrayList
    if ($cleaned -match '(?:System\.Collections\.)?ArrayList') {
        return 'List<object>'
    }

    # Array notation: typename[]
    if ($cleaned -match '^(.+)\[\]$') {
        $inner = Resolve-TypeName -PsTypeName $Matches[1]
        return "$($inner)[]"
    }

    # Nullable: Nullable[T]
    if ($cleaned -match '^(?:System\.)?Nullable\[(.+)\]$') {
        $inner = Resolve-TypeName -PsTypeName $Matches[1]
        return "$($inner)?"
    }

    # Pass through .NET fully-qualified names as-is
    if ($cleaned -match '\.') {
        return $cleaned
    }

    # Unknown single-word type: return as-is, capitalised
    return $cleaned
}
