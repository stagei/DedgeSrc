@{
    RootModule        = 'PwshToCSharpConverter.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f7c8d2-1e4b-4a9f-b6c5-8d2e1f3a7b9c'
    Author            = 'FK SystemAnalyzer Team'
    Description       = 'Converts PowerShell scripts to C# using the built-in PS7 AST parser and a recursive emitter.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('ConvertTo-CSharpSource')
    PrivateData       = @{ PSData = @{} }
}
