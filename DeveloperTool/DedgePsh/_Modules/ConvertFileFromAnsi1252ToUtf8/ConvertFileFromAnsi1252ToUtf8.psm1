# ConvertFileFromAnsi1252ToUtf8.psm1
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
    Converts a file from ANSI 1252 to UTF-8 encoding.

.DESCRIPTION
    Reads a file encoded in ANSI 1252 (Windows-1252) and converts its contents to UTF-8 encoding.
    The original file is overwritten with the converted content.
    Logs the conversion process using the Logger module.

.PARAMETER convertFilePath
    The path to the file to be converted.

.EXAMPLE
    ConvertFileFromAnsi1252ToUtf8 -convertFilePath "C:\data\legacy.txt"
    # Converts legacy.txt from ANSI 1252 to UTF-8 encoding

.NOTES
    The function will exit if the specified file is not found.
    The original file is modified in place - no backup is created.
#>
function ConvertFileFromAnsi1252ToUtf8 {
	param (
		$convertFilePath
	)
    if (Test-Path $convertFilePath -PathType Leaf) {
		Logger -message "Converting file $convertFilePath from ANSI 1252 to UTF-8"
	}
	else {
		Logger -message "File $convertFilePath not found"
		exit
	}

	# Specify the paths for the source ANSI file and the destination UTF-8 file

	$stream = New-Object System.IO.FileStream($convertFilePath, [System.IO.FileMode]::Open)
	$reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::GetEncoding("Windows-1252"))
	$content = $reader.ReadToEnd()
	$reader.Close()
	$stream.Close()

	# Convert the content to UTF-8 encoding and write it to the destination file
	Set-Content -Path $convertFilePath -Value $content -Encoding UTF8
}


Export-ModuleMember -Function ConvertFileFromAnsi1252ToUtf8
