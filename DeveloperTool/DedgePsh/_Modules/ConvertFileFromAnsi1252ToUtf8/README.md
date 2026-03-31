# ConvertFileFromAnsi1252ToUtf8 Module

## Overview
The ConvertFileFromAnsi1252ToUtf8 module provides functionality for converting files from ANSI 1252 (Windows-1252) encoding to UTF-8 encoding. It's designed to help with migrating legacy text files to modern Unicode encoding.

## Functions

### ConvertFileFromAnsi1252ToUtf8
Converts a file from ANSI 1252 to UTF-8 encoding.

#### Parameters
- **convertFilePath**: The path to the file to be converted.

#### Behavior
- Reads a file encoded in ANSI 1252 (Windows-1252) and converts its contents to UTF-8 encoding.
- The original file is overwritten with the converted content.
- Logs the conversion process using the Logger module.
- The function will exit if the specified file is not found.
- No backup of the original file is created.

#### Examples
```powershell
# Convert a file from ANSI 1252 to UTF-8
ConvertFileFromAnsi1252ToUtf8 -convertFilePath "C:\data\legacy.txt"
```

## Dependencies
- Logger module (used for logging the conversion process and errors)

## Version History
- 20240115 fkgeista: First version 