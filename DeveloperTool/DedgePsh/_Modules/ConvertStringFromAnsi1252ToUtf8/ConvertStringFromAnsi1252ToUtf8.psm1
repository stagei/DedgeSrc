# ConvertStringFromAnsi1252ToUtf8.psm1
# Converts a file from ANSI 1252 to UTF-8
#
# Changelog:
# ------------------------------------------------------------------------------
# 20240115 fkgeista Første versjon
# ------------------------------------------------------------------------------

$modulesToImport = @("GlobalFunctions", "Logger")
foreach ($moduleName in $modulesToImport) {
  $loadedModule = Get-Module -Name $moduleName
  if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
  else {
    Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
  }
} 
  

<#
.SYNOPSIS
    Converts a string from ANSI 1252 to UTF-8 encoding.

.DESCRIPTION
    Takes a string encoded in ANSI 1252 (Windows-1252) and attempts to convert it to UTF-8 encoding
    by treating it as a stream. Note that this implementation may not correctly handle all conversion
    scenarios and should be used with caution.

.PARAMETER convertString
    The ANSI 1252 encoded string to convert.

.EXAMPLE
    $utf8String = ConvertStringFromAnsi1252ToUtf8 -convertString "Hello World"
    # Attempts to convert the string from ANSI 1252 to UTF-8 encoding

.EXAMPLE
    $text = Get-Content -Path "legacy.txt"
    $converted = ConvertStringFromAnsi1252ToUtf8 -convertString $text
    # Attempts to convert content from a file from ANSI 1252 to UTF-8

.NOTES
    The current implementation has limitations and may not correctly convert all strings.
    Consider using the ConvertAnsi1252ToUtf8 module's ConvertStringAnsi1252ToUtf8 function
    for more reliable string conversion.
#>
function ConvertStringFromAnsi1252ToUtf8 {
	param (
		$convertString
	)
	# Specify the paths for the source ANSI file and the destination UTF-8 file

	$reader = New-Object System.IO.StreamReader($convertString, [System.Text.Encoding]::GetEncoding("Windows-1252"))
	$content = $reader.ReadToEnd()
	$reader.Close()

	return $content
}


Export-ModuleMember -Function ConvertStringFromAnsi1252ToUtf8
