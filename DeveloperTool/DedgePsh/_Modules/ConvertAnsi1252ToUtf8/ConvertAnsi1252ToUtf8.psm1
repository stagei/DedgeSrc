# ConvertAnsi1252ToUtf8.psm1
# Converts a file from ANSI 1252 to UTF-8
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
    Converts a file from ANSI 1252 to UTF-8 encoding.

.DESCRIPTION
    Reads a file encoded in ANSI 1252 (Windows-1252) and converts its contents to UTF-8 encoding.
    The original file is overwritten with the converted content.

.PARAMETER convertFilePath
    The path to the file to be converted.

.EXAMPLE
    ConvertFileAnsi1252ToUtf8 -convertFilePath "C:\data\legacy.txt"
    # Converts legacy.txt from ANSI 1252 to UTF-8 encoding

.NOTES
    The function will exit if the specified file is not found.
    The original file is modified in place - no backup is created.
#>
function ConvertFileAnsi1252ToUtf8 {
	param (
		$convertFilePath
	)
    if (Test-Path $convertFilePath -PathType Leaf) {
		# Logger -message "Converting file $convertFilePath from ANSI 1252 to UTF-8"
	}
	else {
		Logger -message "File $convertFilePath not found"
		exit
	}

	# Specify the paths for the source ANSI file and the destination UTF-8 file
	$Ansi1252Encoding = [System.Text.Encoding]::GetEncoding("Windows-1252")

	$stream = New-Object System.IO.FileStream($convertFilePath, [System.IO.FileMode]::Open)
	$reader = New-Object System.IO.StreamReader($stream, $Ansi1252Encoding)
	$content = $reader.ReadToEnd()
	$reader.Close()
	$stream.Close()

	# Convert the content to UTF-8 encoding and write it to the destination file
	Set-Content -Path $convertFilePath -Value $content -Encoding UTF8
}

<#
.SYNOPSIS
    Reads an ANSI 1252 file and returns its contents as a UTF-8 string.

.DESCRIPTION
    Opens a file encoded in ANSI 1252 (Windows-1252), reads its contents,
    and converts them to UTF-8 encoding. Returns the converted content as a string
    instead of writing back to the file.

.PARAMETER fileName
    The path to the ANSI 1252 encoded file to read.

.EXAMPLE
    $content = ConvertFileToStringAnsi1252ToUtf8 -fileName "C:\data\legacy.txt"
    # Reads legacy.txt and returns its contents converted to UTF-8
#>
function ConvertFileToStringAnsi1252ToUtf8 {
	param (
		$fileName
	)
    if (Test-Path $fileName -PathType Leaf) {
		# Logger -message "Converting file $fileName from ANSI 1252 to UTF-8"
	}
	else {
		Logger -message "File $fileName not found"
		exit
	}

	# Specify the paths for the source ANSI file and the destination UTF-8 file
	$Ansi1252Encoding = [System.Text.Encoding]::GetEncoding("Windows-1252")

	$stream = New-Object System.IO.FileStream($fileName, [System.IO.FileMode]::Open)
	$reader = New-Object System.IO.StreamReader($stream, $Ansi1252Encoding)
	$content = $reader.ReadToEnd()
	$reader.Close()
	$stream.Close()

	# Convert the content to UTF-8 encoding and write it to the destination file
	$result = [System.Text.Encoding]::UTF8.GetString($Ansi1252Encoding.GetBytes($content))
	
	return $result
}

<#
.SYNOPSIS
    Converts a string from ANSI 1252 to UTF-8 encoding.

.DESCRIPTION
    Takes a string encoded in ANSI 1252 (Windows-1252) and converts it to UTF-8 encoding.
    This is useful when working with legacy text that needs to be converted to modern Unicode encoding.

.PARAMETER string
    The ANSI 1252 encoded string to convert.

.EXAMPLE
    $utf8String = ConvertStringAnsi1252ToUtf8 -string "Hello World"
    # Converts the string from ANSI 1252 to UTF-8 encoding
#>
function ConvertStringAnsi1252ToUtf8 {
	param (
		$string
	)
	$Ansi1252Encoding = [System.Text.Encoding]::GetEncoding("Windows-1252")

	# Convert the content to ANSI 1252 encoding and write it to the destination file
	$result = [System.Text.Encoding]::UTF8.GetString($Ansi1252Encoding.GetBytes($string))
	return $result
}




Export-ModuleMember -Function ConvertFileAnsi1252ToUtf8
Export-ModuleMember -Function ConvertFileToStringAnsi1252ToUtf8
Export-ModuleMember -Function ConvertStringAnsi1252ToUtf8
