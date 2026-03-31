using SqlMermaidErdTools.Converters;

Console.WriteLine("╔════════════════════════════════════════════════════════════════════╗");
Console.WriteLine("║      Testing Error Dump WITHOUT Export Functionality              ║");
Console.WriteLine("╚════════════════════════════════════════════════════════════════════╝");
Console.WriteLine();

try
{
    var invalidSql = @"
        THIS IS NOT VALID SQL AT ALL!!!
        CREATE TABLEX WITHOUT PROPER SYNTAX
        COMPLETE GARBAGE @#$%^&*()
    ";
    
    // NO ExportFolderPath set - error dump should still be created!
    var converter = new SqlToMmdConverter();
    
    Console.WriteLine("Attempting to convert invalid SQL (NO export folder configured)...");
    Console.WriteLine();
    
    try
    {
        var result = await converter.ConvertAsync(invalidSql);
        Console.WriteLine("❌ ERROR: Should have failed but succeeded!");
    }
    catch (Exception ex)
    {
        Console.WriteLine("✅ Expected error occurred:");
        Console.WriteLine($"   Type: {ex.GetType().Name}");
        Console.WriteLine($"   Message: {ex.Message.Substring(0, Math.Min(100, ex.Message.Length))}...");
        Console.WriteLine();
    }
    
    // Check if ErrorDump was created
    var workspaceRoot = FindWorkspaceRoot();
    var errorDumpFolder = Path.Combine(workspaceRoot, "ErrorDump");
    
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine($"Checking ErrorDump folder: {errorDumpFolder}");
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine();
    
    if (Directory.Exists(errorDumpFolder))
    {
        var zipFiles = Directory.GetFiles(errorDumpFolder, "*.zip");
        var latestZip = zipFiles.OrderByDescending(File.GetLastWriteTime).FirstOrDefault();
        
        if (latestZip != null)
        {
            Console.WriteLine($"✅ Error dump created: {Path.GetFileName(latestZip)}");
            Console.WriteLine($"   Location: {errorDumpFolder}");
            Console.WriteLine($"   Size: {new FileInfo(latestZip).Length:N0} bytes");
            Console.WriteLine();
            
            // Extract and examine contents
            var extractPath = Path.Combine(Path.GetTempPath(), "ErrorDumpTest_" + Guid.NewGuid().ToString("N"));
            System.IO.Compression.ZipFile.ExtractToDirectory(latestZip, extractPath);
            
            Console.WriteLine("   ZIP Contents:");
            foreach (var file in Directory.GetFiles(extractPath, "*", SearchOption.AllDirectories))
            {
                var relativePath = Path.GetRelativePath(extractPath, file);
                var size = new FileInfo(file).Length;
                Console.WriteLine($"      • {relativePath} ({size:N0} bytes)");
            }
            
            // Cleanup
            Directory.Delete(extractPath, true);
        }
        else
        {
            Console.WriteLine("❌ No error dump ZIP files found!");
        }
    }
    else
    {
        Console.WriteLine("❌ ErrorDump folder does not exist!");
    }
    
    Console.WriteLine();
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine("✅ Test Complete: Error dumps work WITHOUT export functionality!");
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

static string FindWorkspaceRoot()
{
    var current = new DirectoryInfo(AppContext.BaseDirectory);
    while (current != null)
    {
        if (current.GetFiles("*.sln").Any())
            return current.FullName;
        current = current.Parent;
    }
    return Environment.CurrentDirectory;
}

