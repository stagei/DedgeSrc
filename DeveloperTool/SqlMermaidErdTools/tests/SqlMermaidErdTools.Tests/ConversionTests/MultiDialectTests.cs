using SqlMermaidErdTools.Converters;
using Xunit;
using Xunit.Abstractions;

namespace SqlMermaidErdTools.Tests.ConversionTests;

/// <summary>
/// Tests for multi-dialect SQL support in SQL to Mermaid conversion.
/// </summary>
public class MultiDialectTests
{
    private readonly ITestOutputHelper _output;
    private readonly ISqlToMmdConverter _converter;

    public MultiDialectTests(ITestOutputHelper output)
    {
        _output = output;
        _converter = new SqlToMmdConverter();
    }

    [Fact]
    public async Task ConvertSqlServer_TSQL_ShouldWork()
    {
        // Arrange
        _output.WriteLine("=== Testing SQL Server T-SQL ===");
        
        var tsql = @"
CREATE TABLE Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100) UNIQUE,
    HireDate DATETIME2 DEFAULT GETDATE()
);";

        // Act
        var mermaid = await _converter.ConvertAsync(tsql);
        
        // Assert
        _output.WriteLine($"Generated Mermaid:\n{mermaid}");
        Assert.Contains("erDiagram", mermaid);
        Assert.Contains("Employees", mermaid);
        Assert.Contains("EmployeeID", mermaid);
        Assert.Contains("PK", mermaid);
        Assert.Contains("UK", mermaid); // Email is UNIQUE
    }

    [Fact]
    public async Task ConvertPostgreSQL_ShouldWork()
    {
        // Arrange
        _output.WriteLine("=== Testing PostgreSQL ===");
        
        var pgsql = @"
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    email VARCHAR(100) UNIQUE,
    metadata JSONB
);";

        // Act
        var mermaid = await _converter.ConvertAsync(pgsql);
        
        // Assert
        _output.WriteLine($"Generated Mermaid:\n{mermaid}");
        Assert.Contains("erDiagram", mermaid);
        Assert.Contains("employees", mermaid);
        Assert.Contains("employee_id", mermaid);
        Assert.Contains("PK", mermaid);
        Assert.Contains("jsonb", mermaid); // PostgreSQL-specific type
    }

    [Fact]
    public async Task ConvertMySQL_ShouldWork()
    {
        // Arrange
        _output.WriteLine("=== Testing MySQL ===");
        
        var mysql = @"
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);";

        // Act
        var mermaid = await _converter.ConvertAsync(mysql);
        
        // Assert
        _output.WriteLine($"Generated Mermaid:\n{mermaid}");
        Assert.Contains("erDiagram", mermaid);
        Assert.Contains("users", mermaid);
        Assert.Contains("PK", mermaid);
        Assert.Contains("DEFAULT", mermaid);
    }

    [Fact]
    public async Task ConvertSQLite_ShouldWork()
    {
        // Arrange
        _output.WriteLine("=== Testing SQLite ===");
        
        var sqlite = @"
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE
);";

        // Act
        var mermaid = await _converter.ConvertAsync(sqlite);
        
        // Assert
        _output.WriteLine($"Generated Mermaid:\n{mermaid}");
        Assert.Contains("erDiagram", mermaid);
        Assert.Contains("users", mermaid);
        Assert.Contains("PK", mermaid);
        Assert.Contains("UK", mermaid); // email UNIQUE
    }

    [Fact]
    public async Task ConvertOracle_ShouldWork()
    {
        // Arrange
        _output.WriteLine("=== Testing Oracle ===");
        
        var oracle = @"
CREATE TABLE EMPLOYEES (
    EMPLOYEE_ID NUMBER PRIMARY KEY,
    FIRST_NAME VARCHAR2(50) NOT NULL,
    EMAIL VARCHAR2(100) UNIQUE,
    HIRE_DATE DATE DEFAULT SYSDATE
);";

        // Act
        var mermaid = await _converter.ConvertAsync(oracle);
        
        // Assert
        _output.WriteLine($"Generated Mermaid:\n{mermaid}");
        Assert.Contains("erDiagram", mermaid);
        Assert.Contains("EMPLOYEES", mermaid);
        Assert.Contains("PK", mermaid);
    }
}

