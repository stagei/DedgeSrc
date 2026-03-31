using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;

Console.WriteLine("╔════════════════════════════════════════════════════════════════════╗");
Console.WriteLine("║           Testing Error Dump Functionality                         ║");
Console.WriteLine("╚════════════════════════════════════════════════════════════════════╝");
Console.WriteLine();

try
{
    // Create export folder (in solution root)
    var exportFolder = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", $"ErrorDump_Test_{DateTime.Now:yyyyMMdd_HHmmss}"));
    Directory.CreateDirectory(exportFolder);
    
    Console.WriteLine($"Export folder: {exportFolder}");
    Console.WriteLine();
    
    // Test 1: Invalid SQL that SQLGlot cannot parse
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine("Test 1: Invalid SQL (should trigger error dump)");
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine();
    
    var invalidSql = @"
        THIS IS NOT VALID SQL AT ALL!!!
        CREATE TABLEX WITHOUT PROPER SYNTAX
        COMPLETE GARBAGE @#$%^&*()
        MORE NONSENSE THAT CANNOT BE PARSED
    ";
    
    var converter = new SqlToMmdConverter
    {
        ExportFolderPath = exportFolder
    };
    
    try
    {
        Console.WriteLine("Attempting to convert invalid SQL...");
        var result = await converter.ConvertAsync(invalidSql);
        Console.WriteLine("❌ ERROR: Should have failed but succeeded!");
        Console.WriteLine($"Result: {result}");
    }
    catch (Exception ex)
    {
        Console.WriteLine();
        Console.WriteLine("✅ Expected error occurred:");
        Console.WriteLine($"   Type: {ex.GetType().Name}");
        Console.WriteLine($"   Message: {ex.Message}");
        Console.WriteLine();
    }
    
    // Test 2: Check if ErrorDump folder was created
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine("Checking ErrorDump Folder");
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine();
    
    var errorDumpFolder = Path.Combine(AppContext.BaseDirectory, "ErrorDump");
    Console.WriteLine($"ErrorDump folder path: {errorDumpFolder}");
    
    if (Directory.Exists(errorDumpFolder))
    {
        Console.WriteLine("✅ ErrorDump folder exists");
        
        var zipFiles = Directory.GetFiles(errorDumpFolder, "*.zip");
        var txtFiles = Directory.GetFiles(errorDumpFolder, "*.txt");
        
        Console.WriteLine($"   - ZIP files: {zipFiles.Length}");
        Console.WriteLine($"   - TXT files: {txtFiles.Length}");
        Console.WriteLine();
        
        if (zipFiles.Length > 0)
        {
            Console.WriteLine("Error Dump Files Created:");
            foreach (var zipFile in zipFiles)
            {
                var fileName = Path.GetFileName(zipFile);
                var fileSize = new FileInfo(zipFile).Length;
                Console.WriteLine($"   📦 {fileName} ({fileSize:N0} bytes)");
                
                var txtFile = Path.ChangeExtension(zipFile, ".txt");
                if (File.Exists(txtFile))
                {
                    Console.WriteLine($"   📄 {Path.GetFileName(txtFile)}");
                    Console.WriteLine();
                    Console.WriteLine("   Support Instructions Preview:");
                    Console.WriteLine("   " + new string('─', 60));
                    var txtContent = await File.ReadAllTextAsync(txtFile);
                    var lines = txtContent.Split('\n').Take(15);
                    foreach (var line in lines)
                    {
                        Console.WriteLine($"   {line.TrimEnd()}");
                    }
                    Console.WriteLine("   " + new string('─', 60));
                }
            }
        }
        else
        {
            Console.WriteLine("❌ No error dump files found!");
        }
    }
    else
    {
        Console.WriteLine("❌ ErrorDump folder was not created!");
    }
    
    Console.WriteLine();
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine("✅ Error Dump Test Complete");
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    
    return 0;
}
catch (Exception ex)
{
    Console.WriteLine();
    Console.WriteLine("❌ UNEXPECTED ERROR:");
    Console.WriteLine(ex.ToString());
    return 1;
}

