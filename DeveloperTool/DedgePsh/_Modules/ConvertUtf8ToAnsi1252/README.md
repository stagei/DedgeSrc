# ConvertUtf8ToAnsi1252 Module

## Overview
The ConvertUtf8ToAnsi1252 module provides functionality for converting text from UTF-8 encoding to ANSI 1252 (Windows-1252) encoding. It offers functions for converting files in-place, reading files and returning ANSI 1252 content, and converting strings directly.

## Functions

### ConvertFileUtf8ToAnsi1252
Converts a file from UTF-8 to ANSI 1252 encoding.

#### Parameters
- **convertFilePath**: The path to the file to be converted.

#### Behavior
- Reads a file encoded in UTF-8 and converts its contents to ANSI 1252 (Windows-1252) encoding.
- The original file is overwritten with the converted content.
- The function will exit if the specified file is not found.
- No backup of the original file is created.

#### Known Issues
- The current implementation has an issue with the stream reader initialization order that may cause errors when executing this function.

#### Examples
```powershell
# Convert a file from UTF-8 to ANSI 1252
ConvertFileUtf8ToAnsi1252 -convertFilePath "C:\data\myfile.txt"
```

### ConvertFileToStringUtf8ToAnsi1252
Reads a UTF-8 file and returns its contents as an ANSI 1252 string.

#### Parameters
- **fileName**: The path to the UTF-8 encoded file to read.

#### Behavior
- Opens a file encoded in UTF-8, reads its contents, and converts them to ANSI 1252 encoding.
- Returns the converted content as a string instead of writing back to the file.
- The function will exit if the specified file is not found.

#### Examples
```powershell
# Read a file and get its contents as ANSI 1252
$content = ConvertFileToStringUtf8ToAnsi1252 -fileName "C:\data\myfile.txt"
```

### ConvertStringUtf8ToAnsi1252
Converts a UTF-8 string to ANSI 1252 encoding.

#### Parameters
- **string**: The UTF-8 encoded string to convert.

#### Behavior
- Takes a string that is encoded in UTF-8 and converts it to ANSI 1252 (Windows-1252) encoding.
- Returns the converted string.
- Useful for converting text that needs to be compatible with legacy systems.

#### Examples
```powershell
# Convert a string from UTF-8 to ANSI 1252
$ansiString = ConvertStringUtf8ToAnsi1252 -string "Hello World"
```

## Dependencies
- Logger module (used for logging errors)

## Version History
- 20240412 fkgeista: First version 