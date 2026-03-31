#Requires -Module Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\PwshToCSharpConverter.psm1') -Force -ErrorAction Stop
}

Describe 'ConvertTo-CSharpSource' {

    Context 'Parameter blocks' {

        It 'converts typed parameters with defaults' {
            $cs = ConvertTo-CSharpSource -InputCode 'param([string]$Name, [int]$Count = 5)' -ClassName 'Test'
            $cs | Should -Match 'string name'
            $cs | Should -Match 'int count = 5'
        }

        It 'converts switch parameters to bool' {
            $cs = ConvertTo-CSharpSource -InputCode 'param([switch]$Force)' -ClassName 'Test'
            $cs | Should -Match 'bool force = false'
        }

        It 'converts mandatory parameters without defaults' {
            $cs = ConvertTo-CSharpSource -InputCode 'param([Parameter(Mandatory)][string]$Path)' -ClassName 'Test'
            $cs | Should -Match 'string path'
        }

        It 'generates constructor from script params' {
            $cs = ConvertTo-CSharpSource -InputCode 'param([string]$A, [int]$B)' -ClassName 'MyClass'
            $cs | Should -Match 'public MyClass\(string a, int b\)'
            $cs | Should -Match '_a = a;'
        }
    }

    Context 'Function definitions' {

        It 'converts function to method' {
            $cs = ConvertTo-CSharpSource -InputCode 'function Get-Data { param([string]$Key) return $Key }' -ClassName 'Test'
            $cs | Should -Match 'public object GetData\(string key\)'
            $cs | Should -Match 'return key;'
        }

        It 'converts verb-noun function names to PascalCase' {
            $cs = ConvertTo-CSharpSource -InputCode 'function Test-Connection { }' -ClassName 'Test'
            $cs | Should -Match 'TestConnection'
        }
    }

    Context 'Control flow' {

        It 'converts if/elseif/else' {
            $ps = @'
if ($x -eq 1) { $a = 'one' }
elseif ($x -eq 2) { $a = 'two' }
else { $a = 'other' }
'@
            $cs = ConvertTo-CSharpSource -InputCode $ps -ClassName 'Test'
            $cs | Should -Match 'if \(x == 1\)'
            $cs | Should -Match 'else if \(x == 2\)'
            $cs | Should -Match 'else'
        }

        It 'converts foreach loop' {
            $cs = ConvertTo-CSharpSource -InputCode 'foreach ($item in $list) { Write-Host $item }' -ClassName 'Test'
            $cs | Should -Match 'foreach \(var item in list\)'
        }

        It 'converts try/catch' {
            $ps = 'try { $x = 1 } catch { Write-Host "error" }'
            $cs = ConvertTo-CSharpSource -InputCode $ps -ClassName 'Test'
            $cs | Should -Match 'try'
            $cs | Should -Match 'catch \(Exception ex\)'
        }

        It 'converts return statements' {
            $cs = ConvertTo-CSharpSource -InputCode 'function Foo { return 42 }' -ClassName 'Test'
            $cs | Should -Match 'return 42;'
        }
    }

    Context 'Expressions' {

        It 'converts PS variables to camelCase' {
            $cs = ConvertTo-CSharpSource -InputCode '$myVariable = 10' -ClassName 'Test'
            $cs | Should -Match 'myVariable'
        }

        It 'converts $true/$false/$null' {
            $cs = ConvertTo-CSharpSource -InputCode '$a = $true; $b = $false; $c = $null' -ClassName 'Test'
            $cs | Should -Match '= true;'
            $cs | Should -Match '= false;'
            $cs | Should -Match '= null;'
        }

        It 'converts comparison operators' {
            $cs = ConvertTo-CSharpSource -InputCode 'if ($a -eq $b) { }' -ClassName 'Test'
            $cs | Should -Match 'a == b'
        }

        It 'converts -match to Regex.IsMatch' {
            $cs = ConvertTo-CSharpSource -InputCode 'if ($s -match "pattern") { }' -ClassName 'Test'
            $cs | Should -Match 'Regex\.IsMatch'
        }

        It 'converts string interpolation' {
            $cs = ConvertTo-CSharpSource -InputCode 'Write-Host "Hello $Name"' -ClassName 'Test'
            $cs | Should -Match '\$"Hello \{name\}"'
        }

        It 'converts hashtable to Dictionary' {
            $cs = ConvertTo-CSharpSource -InputCode '$h = @{ Key = "value"; Num = 42 }' -ClassName 'Test'
            $cs | Should -Match 'Dictionary<string, object\?>'
        }
    }

    Context 'Cmdlet mapping' {

        It 'maps Write-LogMessage to NLog' {
            $cs = ConvertTo-CSharpSource -InputCode 'Write-LogMessage "test" -Level INFO' -ClassName 'Test'
            $cs | Should -Match 'Logger\.Info\('
        }

        It 'maps Get-Content -Raw to File.ReadAllText' {
            $cs = ConvertTo-CSharpSource -InputCode '$x = Get-Content -LiteralPath $path -Raw' -ClassName 'Test'
            $cs | Should -Match 'File\.ReadAllText\('
        }

        It 'maps Test-Path -PathType Leaf to File.Exists' {
            $cs = ConvertTo-CSharpSource -InputCode 'Test-Path -LiteralPath $p -PathType Leaf' -ClassName 'Test'
            $cs | Should -Match 'File\.Exists\('
        }

        It 'maps Join-Path to Path.Combine' {
            $cs = ConvertTo-CSharpSource -InputCode '$x = Join-Path $a $b' -ClassName 'Test'
            $cs | Should -Match 'Path\.Combine\('
        }

        It 'maps ConvertFrom-Json to JsonSerializer.Deserialize' {
            $cs = ConvertTo-CSharpSource -InputCode '$x = ConvertFrom-Json $raw' -ClassName 'Test'
            $cs | Should -Match 'JsonSerializer\.Deserialize'
        }

        It 'maps Start-Sleep -Seconds to Task.Delay' {
            $cs = ConvertTo-CSharpSource -InputCode 'Start-Sleep -Seconds 5' -ClassName 'Test'
            $cs | Should -Match 'Task\.Delay'
        }
    }

    Context 'Pipeline conversion' {

        It 'converts Where-Object with script block to LINQ Where' {
            $cs = ConvertTo-CSharpSource -InputCode '$result = $items | Where-Object { $_.Name -eq "test" }' -ClassName 'Test'
            $cs | Should -Match '\.Where\('
        }

        It 'converts ForEach-Object to LINQ Select' {
            $cs = ConvertTo-CSharpSource -InputCode '$result = $items | ForEach-Object { $_.FullName }' -ClassName 'Test'
            $cs | Should -Match '\.Select\('
        }

        It 'converts Sort-Object to OrderBy' {
            $cs = ConvertTo-CSharpSource -InputCode '$result = $items | Sort-Object Name' -ClassName 'Test'
            $cs | Should -Match '\.OrderBy\('
        }
    }

    Context 'Usings collection' {

        It 'adds NLog using when Write-LogMessage is used' {
            $cs = ConvertTo-CSharpSource -InputCode 'Write-LogMessage "x" -Level INFO' -ClassName 'Test'
            $cs | Should -Match 'using NLog;'
        }

        It 'adds System.Text.Json using when ConvertFrom-Json is used' {
            $cs = ConvertTo-CSharpSource -InputCode '$j = ConvertFrom-Json $x' -ClassName 'Test'
            $cs | Should -Match 'using System\.Text\.Json;'
        }
    }

    Context 'Type resolution' {

        It 'maps [string] to string' {
            $cs = ConvertTo-CSharpSource -InputCode 'param([string]$X)' -ClassName 'Test'
            $cs | Should -Match 'string x'
        }

        It 'maps [int[]] to int[]' {
            $cs = ConvertTo-CSharpSource -InputCode 'param([int[]]$Ids)' -ClassName 'Test'
            $cs | Should -Match 'int\[\] ids'
        }

        It 'maps [hashtable] to Dictionary' {
            $cs = ConvertTo-CSharpSource -InputCode 'param([hashtable]$Config)' -ClassName 'Test'
            $cs | Should -Match 'Dictionary<string, object\?> config'
        }
    }

    Context 'File-based conversion' {

        It 'converts a file and sets class name from filename' {
            $testFile = Join-Path $TestDrive 'MyTestScript.ps1'
            'param([string]$Name) Write-Host $Name' | Set-Content $testFile
            $cs = ConvertTo-CSharpSource -InputFile $testFile
            $cs | Should -Match 'class MyTestScript'
        }
    }

    Context 'Static type calls (fix: typeof)' {

        It 'converts [string]::IsNullOrEmpty to string.IsNullOrEmpty' {
            $cs = ConvertTo-CSharpSource -InputCode 'if ([string]::IsNullOrEmpty($x)) { }' -ClassName 'Test'
            $cs | Should -Match 'string\.IsNullOrEmpty\(x\)'
            $cs | Should -Not -Match 'typeof'
        }

        It 'converts [Math]::Round to Math.Round' {
            $cs = ConvertTo-CSharpSource -InputCode '$y = [Math]::Round($x, 2)' -ClassName 'Test'
            $cs | Should -Match 'Math\.Round\(x, 2\)'
            $cs | Should -Not -Match 'typeof'
        }

        It 'converts static property access [DateTime]::Now' {
            $cs = ConvertTo-CSharpSource -InputCode '$d = [DateTime]::Now' -ClassName 'Test'
            $cs | Should -Match 'DateTime\.Now'
            $cs | Should -Not -Match 'typeof'
        }
    }

    Context 'Truthiness wrapping' {

        It 'wraps simple variable in null check for if condition' {
            $cs = ConvertTo-CSharpSource -InputCode 'if ($name) { $x = 1 }' -ClassName 'Test'
            $cs | Should -Match 'IsNullOrEmpty\(name\)'
        }

        It 'wraps negated variable: if (-not $x)' {
            $cs = ConvertTo-CSharpSource -InputCode 'if (-not $x) { $a = 1 }' -ClassName 'Test'
            $cs | Should -Match 'IsNullOrEmpty\(x\)'
        }

        It 'leaves comparison expressions unchanged' {
            $cs = ConvertTo-CSharpSource -InputCode 'if ($x -eq 1) { }' -ClassName 'Test'
            $cs | Should -Match 'x == 1'
            $cs | Should -Not -Match 'IsNullOrEmpty'
        }

        It 'leaves method calls unchanged in conditions' {
            $cs = ConvertTo-CSharpSource -InputCode 'if (Test-Path $p) { }' -ClassName 'Test'
            $cs | Should -Match 'Path\.Exists\('
            $cs | Should -Not -Match 'IsNullOrEmpty'
        }
    }

    Context 'Array initialization (fix: semicolons)' {

        It 'uses commas not semicolons in array literals' {
            $cs = ConvertTo-CSharpSource -InputCode '$arr = @("a", "b", "c")' -ClassName 'Test'
            $cs | Should -Match 'new List<object>'
            $cs | Should -Not -Match ';.*"b"'
        }
    }

    Context 'PS automatic variables' {

        It 'emits ErrorActionPreference as comment' {
            $cs = ConvertTo-CSharpSource -InputCode '$ErrorActionPreference = "Stop"' -ClassName 'Test'
            $cs | Should -Match '// PS: \$ErrorActionPreference'
            $cs | Should -Not -Match 'var.*ErrorActionPreference'
        }

        It 'emits ProgressPreference as comment' {
            $cs = ConvertTo-CSharpSource -InputCode '$ProgressPreference = "SilentlyContinue"' -ClassName 'Test'
            $cs | Should -Match '// PS: \$ProgressPreference'
        }
    }

    Context 'Complex LHS assignment (fix: var on member access)' {

        It 'does not emit var for member access assignment' {
            $cs = ConvertTo-CSharpSource -InputCode '$obj = @{}; $obj.Name = "test"' -ClassName 'Test'
            $cs | Should -Not -Match 'var obj\.Name'
        }
    }

    Context 'Async detection' {

        It 'emits async Task<int> Run when Start-Sleep is used' {
            $cs = ConvertTo-CSharpSource -InputCode 'Start-Sleep -Seconds 5' -ClassName 'Test'
            $cs | Should -Match 'async Task<int> Run'
            $cs | Should -Match 'await Task\.Delay'
        }

        It 'emits async Task<int> Run when Invoke-RestMethod is used' {
            $cs = ConvertTo-CSharpSource -InputCode '$r = Invoke-RestMethod -Uri "http://x"' -ClassName 'Test'
            $cs | Should -Match 'async Task<int> Run'
            $cs | Should -Match 'await httpClient'
        }

        It 'emits plain int Run when no async cmdlets used' {
            $cs = ConvertTo-CSharpSource -InputCode '$x = 1' -ClassName 'Test'
            $cs | Should -Match 'public int Run\(\)'
            $cs | Should -Not -Match 'async'
        }
    }

    Context 'Regex usings' {

        It 'adds System.Text.RegularExpressions when -match is used' {
            $cs = ConvertTo-CSharpSource -InputCode 'if ($s -match "^test") { }' -ClassName 'Test'
            $cs | Should -Match 'using System\.Text\.RegularExpressions;'
            $cs | Should -Match 'Regex\.IsMatch'
        }
    }

    Context 'Is/IsNot operator (fix: typeof strip)' {

        It 'converts -is without typeof wrapper' {
            $cs = ConvertTo-CSharpSource -InputCode 'if ($x -is [string]) { }' -ClassName 'Test'
            $cs | Should -Match 'is string'
            $cs | Should -Not -Match 'typeof'
        }
    }

    Context 'AI tag emission' {

        It 'emits AI:UNHANDLED_CMDLET for unmapped commands' {
            $cs = ConvertTo-CSharpSource -InputCode 'Send-MailMessage -To "x@y.z"' -ClassName 'Test'
            $cs | Should -Match 'AI:UNHANDLED_CMDLET'
            $cs | Should -Match 'CONVERSION SUMMARY'
        }

        It 'emits AI:PIPELINE_COMPLEX for unhandled pipeline steps' {
            $cs = ConvertTo-CSharpSource -InputCode '$x = $items | Tee-Object -Variable backup' -ClassName 'Test'
            $cs | Should -Match 'AI:PIPELINE_COMPLEX'
        }

        It 'emits AI:PROCESS_INVOCATION for & operator' {
            $cs = ConvertTo-CSharpSource -InputCode '& $script -Arg1 "value"' -ClassName 'Test'
            $cs | Should -Match 'AI:PROCESS_INVOCATION'
            $cs | Should -Match 'ProcessStartInfo'
        }

        It 'counts AI tags in conversion summary' {
            $cs = ConvertTo-CSharpSource -InputCode 'Send-MailMessage -To "a"; Invoke-SqlCmd -Query "SELECT 1"' -ClassName 'Test'
            $cs | Should -Match 'AI tags remaining: [1-9]'
        }
    }

    Context 'DB2 detection' {

        It 'tags Invoke-Db2Query as AI:DB2_QUERY' {
            $cs = ConvertTo-CSharpSource -InputCode 'Invoke-Db2Query -Query "SELECT 1"' -ClassName 'Test'
            $cs | Should -Match 'AI:DB2_QUERY'
        }

        It 'tags New-Object OdbcConnection as AI:DB2_CONNECTION' {
            $cs = ConvertTo-CSharpSource -InputCode 'New-Object System.Data.Odbc.OdbcConnection("DSN=TEST")' -ClassName 'Test'
            $cs | Should -Match 'AI:DB2_CONNECTION'
        }
    }

    Context 'Pipeline improvements' {

        It 'converts Group-Object to GroupBy' {
            $cs = ConvertTo-CSharpSource -InputCode '$g = $items | Group-Object Category' -ClassName 'Test'
            $cs | Should -Match '\.GroupBy\('
        }
    }
}
