# ConvertAnsi1252ToUtf8 Module

## Overview
The ConvertAnsi1252ToUtf8 module provides functionality for converting text from ANSI 1252 (Windows-1252) encoding to UTF-8 encoding. It offers functions for converting files in-place, reading files and returning UTF-8 content, and converting strings directly.

## Functions

### ConvertFileAnsi1252ToUtf8
Converts a file from ANSI 1252 to UTF-8 encoding.

#### Parameters
- **convertFilePath**: The path to the file to be converted.

#### Behavior
- Reads a file encoded in ANSI 1252 (Windows-1252) and converts its contents to UTF-8 encoding.
- The original file is overwritten with the converted content.
- The function will exit if the specified file is not found.
- No backup of the original file is created.

#### Examples
```powershell
# Convert a file from ANSI 1252 to UTF-8
ConvertFileAnsi1252ToUtf8 -convertFilePath "C:\data\legacy.txt"
```

### ConvertFileToStringAnsi1252ToUtf8
Reads an ANSI 1252 file and returns its contents as a UTF-8 string.

#### Parameters
- **fileName**: The path to the ANSI 1252 encoded file to read.

#### Behavior
- Opens a file encoded in ANSI 1252 (Windows-1252), reads its contents, and converts them to UTF-8 encoding.
- Returns the converted content as a string instead of writing back to the file.
- The function will exit if the specified file is not found.

#### Examples
```powershell
# Read a file and get its contents as UTF-8
$content = ConvertFileToStringAnsi1252ToUtf8 -fileName "C:\data\legacy.txt"
```

### ConvertStringAnsi1252ToUtf8
Converts a string from ANSI 1252 to UTF-8 encoding.

#### Parameters
- **string**: The ANSI 1252 encoded string to convert.

#### Behavior
- Takes a string encoded in ANSI 1252 (Windows-1252) and converts it to UTF-8 encoding.
- Returns the converted string.
- Useful when working with legacy text that needs to be converted to modern Unicode encoding.

#### Examples
```powershell
# Convert a string from ANSI 1252 to UTF-8
$utf8String = ConvertStringAnsi1252ToUtf8 -string "Hello World"
```

## Dependencies
- Logger module (used for logging errors)

## Version History
- 20240412 fkgeista: First version 