# ConvertUtf8ToAnsi1252.psm1
# Converts a file from UTF-8 To ANSI 1252
#
# Changelog:
# ------------------------------------------------------------------------------
# 20240412 fkgeista Første versjon
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
    Provides utilities for converting text and files from UTF-8 to ANSI 1252 encoding.

.DESCRIPTION
    This module offers functions to convert text content from UTF-8 encoding to ANSI 1252 (Windows-1252)
    encoding. It supports file conversion, string conversion, and reading files with encoding conversion.
    Useful for ensuring compatibility with legacy systems that require ANSI 1252 encoding.

.EXAMPLE
    ConvertFileUtf8ToAnsi1252 -convertFilePath "C:\data\myfile.txt"
    # Converts a file from UTF-8 to ANSI 1252 encoding

.EXAMPLE
    $ansiString = ConvertStringUtf8ToAnsi1252 -string "Hello World"
    # Converts a string from UTF-8 to ANSI 1252 encoding
#>

<#
.SYNOPSIS
    Converts a file from UTF-8 to ANSI 1252 encoding.

.DESCRIPTION
    Reads a file encoded in UTF-8 and converts its contents to ANSI 1252 (Windows-1252) encoding.
    The original file is overwritten with the converted content.
    
    Note: The current implementation has an issue with the stream reader initialization order
    that may cause errors when executing this function.

.PARAMETER convertFilePath
    The path to the file to be converted.

.EXAMPLE
    ConvertFileUtf8ToAnsi1252 -convertFilePath "C:\data\myfile.txt"
    # Converts myfile.txt from UTF-8 to ANSI 1252 encoding

.NOTES
    The function will exit if the specified file is not found.
    The original file is modified in place - no backup is created.
#>
function ConvertFileUtf8ToAnsi1252 {
	param (
		$convertFilePath
	)
    if (Test-Path $convertFilePath -PathType Leaf) {
		# Logger -message "Converting file $convertFilePath from UTF-8 to ANSI 1252"
	}
	else {
		Logger -message "File $convertFilePath not found"
		exit
	}

	$Ansi1252Encoding = [System.Text.Encoding]::GetEncoding("Windows-1252")
	# Specify the paths for the source UTF-8 file and the destination ANSI file
	$reader = New-Object System.IO.StreamReader($stream, $Ansi1252Encoding)

	$stream = New-Object System.IO.FileStream($convertFilePath, [System.IO.FileMode]::Open)
	$reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
	$content = $reader.ReadToEnd()
	$reader.Close()
	$stream.Close()

	# Convert the content to ANSI 1252 encoding and write it to the destination file
	Set-Content -Path $convertFilePath -Value $content -Encoding $Ansi1252Encoding
}

<#
.SYNOPSIS
    Reads a UTF-8 file and returns its contents as an ANSI 1252 string.

.DESCRIPTION
    Opens a file encoded in UTF-8, reads its contents, and converts them to ANSI 1252 encoding.
    Returns the converted content as a string instead of writing back to the file.

.PARAMETER fileName
    The path to the UTF-8 encoded file to read.

.EXAMPLE
    $content = ConvertFileToStringUtf8ToAnsi1252 -fileName "C:\data\myfile.txt"
    # Reads myfile.txt and returns its contents converted to ANSI 1252
#>
function ConvertFileToStringUtf8ToAnsi1252 {
	param (
		$fileName
	)
    if (Test-Path $fileName -PathType Leaf) {
		# Logger -message "Converting file $fileName from UTF-8 to ANSI 1252"
	}
	else {
		Logger -message "File $fileName not found"
		exit
	}

	# Specify the paths for the source UTF-8 file and the destination ANSI file
	$Ansi1252Encoding = [System.Text.Encoding]::GetEncoding("Windows-1252")

	$stream = New-Object System.IO.FileStream($fileName, [System.IO.FileMode]::Open)
	$reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
	$content = $reader.ReadToEnd()
	$reader.Close()
	$stream.Close()

	# Convert the content to ANSI 1252 encoding and write it to the destination file
	$result = [System.Text.Encoding]::Default.GetString($Ansi1252Encoding.GetBytes($content))
	
	return $result
}

<#
.SYNOPSIS
    Converts a UTF-8 string to ANSI 1252 encoding.

.DESCRIPTION
    Takes a string that is encoded in UTF-8 and converts it to ANSI 1252 (Windows-1252) encoding.
    Useful for converting text that needs to be compatible with legacy systems.

.PARAMETER string
    The UTF-8 encoded string to convert.

.EXAMPLE
    $ansiString = ConvertStringUtf8ToAnsi1252 -string "Hello World"
    # Converts the string from UTF-8 to ANSI 1252 encoding
#>
function ConvertStringUtf8ToAnsi1252 {
	param (
		$string
	)
	$Ansi1252Encoding = [System.Text.Encoding]::GetEncoding("Windows-1252")

	# Convert the content to ANSI 1252 encoding and write it to the destination file
	$result = $Ansi1252Encoding.GetString([System.Text.Encoding]::UTF8.GetBytes($string))
	return $result
}



Export-ModuleMember -Function ConvertFileUtf8ToAnsi1252
Export-ModuleMember -Function ConvertFileToStringUtf8ToAnsi1252
Export-ModuleMember -Function ConvertStringUtf8ToAnsi1252


