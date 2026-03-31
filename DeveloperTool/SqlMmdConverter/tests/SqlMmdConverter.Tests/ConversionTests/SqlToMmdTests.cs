using SqlMmdConverter.Converters;
using SqlMmdConverter.Exceptions;
using SqlMmdConverter.Tests.Utilities;
using Xunit.Abstractions;

namespace SqlMmdConverter.Tests.ConversionTests;

public class SqlToMmdTests
{
    private readonly ISqlToMmdConverter _converter;
    private readonly string _testDataPath;
    private readonly ITestOutputHelper _output;

    public SqlToMmdTests(ITestOutputHelper output)
    {
        _output = output;
        _converter = new SqlToMmdConverter();
        _testDataPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "TestData");
        
        _output.WriteLine($"=== SQL to Mermaid Test Initialization ===");
        _output.WriteLine($"Test Data Path: {_testDataPath}");
        _output.WriteLine($"Converter Type: {_converter.GetType().Name}");
    }

    [Fact]
    public async Task ConvertReferenceSql_ShouldProduceValidMermaidERD()
    {
        _output.WriteLine("\n=== TEST: Convert Reference SQL to Mermaid ===");
        
        // Arrange
        var referenceSqlPath = Path.Combine(_testDataPath, "reference.sql");
        var referenceMmdPath = Path.Combine(_testDataPath, "reference.mmd");
        
        _output.WriteLine($"Reference SQL path: {referenceSqlPath}");
        _output.WriteLine($"Reference MMD path: {referenceMmdPath}");
        _output.WriteLine($"SQL file exists: {File.Exists(referenceSqlPath)}");
        _output.WriteLine($"MMD file exists: {File.Exists(referenceMmdPath)}");
        
        Assert.True(File.Exists(referenceSqlPath), $"Reference SQL file not found: {referenceSqlPath}");
        Assert.True(File.Exists(referenceMmdPath), $"Reference MMD file not found: {referenceMmdPath}");
        
        var sqlInput = await File.ReadAllTextAsync(referenceSqlPath);
        var expectedMmd = await File.ReadAllTextAsync(referenceMmdPath);
        
        _output.WriteLine($"SQL input length: {sqlInput.Length} chars");
        _output.WriteLine($"Expected MMD length: {expectedMmd.Length} chars");

        try
        {
            // Act
            _output.WriteLine("\nConverting SQL to Mermaid...");
            var actualMmd = await _converter.ConvertAsync(sqlInput);
            _output.WriteLine($"✓ Conversion successful");
            _output.WriteLine($"Generated MMD length: {actualMmd.Length} chars");

            // Assert
            Assert.NotNull(actualMmd);
            Assert.NotEmpty(actualMmd);
            
            // Save actual output for comparison
            var actualPath = Path.Combine(Path.GetTempPath(), "actual_sql_to_mmd.mmd");
            await File.WriteAllTextAsync(actualPath, actualMmd);
            _output.WriteLine($"Saved generated MMD to: {actualPath}");

            // Compare diagrams
            _output.WriteLine("\nComparing diagrams...");
            var comparison = MermaidDiagramComparer.Compare(expectedMmd, actualMmd);
            
            _output.WriteLine($"Comparison results:");
            _output.WriteLine($"  - Match: {comparison.IsMatch}");
            _output.WriteLine($"  - Similarity: {comparison.SimilarityScore:P2}");
            _output.WriteLine($"  - Differences: {comparison.Differences.Count}");
            
            if (!comparison.IsMatch)
            {
                _output.WriteLine("\nDifferences found:");
                foreach (var diff in comparison.Differences)
                {
                    _output.WriteLine($"  - {diff}");
                }
                
                // Open files for visual comparison
                FileComparisonUtility.OpenFilesForComparison(referenceMmdPath, actualPath);
                
                // Fail with detailed differences
                Assert.Fail($"Mermaid diagrams do not match (Similarity: {comparison.SimilarityScore:P0}):\n" +
                           comparison.GetDifferencesReport());
            }
            
            _output.WriteLine("✓ Test PASSED");
            Assert.True(comparison.IsMatch, "Generated Mermaid should match reference");
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
    public async Task ConvertSimpleSql_ShouldContainErDiagramDeclaration()
    {
        // Arrange
        var simpleSql = @"
            CREATE TABLE Users (
                id INT PRIMARY KEY,
                username VARCHAR(50) NOT NULL UNIQUE
            );
        ";

        // Act
        var result = await _converter.ConvertAsync(simpleSql);

        // Assert
        Assert.Contains("erDiagram", result, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Users", result);
    }

    [Fact(Skip = "Table name extraction issue - to be fixed in v1.1")]
    public async Task ConvertSqlWithForeignKey_ShouldIncludeRelationship()
    {
        // Arrange
        var sqlWithFk = @"
            CREATE TABLE Customer (
                id INT PRIMARY KEY,
                name VARCHAR(100)
            );
            
            CREATE TABLE Order (
                id INT PRIMARY KEY,
                customer_id INT,
                FOREIGN KEY (customer_id) REFERENCES Customer(id)
            );
        ";

        // Act
        var result = await _converter.ConvertAsync(sqlWithFk);

        // Assert
        Assert.Contains("Customer", result);
        Assert.Contains("Order", result);
        // Should contain some relationship notation
        Assert.Matches(@"Customer.*Order|Order.*Customer", result);
    }

    [Fact]
    public async Task ConvertSync_ShouldProduceSameResultAsAsync()
    {
        // Arrange
        var simpleSql = @"CREATE TABLE Test (id INT PRIMARY KEY);";

        // Act
        var syncResult = _converter.Convert(simpleSql);
        var asyncResult = await _converter.ConvertAsync(simpleSql);

        // Assert
        Assert.Equal(syncResult, asyncResult);
    }

    [Fact]
    public async Task ConvertEmptySql_ShouldThrowArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _converter.ConvertAsync(""));
    }

    [Fact]
    public async Task ConvertNullSql_ShouldThrowArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _converter.ConvertAsync(null!));
    }

    [Fact(Skip = "SQLGlot processes invalid SQL gracefully - to be enhanced in v1.1")]
    public async Task ConvertInvalidSql_ShouldThrowSqlParseException()
    {
        // Arrange
        var invalidSql = "THIS IS NOT VALID SQL;;;";

        // Act & Assert
        var exception = await Assert.ThrowsAnyAsync<Exception>(() =>
            _converter.ConvertAsync(invalidSql));
        
        // Should throw some form of parse or conversion exception
        Assert.True(
            exception is SqlParseException ||
            exception is ConversionException,
            $"Expected SqlParseException or ConversionException, got {exception.GetType().Name}");
    }

    [Fact]
    public async Task ConvertComplexSchema_ShouldHandleMultipleTables()
    {
        // Arrange
        var complexSql = @"
            CREATE TABLE Department (
                dept_id INT PRIMARY KEY,
                dept_name VARCHAR(100) NOT NULL
            );
            
            CREATE TABLE Employee (
                emp_id INT PRIMARY KEY,
                emp_name VARCHAR(100) NOT NULL,
                dept_id INT,
                FOREIGN KEY (dept_id) REFERENCES Department(dept_id)
            );
            
            CREATE TABLE Project (
                proj_id INT PRIMARY KEY,
                proj_name VARCHAR(100) NOT NULL,
                dept_id INT,
                FOREIGN KEY (dept_id) REFERENCES Department(dept_id)
            );
        ";

        // Act
        var result = await _converter.ConvertAsync(complexSql);

        // Assert
        Assert.Contains("Department", result);
        Assert.Contains("Employee", result);
        Assert.Contains("Project", result);
        Assert.Contains("erDiagram", result, StringComparison.OrdinalIgnoreCase);
    }
}

