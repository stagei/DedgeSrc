using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Exceptions;
using SqlMermaidErdTools.Models;
using Xunit.Abstractions;

namespace SqlMermaidErdTools.Tests.ConversionTests;

public class MmdToSqlTests
{
    private readonly IMmdToSqlConverter _converter;
    private readonly string _testDataPath;
    private readonly ITestOutputHelper _output;

    public MmdToSqlTests(ITestOutputHelper output)
    {
        _output = output;
        _converter = new MmdToSqlConverter();
        _testDataPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "TestData");
        
        _output.WriteLine($"=== Mermaid to SQL Test Initialization ===");
        _output.WriteLine($"Test Data Path: {_testDataPath}");
        _output.WriteLine($"Converter Type: {_converter.GetType().Name}");
    }

    [Fact]
    public async Task ConvertReferenceMmd_ShouldProduceValidSQL()
    {
        _output.WriteLine("\n=== TEST: Convert Reference Mermaid to SQL ===");
        
        // Arrange
        var referenceMmdPath = Path.Combine(_testDataPath, "reference.mmd");
        
        Assert.True(File.Exists(referenceMmdPath), $"Reference MMD file not found: {referenceMmdPath}");
        
        var mmdInput = await File.ReadAllTextAsync(referenceMmdPath);
        
        _output.WriteLine($"MMD input length: {mmdInput.Length} chars");

        try
        {
            // Act
            _output.WriteLine("\nConverting Mermaid to SQL...");
            var actualSql = await _converter.ConvertAsync(mmdInput, SqlDialect.AnsiSql);
            _output.WriteLine($"✓ Conversion successful");
            _output.WriteLine($"Generated SQL length: {actualSql.Length} chars");

            // Assert
            Assert.NotNull(actualSql);
            Assert.NotEmpty(actualSql);
            
            // Should contain CREATE TABLE
            Assert.Contains("CREATE TABLE", actualSql, StringComparison.OrdinalIgnoreCase);
            
            // Save actual output for inspection
            var actualPath = Path.Combine(Path.GetTempPath(), "actual_mmd_to_sql.sql");
            await File.WriteAllTextAsync(actualPath, actualSql);
            _output.WriteLine($"Saved generated SQL to: {actualPath}");
            
            _output.WriteLine("\nGenerated SQL:");
            _output.WriteLine(actualSql);
            
            _output.WriteLine("✓ Test PASSED");
        }
        catch (Exception ex)
        {
            _output.WriteLine($"\n✗ Test FAILED");
            _output.WriteLine($"Exception: {ex.GetType().Name}");
            _output.WriteLine($"Message: {ex.Message}");
            _output.WriteLine($"Stack: {ex.StackTrace}");
            throw;
        }
    }

    [Fact]
    public async Task ConvertSimpleMermaid_ShouldCreateTableStatement()
    {
        // Arrange
        var simpleMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK ""NOT NULL""
    }
        ";

        // Act
        var result = await _converter.ConvertAsync(simpleMermaid);

        // Assert
        Assert.Contains("CREATE TABLE", result, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Users", result);
        Assert.Contains("id", result);
        Assert.Contains("username", result);
    }

    [Fact]
    public async Task ConvertWithDifferentDialects_ShouldProduceDialectSpecificSQL()
    {
        // Arrange
        var mermaid = @"
erDiagram
    Product {
        int id PK
        varchar name
    }
        ";

        // Act - PostgreSQL
        var pgSql = await _converter.ConvertAsync(mermaid, SqlDialect.PostgreSql);
        _output.WriteLine("PostgreSQL:");
        _output.WriteLine(pgSql);
        
        // Act - MySQL
        var mySql = await _converter.ConvertAsync(mermaid, SqlDialect.MySql);
        _output.WriteLine("\nMySQL:");
        _output.WriteLine(mySql);
        
        // Act - SQL Server
        var tsql = await _converter.ConvertAsync(mermaid, SqlDialect.SqlServer);
        _output.WriteLine("\nSQL Server:");
        _output.WriteLine(tsql);

        // Assert
        Assert.NotEmpty(pgSql);
        Assert.NotEmpty(mySql);
        Assert.NotEmpty(tsql);
        Assert.Contains("CREATE TABLE", pgSql, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ConvertSync_ShouldProduceSameResultAsAsync()
    {
        // Arrange
        var simpleMermaid = @"
erDiagram
    Test {
        int id PK
    }
        ";

        // Act
        var syncResult = _converter.Convert(simpleMermaid);
        var asyncResult = await _converter.ConvertAsync(simpleMermaid);

        // Assert
        Assert.Equal(syncResult, asyncResult);
    }

    [Fact]
    public async Task ConvertEmptyMermaid_ShouldThrowArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _converter.ConvertAsync(""));
    }

    [Fact]
    public async Task ConvertNullMermaid_ShouldThrowArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _converter.ConvertAsync(null!));
    }

    [Fact(Skip = "Foreign key generation from Mermaid relationships not yet implemented - planned for v0.3.0")]
    public async Task ConvertMermaidWithRelationships_ShouldIncludeForeignKeys()
    {
        // Arrange
        var mermaidWithFk = @"
erDiagram
    Customer {
        int id PK
        varchar name
    }
    
    Order {
        int id PK
        int customer_id FK
    }
    
    Customer ||--o{ Order : places
        ";

        // Act
        var result = await _converter.ConvertAsync(mermaidWithFk);
        
        _output.WriteLine("Generated SQL:");
        _output.WriteLine(result);

        // Assert
        Assert.Contains("Customer", result);
        Assert.Contains("Order", result);
        // Should contain FOREIGN KEY or REFERENCES
        Assert.True(
            result.Contains("FOREIGN KEY", StringComparison.OrdinalIgnoreCase) ||
            result.Contains("REFERENCES", StringComparison.OrdinalIgnoreCase),
            "SQL should contain foreign key relationship");
    }

    [Fact]
    public async Task ConvertComplexSchema_ShouldHandleMultipleTables()
    {
        // Arrange
        var complexMermaid = @"
erDiagram
    Department {
        int dept_id PK
        varchar dept_name UK ""NOT NULL""
    }
    
    Employee {
        int emp_id PK
        varchar emp_name ""NOT NULL""
        int dept_id FK
    }
    
    Project {
        int proj_id PK
        varchar proj_name ""NOT NULL""
        int dept_id FK
    }
    
    Department ||--o{ Employee : employs
    Department ||--o{ Project : manages
        ";

        // Act
        var result = await _converter.ConvertAsync(complexMermaid);
        
        _output.WriteLine("Generated SQL:");
        _output.WriteLine(result);

        // Assert
        Assert.Contains("Department", result);
        Assert.Contains("Employee", result);
        Assert.Contains("Project", result);
        Assert.Contains("CREATE TABLE", result, StringComparison.OrdinalIgnoreCase);
    }
}

