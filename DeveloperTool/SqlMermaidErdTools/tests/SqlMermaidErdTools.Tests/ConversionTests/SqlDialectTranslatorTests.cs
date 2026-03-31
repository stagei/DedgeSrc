using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Exceptions;
using SqlMermaidErdTools.Models;
using Xunit.Abstractions;

namespace SqlMermaidErdTools.Tests.ConversionTests;

public class SqlDialectTranslatorTests
{
    private readonly ISqlDialectTranslator _translator;
    private readonly string _testDataPath;
    private readonly ITestOutputHelper _output;

    public SqlDialectTranslatorTests(ITestOutputHelper output)
    {
        _output = output;
        _translator = new SqlDialectTranslator();
        _testDataPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "TestData");
        
        _output.WriteLine($"=== SQL Dialect Translator Test Initialization ===");
        _output.WriteLine($"Test Data Path: {_testDataPath}");
        _output.WriteLine($"Translator Type: {_translator.GetType().Name}");
    }

    [Fact]
    public async Task TranslateSqlServerToPostgres_ShouldConvertDialectSpecificSyntax()
    {
        _output.WriteLine("\n=== TEST: Translate SQL Server to PostgreSQL ===");
        
        // Arrange
        var sqlServerSql = @"
CREATE TABLE Employees (
    id INT PRIMARY KEY IDENTITY(1,1),
    name NVARCHAR(100) NOT NULL,
    hire_date DATETIME DEFAULT GETDATE()
);
        ";
        
        _output.WriteLine("SQL Server SQL:");
        _output.WriteLine(sqlServerSql);

        try
        {
            // Act
            _output.WriteLine("\nTranslating to PostgreSQL...");
            var postgresSql = await _translator.TranslateAsync(
                sqlServerSql,
                SqlDialect.SqlServer,
                SqlDialect.PostgreSql
            );
            
            _output.WriteLine($"✓ Translation successful");
            _output.WriteLine("\nPostgreSQL SQL:");
            _output.WriteLine(postgresSql);

            // Assert
            Assert.NotNull(postgresSql);
            Assert.NotEmpty(postgresSql);
            Assert.Contains("CREATE TABLE", postgresSql, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("Employees", postgresSql);
            
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
    public async Task TranslatePostgresToMySql_ShouldConvertSuccessfully()
    {
        // Arrange
        var postgresSql = @"
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
        ";

        // Act
        var mySql = await _translator.TranslateAsync(
            postgresSql,
            SqlDialect.PostgreSql,
            SqlDialect.MySql
        );
        
        _output.WriteLine("MySQL SQL:");
        _output.WriteLine(mySql);

        // Assert
        Assert.NotEmpty(mySql);
        Assert.Contains("CREATE TABLE", mySql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("products", mySql);
    }

    [Fact]
    public async Task TranslateMySqlToSqlite_ShouldHandleDataTypes()
    {
        // Arrange
        var mySql = @"
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    active TINYINT DEFAULT 1
);
        ";

        // Act
        var sqlite = await _translator.TranslateAsync(
            mySql,
            SqlDialect.MySql,
            SqlDialect.Sqlite
        );
        
        _output.WriteLine("SQLite SQL:");
        _output.WriteLine(sqlite);

        // Assert
        Assert.NotEmpty(sqlite);
        Assert.Contains("CREATE TABLE", sqlite, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task TranslateSync_ShouldProduceSameResultAsAsync()
    {
        // Arrange
        var simpleSql = @"CREATE TABLE Test (id INT PRIMARY KEY, name VARCHAR(50));";

        // Act
        var syncResult = _translator.Translate(
            simpleSql,
            SqlDialect.AnsiSql,
            SqlDialect.PostgreSql
        );
        
        var asyncResult = await _translator.TranslateAsync(
            simpleSql,
            SqlDialect.AnsiSql,
            SqlDialect.PostgreSql
        );

        // Assert
        Assert.Equal(syncResult, asyncResult);
    }

    [Fact]
    public async Task TranslateSameDialect_ShouldReturnFormattedSql()
    {
        // Arrange
        var sql = @"CREATE TABLE Test (id INT PRIMARY KEY);";

        // Act
        var result = await _translator.TranslateAsync(
            sql,
            SqlDialect.AnsiSql,
            SqlDialect.AnsiSql
        );

        // Assert
        Assert.NotEmpty(result);
        Assert.Contains("CREATE TABLE", result, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task TranslateEmptySql_ShouldThrowArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _translator.TranslateAsync("", SqlDialect.AnsiSql, SqlDialect.PostgreSql));
    }

    [Fact]
    public async Task TranslateNullSql_ShouldThrowArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(() =>
            _translator.TranslateAsync(null!, SqlDialect.AnsiSql, SqlDialect.PostgreSql));
    }

    [Fact]
    public async Task TranslateComplexSchema_ShouldPreserveStructure()
    {
        // Arrange
        var complexSql = @"
CREATE TABLE departments (
    dept_id INT PRIMARY KEY,
    dept_name VARCHAR(100) NOT NULL
);

CREATE TABLE employees (
    emp_id INT PRIMARY KEY,
    emp_name VARCHAR(100) NOT NULL,
    dept_id INT,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);
        ";

        // Act
        var result = await _translator.TranslateAsync(
            complexSql,
            SqlDialect.AnsiSql,
            SqlDialect.PostgreSql
        );
        
        _output.WriteLine("Translated SQL:");
        _output.WriteLine(result);

        // Assert
        Assert.Contains("departments", result);
        Assert.Contains("employees", result);
        Assert.Contains("CREATE TABLE", result, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task TranslateTestDataSamples_ShouldHandleRealWorldSchemas()
    {
        // Arrange
        var sqlServerSamplePath = Path.Combine(_testDataPath, "sqlserver_sample.sql");
        var postgresSamplePath = Path.Combine(_testDataPath, "postgresql_sample.sql");
        
        if (File.Exists(sqlServerSamplePath))
        {
            var sqlServerSql = await File.ReadAllTextAsync(sqlServerSamplePath);
            
            // Act
            var translatedToPostgres = await _translator.TranslateAsync(
                sqlServerSql,
                SqlDialect.SqlServer,
                SqlDialect.PostgreSql
            );
            
            _output.WriteLine("Translated SQL Server to PostgreSQL:");
            _output.WriteLine(translatedToPostgres);
            
            // Assert
            Assert.NotEmpty(translatedToPostgres);
        }
        
        if (File.Exists(postgresSamplePath))
        {
            var postgresSql = await File.ReadAllTextAsync(postgresSamplePath);
            
            // Act
            var translatedToMySql = await _translator.TranslateAsync(
                postgresSql,
                SqlDialect.PostgreSql,
                SqlDialect.MySql
            );
            
            _output.WriteLine("\n\nTranslated PostgreSQL to MySQL:");
            _output.WriteLine(translatedToMySql);
            
            // Assert
            Assert.NotEmpty(translatedToMySql);
        }
    }
}

