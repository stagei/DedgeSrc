# Shortcut to CMD Converter with Nerdio Manager Integration

This is a PowerShell-based utility that serves three main purposes:

1. **Converting Windows Shortcuts (.lnk files) to CMD Files**
   - Takes Windows shortcut files (.lnk)
   - Extracts all relevant information (target path, arguments, working directory, etc.)
   - Creates equivalent .cmd batch files that can run the same programs

2. **Creating Nerdio Manager Integration**
   - Generates PowerShell scripts (.ps1) for Nerdio Manager compatibility
   - Creates metadata files for Nerdio Manager configuration
   - Maintains all original shortcut settings (window style, working directory, etc.)

3. **Documentation and Logging**
   - Creates detailed logs of the conversion process
   - Generates documentation for the converted files
   - Provides import instructions for Nerdio Manager

## Key Features

- **Interactive Usage**: Prompts users for confirmation and shows clear progress
- **Safe Conversion**: Preserves all shortcut settings and parameters
- **Detailed Logging**: Tracks all actions and potential issues
- **File Comparison**: Checks for existing files and shows differences before overwriting
- **Structured Output**:
  - CMD files in the root directory
  - Support files in a `Nerdio-Shorcut-Converter-Output` subfolder
  - Comprehensive documentation and logs

## Typical Use Case

This tool is particularly useful in enterprise environments where:
1. You need to convert Windows shortcuts to command-line equivalents
2. You want to integrate these shortcuts with Nerdio Manager (a virtual desktop management platform)
3. You need to maintain documentation and traceability of the conversion process

## Output Structure

Project/
├── *.cmd                    # Converted batch files
└── Nerdio-Shorcut-Converter-Output/                 # Support folder
    ├── *.ps1               # Nerdio Manager scripts
    ├── *.metadata          # Nerdio configuration
    ├── README.md           # Documentation
    ├── import_instructions.md # Nerdio setup guide
    └── shortcut-conversion.log # Process logs