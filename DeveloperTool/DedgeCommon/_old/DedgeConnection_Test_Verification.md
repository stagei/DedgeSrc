# DedgeConnection Test Verification Plan

## Available Test Programs

Based on the analysis of the project, I found several test programs that can be used to verify `DedgeConnection` functionality after the rewrite:

### 1. **DedgeCommonVerifyFkDatabaseHandler/Program.cs** (Main Verification Program)
- **Purpose**: Comprehensive database handler verification
- **Key DedgeConnection Usage**:
  - `DedgeConnection.ConnectionKey` creation and usage
  - `DedgeConnection.GetConnectionKeyByDatabaseName()` method
  - `DedgeDbHandler.Create()` with connection keys
  - Database operations using connection strings

### 2. **DedgeCommonTest/FkDatabaseHandlerTests.cs** (Unit Tests)
- **Purpose**: Unit tests for database handler creation
- **Key DedgeConnection Tests**:
  - Connection key creation with different applications/environments
  - Version-specific connection handling
  - Provider type validation
  - Connection string generation

### 3. **TestNoNameSpace/Program.cs** (Simple Test)
- **Purpose**: Basic functionality test
- **Key DedgeConnection Usage**:
  - Simple connection key creation
  - Database logging enablement

## Test Verification Strategy

### Phase 1: Unit Test Verification
Run the existing unit tests to ensure basic functionality:

```bash
# Run unit tests
dotnet test DedgeCommonTest/DedgeCommonTest.csproj --verbosity normal
```

**Expected Results**:
- All `FkDatabaseHandlerTests` should pass
- Connection key creation should work
- Provider detection should be correct
- Version handling should work

### Phase 2: Integration Test Verification
Run the main verification program:

```bash
# Run the verification program
dotnet run --project DedgeCommonVerifyFkDatabaseHandler/VerifyFunctionality.csproj
```

**Expected Results**:
- Program should start successfully
- Database connections should be established
- All database operations should complete
- Notifications should be sent

### Phase 3: Specific DedgeConnection Method Testing
Create a focused test program to verify all `DedgeConnection` methods:

```csharp
// Test program to verify DedgeConnection methods
public class DedgeConnectionTestProgram
{
    static void Main(string[] args)
    {
        try
        {
            Console.WriteLine("=== DedgeConnection Test Verification ===");
            
            // Test 1: GetConnectionStringInfo with different parameters
            TestGetConnectionStringInfo();
            
            // Test 2: GetConnectionString method
            TestGetConnectionString();
            
            // Test 3: GetCurrentVersionConnectionInfo
            TestGetCurrentVersionConnectionInfo();
            
            // Test 4: GetConnectionKeyByDatabaseName
            TestGetConnectionKeyByDatabaseName();
            
            // Test 5: GetAllConnectionDetails
            TestGetAllConnectionDetails();
            
            // Test 6: GetConnectionsForApplications
            TestGetConnectionsForApplications();
            
            Console.WriteLine("=== All tests passed successfully ===");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Test failed: {ex.Message}");
            Console.WriteLine($"Stack trace: {ex.StackTrace}");
        }
    }
    
    private static void TestGetConnectionStringInfo()
    {
        Console.WriteLine("Testing GetConnectionStringInfo...");
        
        // Test with default parameters
        var connInfo1 = DedgeConnection.GetConnectionStringInfo(DedgeConnection.FkEnvironment.DEV);
        Assert.IsNotNull(connInfo1);
        Assert.AreEqual(DedgeConnection.FkApplication.FKM, connInfo1.Application);
        
        // Test with specific application
        var connInfo2 = DedgeConnection.GetConnectionStringInfo(DedgeConnection.FkEnvironment.PRD, DedgeConnection.FkApplication.INL);
        Assert.IsNotNull(connInfo2);
        Assert.AreEqual(DedgeConnection.FkApplication.INL, connInfo2.Application);
        
        // Test with version
        var connInfo3 = DedgeConnection.GetConnectionStringInfo(DedgeConnection.FkEnvironment.DEV, DedgeConnection.FkApplication.FKM, "2.0");
        Assert.IsNotNull(connInfo3);
        Assert.AreEqual("2.0", connInfo3.Version);
        
        Console.WriteLine("✓ GetConnectionStringInfo tests passed");
    }
    
    private static void TestGetConnectionString()
    {
        Console.WriteLine("Testing GetConnectionString...");
        
        // Test connection string generation
        var connString1 = DedgeConnection.GetConnectionString(DedgeConnection.FkEnvironment.DEV);
        Assert.IsNotNull(connString1);
        Assert.IsTrue(connString1.Contains("Database="));
        Assert.IsTrue(connString1.Contains("Server="));
        
        // Test with connection key
        var key = new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.FKM, DedgeConnection.FkEnvironment.PRD);
        var connString2 = DedgeConnection.GetConnectionString(key);
        Assert.IsNotNull(connString2);
        
        Console.WriteLine("✓ GetConnectionString tests passed");
    }
    
    private static void TestGetCurrentVersionConnectionInfo()
    {
        Console.WriteLine("Testing GetCurrentVersionConnectionInfo...");
        
        var connInfo = DedgeConnection.GetCurrentVersionConnectionInfo(DedgeConnection.FkEnvironment.DEV, DedgeConnection.FkApplication.FKM);
        Assert.IsNotNull(connInfo);
        Assert.AreEqual(DedgeConnection.FkApplication.FKM, connInfo.Application);
        Assert.AreEqual(DedgeConnection.FkEnvironment.DEV, connInfo.Environment);
        
        Console.WriteLine("✓ GetCurrentVersionConnectionInfo tests passed");
    }
    
    private static void TestGetConnectionKeyByDatabaseName()
    {
        Console.WriteLine("Testing GetConnectionKeyByDatabaseName...");
        
        var key = DedgeConnection.GetConnectionKeyByDatabaseName("BASISTST");
        Assert.IsNotNull(key);
        Assert.AreEqual(DedgeConnection.FkApplication.FKM, key.Application);
        
        Console.WriteLine("✓ GetConnectionKeyByDatabaseName tests passed");
    }
    
    private static void TestGetAllConnectionDetails()
    {
        Console.WriteLine("Testing GetAllConnectionDetails...");
        
        var allDetails = DedgeConnection.GetAllConnectionDetails();
        Assert.IsNotNull(allDetails);
        Assert.IsTrue(allDetails.Count > 0);
        
        var fkmDetails = DedgeConnection.GetAllConnectionDetails(DedgeConnection.FkApplication.FKM);
        Assert.IsNotNull(fkmDetails);
        Assert.IsTrue(fkmDetails.All(d => d.ConnectionKey.Application == DedgeConnection.FkApplication.FKM));
        
        Console.WriteLine("✓ GetAllConnectionDetails tests passed");
    }
    
    private static void TestGetConnectionsForApplications()
    {
        Console.WriteLine("Testing GetConnectionsForApplications...");
        
        var applications = new List<DedgeConnection.FkApplication> { DedgeConnection.FkApplication.FKM, DedgeConnection.FkApplication.INL };
        var connections = DedgeConnection.GetConnectionsForApplications(applications);
        Assert.IsNotNull(connections);
        Assert.IsTrue(connections.Count > 0);
        Assert.IsTrue(connections.All(c => applications.Contains(c.Key.Application)));
        
        Console.WriteLine("✓ GetConnectionsForApplications tests passed");
    }
}
```

## Test Execution Plan

### Step 1: Pre-Rewrite Baseline
1. Run all existing tests to establish baseline
2. Document current behavior and results
3. Capture any existing issues or warnings

### Step 2: Post-Rewrite Verification
1. **Unit Tests**: Run `FkDatabaseHandlerTests` to verify basic functionality
2. **Integration Tests**: Run `DedgeCommonVerifyFkDatabaseHandler` to verify end-to-end functionality
3. **Method Tests**: Run the focused `DedgeConnectionTestProgram` to verify all methods
4. **Edge Cases**: Test error conditions and invalid inputs

### Step 3: Comparison and Validation
1. Compare results before and after rewrite
2. Verify all connection strings are generated correctly
3. Ensure all database operations work as expected
4. Validate that no functionality is lost

## Expected Test Results

### Successful Test Outcomes:
- ✅ All unit tests pass
- ✅ Database connections establish successfully
- ✅ Connection strings are generated correctly
- ✅ All DedgeConnection methods work as expected
- ✅ No breaking changes in functionality
- ✅ Performance is maintained or improved

### Potential Issues to Watch For:
- ⚠️ Configuration file loading errors
- ⚠️ JSON parsing issues
- ⚠️ Enum conversion problems
- ⚠️ Connection string format changes
- ⚠️ Performance degradation

## Test Data Validation

### Connection String Format Validation:
```csharp
// Expected DB2 connection string format:
// "Database=BASISTST;Server=t-no1fkmtst-db.DEDGE.fk.no:3701;UID=db2nt;PWD=ntdb2;"

// Expected SQL Server connection string format:
// "Database=DBQA;Server=p-Dedge-vm02.DEDGE.fk.no:50000;User Id=db2nt;Password=ntdb2;"
```

### Database Name Validation:
- FKM DEV: Should use "FKAVDNT" or "FKMDEV"
- FKM TST: Should use "BASISTST" or "FKMTST"
- FKM PRD: Should use "BASISPRO" or "FKMPRD"
- INL PRD: Should use "FKKONTO" or "INLPRD"

## Rollback Plan

If tests fail after the rewrite:

1. **Immediate Rollback**: Revert to original hardcoded implementation
2. **Issue Analysis**: Identify specific problems in the rewrite
3. **Incremental Fixes**: Address issues one by one
4. **Re-testing**: Verify fixes with the same test suite
5. **Gradual Deployment**: Deploy fixes incrementally

## Conclusion

This comprehensive test plan ensures that the `DedgeConnection` rewrite maintains full backward compatibility and functionality. The existing test programs provide excellent coverage for verification, and the focused test program will validate all specific methods and edge cases.

The key to success is thorough testing at each phase and maintaining the exact same function signatures and behavior as the original implementation.

