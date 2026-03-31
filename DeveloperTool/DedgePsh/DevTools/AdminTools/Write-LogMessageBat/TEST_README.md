# Write-LogMessageBat Test Suite

This directory contains a comprehensive test suite for the Write-LogMessageBat logging solution.

## Test Files

### 1. `test.bat` - Simple Batch Test
A basic batch file that demonstrates the core functionality of the logging solution:
- Tests different log levels (INFO, WARNING, ERROR, SUCCESS, DEBUG)
- Tests file logging
- Tests various options (NOTIMESTAMP, NOCONSOLE)
- Shows the log file contents at the end

**Usage:**
```cmd
test.bat
```

### 2. `Test-WriteLogMessageBat.ps1` - Comprehensive PowerShell Test
A thorough PowerShell test script that validates all functionality:
- Tests the PowerShell script directly
- Tests the batch wrapper
- Validates log file creation and content format
- Provides detailed test results and statistics

**Usage:**
```powershell
.\Test-WriteLogMessageBat.ps1
```

**Parameters:**
- `-TestLogFile` - Path to test log file (default: temp directory)
- `-CleanupAfter` - Remove test log file after testing

**Examples:**
```powershell
# Basic test run
.\Test-WriteLogMessageBat.ps1

# Custom log file with cleanup
.\Test-WriteLogMessageBat.ps1 -TestLogFile "C:\temp\mytest.log" -CleanupAfter
```

### 3. `RunTests.bat` - Test Suite Runner
A batch file that runs both test scripts in sequence:
- Runs the simple batch test first
- Then runs the comprehensive PowerShell test
- Provides a summary of all test results

**Usage:**
```cmd
RunTests.bat
```

## Test Coverage

The test suite covers the following scenarios:

### PowerShell Script Tests
- ✅ Basic message logging
- ✅ Different log levels (INFO, WARNING, ERROR, DEBUG, SUCCESS)
- ✅ File logging functionality
- ✅ No timestamp option
- ✅ No console option
- ✅ Custom color support

### Batch Script Tests
- ✅ Basic batch wrapper functionality
- ✅ Parameter passing from batch to PowerShell
- ✅ File logging through batch interface
- ✅ Different log levels through batch
- ✅ Options handling (NOTIMESTAMP, NOCONSOLE, COLOR)

### Log File Content Tests
- ✅ Log file creation
- ✅ Proper timestamp format
- ✅ Correct log level formatting
- ✅ Content integrity

## Expected Output

### Successful Test Run
When all tests pass, you should see:
```
=== Test Summary ===
Total Tests: 12
Passed: 12
Failed: 0
Success Rate: 100%

All tests passed!
```

### Test Failure
If any tests fail, you'll see:
```
=== Test Summary ===
Total Tests: 12
Passed: 10
Failed: 2
Success Rate: 83.33%

Some tests failed!
```

## Troubleshooting

### Common Issues

1. **PowerShell Execution Policy**
   - Error: "execution of scripts is disabled on this system"
   - Solution: Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

2. **File Permission Issues**
   - Error: "Access to the path is denied"
   - Solution: Ensure you have write permissions to the temp directory

3. **Script Not Found**
   - Error: "The system cannot find the file specified"
   - Solution: Ensure all files are in the same directory and paths are correct

### Manual Testing

You can also test individual components manually:

```powershell
# Test PowerShell script directly
.\Write-LogMessageBat.ps1 -Message "Test message" -Level "INFO"

# Test with file logging
.\Write-LogMessageBat.ps1 -Message "File test" -Level "WARNING" -LogFile "test.log"
```

```cmd
rem Test batch script
Write-LogMessageBat.bat "Test from batch" INFO
Write-LogMessageBat.bat "File test" ERROR "test.log"
```

## Test Log Files

The tests create temporary log files in the system temp directory:
- `%TEMP%\Write-LogMessageBat-Test.log` - PowerShell test log
- `%TEMP%\test-log.txt` - Simple batch test log

These files are automatically cleaned up by the `-CleanupAfter` parameter or can be manually deleted.

## Integration with CI/CD

The test suite returns appropriate exit codes:
- `0` - All tests passed
- `1` - Some tests failed

This makes it suitable for integration with automated build and deployment pipelines.

```cmd
RunTests.bat
if %ERRORLEVEL% neq 0 (
    echo Build failed - tests did not pass
    exit /b 1
)
echo Build successful - all tests passed
``` 