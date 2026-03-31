# DedgeConnection Test Execution Guide

## Overview

This guide provides step-by-step instructions for testing the `DedgeConnection` rewrite to ensure it works correctly with the JSON configuration file while maintaining backward compatibility.

## Prerequisites

1. **Environment Setup**:
   - .NET 8.0 SDK installed
   - Access to the DedgeCommon project directory
   - Network access to the JSON configuration file location
   - Database access for integration tests

2. **Required Files**:
   - `DedgeConnectionTestProgram.cs` - Custom test program
   - `run_DedgeConnection_tests.ps1` - PowerShell test runner script
   - Existing test projects in the solution

## Test Execution Methods

### Method 1: Automated Test Runner (Recommended)

The PowerShell script provides comprehensive testing with detailed reporting:

```powershell
# Run all tests
.\run_DedgeConnection_tests.ps1

# Run with verbose output
.\run_DedgeConnection_tests.ps1 -Verbose

# Skip specific test phases
.\run_DedgeConnection_tests.ps1 -SkipUnitTests
.\run_DedgeConnection_tests.ps1 -SkipIntegrationTests
.\run_DedgeConnection_tests.ps1 -SkipCustomTests
```

### Method 2: Manual Test Execution

#### Step 1: Unit Tests
```bash
# Build and run unit tests
dotnet build DedgeCommonTest/DedgeCommonTest.csproj
dotnet test DedgeCommonTest/DedgeCommonTest.csproj --verbosity normal
```

#### Step 2: Integration Tests
```bash
# Run the main verification program
dotnet run --project DedgeCommonVerifyFkDatabaseHandler/VerifyFunctionality.csproj
```

#### Step 3: Custom DedgeConnection Tests
```bash
# Create and run custom test project
mkdir DedgeConnectionTest
cd DedgeConnectionTest
dotnet new console
# Copy DedgeConnectionTestProgram.cs as Program.cs
# Add project reference to DedgeCommon
dotnet run
```

#### Step 4: Simple Test
```bash
# Run the simple test program
dotnet run --project TestNoNameSpace/TestNoNameSpace.csproj
```

## Test Phases Explained

### Phase 1: Unit Tests
- **Purpose**: Verify basic functionality of individual methods
- **Tests**: Connection key creation, provider detection, version handling
- **Expected**: All tests should pass without modification

### Phase 2: Integration Tests
- **Purpose**: Verify end-to-end functionality with real database operations
- **Tests**: Database connections, SQL execution, transaction handling
- **Expected**: All database operations should complete successfully

### Phase 3: Custom DedgeConnection Tests
- **Purpose**: Comprehensive testing of all DedgeConnection methods
- **Tests**: All public methods, error handling, edge cases
- **Expected**: All methods should work identically to the original implementation

### Phase 4: Simple Test
- **Purpose**: Basic functionality verification
- **Tests**: Simple connection key creation and logging
- **Expected**: Program should run without errors

## Expected Test Results

### Successful Test Outcomes:
```
=== Test Summary ===
Total tests run: 4
Passed: 4
Failed: 0
Success rate: 100.0%

Detailed Results:
  ✓ Unit Tests
  ✓ Integration Tests
  ✓ Custom DedgeConnection Tests
  ✓ Simple Test Program

🎉 All tests passed! DedgeConnection rewrite is working correctly.
```

### Connection String Validation:
- **DB2 Format**: `Database=BASISTST;Server=t-no1fkmtst-db.DEDGE.fk.no:3701;UID=db2nt;PWD=ntdb2;`
- **SQL Server Format**: `Database=DBQA;Server=p-Dedge-vm02.DEDGE.fk.no:50000;User Id=db2nt;Password=ntdb2;`

### Database Name Validation:
- FKM DEV: Should use "FKAVDNT" or "FKMDEV"
- FKM TST: Should use "BASISTST" or "FKMTST"
- FKM PRD: Should use "BASISPRO" or "FKMPRD"
- INL PRD: Should use "FKKONTO" or "INLPRD"

## Troubleshooting

### Common Issues and Solutions

#### 1. Configuration File Not Found
```
Error: Configuration file not found: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json
```
**Solution**: Verify network access and file path. Check if the file exists and is accessible.

#### 2. JSON Parsing Errors
```
Error: Invalid JSON in configuration file
```
**Solution**: Validate the JSON file format. Use a JSON validator to check for syntax errors.

#### 3. Database Connection Failures
```
Error: Failed to execute query
```
**Solution**: Verify database connectivity and credentials. Check if the database servers are accessible.

#### 4. Missing Dependencies
```
Error: Package reference not found
```
**Solution**: Restore NuGet packages: `dotnet restore`

#### 5. Build Errors
```
Error: Build failed
```
**Solution**: Clean and rebuild: `dotnet clean && dotnet build`

### Debug Mode

Enable detailed logging for troubleshooting:

```csharp
// In the test program, enable debug logging
DedgeNLog.SetFileLogLevels(DedgeNLog.LogLevel.Debug, DedgeNLog.LogLevel.Fatal);
DedgeNLog.SetConsoleLogLevels(DedgeNLog.LogLevel.Debug, DedgeNLog.LogLevel.Fatal);
```

## Test Data Validation

### Connection Information Validation:
```csharp
// Verify connection info structure
var connInfo = DedgeConnection.GetConnectionStringInfo(FkEnvironment.DEV, FkApplication.FKM);
Assert.IsNotNull(connInfo.Database);
Assert.IsNotNull(connInfo.Server);
Assert.IsNotNull(connInfo.UID);
Assert.IsNotNull(connInfo.PWD);
Assert.AreEqual(DatabaseProvider.DB2, connInfo.Provider);
```

### Version Handling Validation:
```csharp
// Verify version-specific connections
var v1Conn = DedgeConnection.GetConnectionString(FkEnvironment.DEV, FkApplication.FKM, "2.0");
var v2Conn = DedgeConnection.GetConnectionString(FkEnvironment.DEV, FkApplication.FKM, "2.0");
Assert.AreNotEqual(v1Conn, v2Conn);
```

## Performance Considerations

### Expected Performance:
- **Configuration Loading**: < 1 second for initial load
- **Connection String Generation**: < 10ms per call
- **Dictionary Lookup**: < 1ms per call
- **Memory Usage**: Minimal increase due to caching

### Performance Monitoring:
```csharp
var stopwatch = Stopwatch.StartNew();
var connInfo = DedgeConnection.GetConnectionStringInfo(FkEnvironment.DEV, FkApplication.FKM);
stopwatch.Stop();
Console.WriteLine($"Connection info retrieval took: {stopwatch.ElapsedMilliseconds}ms");
```

## Rollback Plan

If tests fail after the rewrite:

1. **Immediate Actions**:
   - Revert to original hardcoded implementation
   - Document specific failure points
   - Analyze error logs

2. **Investigation Steps**:
   - Check JSON file format and accessibility
   - Verify enum parsing logic
   - Test configuration loading in isolation
   - Validate connection string generation

3. **Incremental Fixes**:
   - Fix one issue at a time
   - Re-test after each fix
   - Maintain backward compatibility

## Success Criteria

The rewrite is considered successful when:

✅ **All existing unit tests pass without modification**  
✅ **Integration tests complete successfully**  
✅ **Custom DedgeConnection tests pass**  
✅ **Connection strings are generated correctly**  
✅ **All public methods work identically**  
✅ **Performance is maintained or improved**  
✅ **No breaking changes in functionality**  
✅ **Error handling works as expected**  

## Conclusion

This comprehensive test plan ensures that the `DedgeConnection` rewrite maintains full backward compatibility while providing the benefits of JSON-based configuration. The automated test runner simplifies the verification process, while the manual steps provide detailed control for troubleshooting.

The key to success is thorough testing at each phase and maintaining the exact same function signatures and behavior as the original implementation.

