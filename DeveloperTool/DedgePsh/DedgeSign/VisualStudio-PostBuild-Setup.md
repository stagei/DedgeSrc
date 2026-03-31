# Setting up Post-Build Code Signing in Visual Studio

## Prerequisites

1. Ensure DedgeSign is deployed to `%OptPath%\apps\DedgeSign\`
2. Verify that `AutoSign.cmd` exists in the DedgeSign folder

## Setup Instructions

### Option 1: Using Visual Studio UI

1. Right-click your project in Solution Explorer
2. Select "Properties"
3. Navigate to "Build Events"
4. In the "Post-build event command line" box, add:
   ```
   "%OptPath%\apps\DedgeSign\AutoSign.cmd" "$(TargetPath)"
   ```

### Option 2: Editing Project File Directly

1. Right-click your project in Solution Explorer
2. Select "Edit Project File"
3. Add the following PropertyGroup section:
   ```xml
   <PropertyGroup>
     <PostBuildEvent>"%OptPath%\apps\DedgeSign\AutoSign.cmd" "$(TargetPath)"</PostBuildEvent>
   </PropertyGroup>
   ```

## Additional Options

- To sign recursively (all files in output directory), add "Y" as a second parameter:
  ```
  "%OptPath%\apps\DedgeSign\AutoSign.cmd" "$(TargetPath)" Y
  ```

## Troubleshooting

1. Ensure `%OptPath%` environment variable is set correctly
2. Verify DedgeSign is properly deployed to `%OptPath%\apps\DedgeSign\`
3. Check build output for any signing-related errors 