using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;
using Xunit.Abstractions;

namespace SqlMermaidErdTools.Tests.ConversionTests;

public class MmdDiffToSqlTests
{
    private readonly IMmdDiffToSqlGenerator _generator;
    private readonly ITestOutputHelper _output;

    public MmdDiffToSqlTests(ITestOutputHelper output)
    {
        _output = output;
        _generator = new MmdDiffToSqlGenerator();
        
        _output.WriteLine($"=== Mermaid Diff to SQL Test Initialization ===");
        _output.WriteLine($"Generator Type: {_generator.GetType().Name}");
    }

    [Fact]
    public async Task GenerateAlterStatements_AddNewColumn_ShouldCreateAlterAddColumn()
    {
        _output.WriteLine("\n=== TEST: Generate ALTER statements for added column ===");
        
        // Arrange
        var beforeMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK
        varchar email UK ""NOT NULL""
    }
        ";

        try
        {
            // Act
            _output.WriteLine("\nGenerating ALTER statements...");
            var alterStatements = await _generator.GenerateAlterStatementsAsync(
                beforeMermaid,
                afterMermaid,
                SqlDialect.AnsiSql
            );
            
            _output.WriteLine($"✓ Generation successful");
            _output.WriteLine("\nGenerated ALTER statements:");
            _output.WriteLine(alterStatements);

            // Assert
            Assert.NotNull(alterStatements);
            Assert.NotEmpty(alterStatements);
            Assert.Contains("ALTER TABLE", alterStatements, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("ADD COLUMN", alterStatements, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("email", alterStatements);
            
            _output.WriteLine("✓ Test PASSED");
        }
        catch (Exception ex)
        {
            _output.WriteLine($"\n✗ Test FAILED");
            _output.WriteLine($"Exception: {ex.GetType().Name}");
            _output.WriteLine($"Message: {ex.Message}");
            throw;
        }
    }

    [Fact]
    public async Task GenerateAlterStatements_DropColumn_ShouldCreateAlterDropColumn()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK
        varchar email UK
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK
    }
        ";

        // Act
        var alterStatements = await _generator.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid
        );
        
        _output.WriteLine("Generated ALTER statements:");
        _output.WriteLine(alterStatements);

        // Assert
        Assert.Contains("ALTER TABLE", alterStatements, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("DROP COLUMN", alterStatements, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("email", alterStatements);
    }

    [Fact]
    public async Task GenerateAlterStatements_AddNewTable_ShouldCreateTableStatement()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK
    }
    
    Products {
        int id PK
        varchar name ""NOT NULL""
        decimal price
    }
        ";

        // Act
        var alterStatements = await _generator.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid
        );
        
        _output.WriteLine("Generated statements:");
        _output.WriteLine(alterStatements);

        // Assert
        Assert.Contains("CREATE TABLE", alterStatements, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Products", alterStatements);
    }

    [Fact]
    public async Task GenerateAlterStatements_DropTable_ShouldCreateDropTableStatement()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Users {
        int id PK
    }
    
    OldTable {
        int id PK
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Users {
        int id PK
    }
        ";

        // Act
        var alterStatements = await _generator.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid
        );
        
        _output.WriteLine("Generated statements:");
        _output.WriteLine(alterStatements);

        // Assert
        Assert.Contains("DROP TABLE", alterStatements, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("OldTable", alterStatements);
    }

    [Fact]
    public async Task GenerateAlterStatements_ModifyColumn_ShouldCreateAlterModifyColumn()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK ""NOT NULL""
    }
        ";

        // Act
        var alterStatements = await _generator.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid
        );
        
        _output.WriteLine("Generated ALTER statements:");
        _output.WriteLine(alterStatements);

        // Assert
        Assert.Contains("ALTER", alterStatements, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("username", alterStatements);
    }

    [Fact]
    public async Task GenerateAlterStatements_NoChanges_ShouldReturnNoChangesMessage()
    {
        // Arrange
        var mermaid = @"
erDiagram
    Users {
        int id PK
        varchar username UK
    }
        ";

        // Act
        var alterStatements = await _generator.GenerateAlterStatementsAsync(
            mermaid,
            mermaid
        );
        
        _output.WriteLine("Generated output:");
        _output.WriteLine(alterStatements);

        // Assert
        Assert.Contains("No changes detected", alterStatements, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task GenerateAlterStatements_ComplexChanges_ShouldHandleMultipleOperations()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Departments {
        int dept_id PK
        varchar dept_name
    }
    
    Employees {
        int emp_id PK
        varchar emp_name
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Departments {
        int dept_id PK
        varchar dept_name UK ""NOT NULL""
        varchar location
    }
    
    Employees {
        int emp_id PK
        varchar emp_name ""NOT NULL""
        int dept_id FK
    }
    
    Projects {
        int proj_id PK
        varchar proj_name ""NOT NULL""
    }
    
    Departments ||--o{ Employees : employs
        ";

        // Act
        var alterStatements = await _generator.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid
        );
        
        _output.WriteLine("Generated ALTER statements:");
        _output.WriteLine(alterStatements);

        // Assert
        Assert.NotEmpty(alterStatements);
        // Should contain new table
        Assert.Contains("Projects", alterStatements);
        // Should contain added column
        Assert.Contains("location", alterStatements);
    }

    [Fact]
    public async Task GenerateAlterStatementsSync_ShouldProduceSameResultAsAsync()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Test {
        int id PK
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Test {
        int id PK
        varchar name
    }
        ";

        // Act
        var syncResult = _generator.GenerateAlterStatements(beforeMermaid, afterMermaid);
        var asyncResult = await _generator.GenerateAlterStatementsAsync(beforeMermaid, afterMermaid);

        // Assert
        Assert.Equal(syncResult, asyncResult);
    }

    [Fact]
    public async Task GenerateAlterStatements_DifferentDialects_ShouldProduceDialectSpecificSyntax()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Users {
        int id PK
        varchar name
    }
        ";
        
        var afterMermaid = @"
erDiagram
    Users {
        int id PK
        varchar name ""NOT NULL""
    }
        ";

        // Act - PostgreSQL
        var pgAlter = await _generator.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid,
            SqlDialect.PostgreSql
        );
        _output.WriteLine("PostgreSQL ALTER:");
        _output.WriteLine(pgAlter);
        
        // Act - MySQL
        var myAlter = await _generator.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid,
            SqlDialect.MySql
        );
        _output.WriteLine("\nMySQL ALTER:");
        _output.WriteLine(myAlter);

        // Assert
        Assert.NotEmpty(pgAlter);
        Assert.NotEmpty(myAlter);
        Assert.Contains("ALTER", pgAlter, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ALTER", myAlter, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task GenerateAlterStatements_EmptyBefore_ShouldThrowArgumentException()
    {
        // Arrange
        var afterMermaid = @"
erDiagram
    Test {
        int id PK
    }
        ";

        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _generator.GenerateAlterStatementsAsync("", afterMermaid));
    }

    [Fact]
    public async Task GenerateAlterStatements_EmptyAfter_ShouldThrowArgumentException()
    {
        // Arrange
        var beforeMermaid = @"
erDiagram
    Test {
        int id PK
    }
        ";

        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _generator.GenerateAlterStatementsAsync(beforeMermaid, ""));
    }
}

