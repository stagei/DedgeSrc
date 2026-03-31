@echo off
@REM ---------------------------
@REM Setup
@REM ---------------------------
@REM The Setup program accepts optional command line parameters.

@REM /HELP, /?
@REM Shows this information.
@REM /SP-
@REM Disables the "This will install... Do you wish to continue?" message box at the beginning of Setup.
@REM /SILENT, /VERYSILENT
@REM Instructs Setup to be silent or very silent.
@REM /SUPPRESSMSGBOXES
@REM Instructs Setup to suppress message boxes.
@REM /LOG
@REM Causes Setup to create a log file in the user's TEMP directory.
@REM /LOG="filename"
@REM Same as /LOG, except it allows you to specify a fixed path/filename to use for the log file.
@REM /NOCANCEL
@REM Prevents the user from cancelling during the installation process.
@REM /NORESTART
@REM Prevents Setup from restarting the system following a successful installation, or after a Preparing to Install failure that requests a restart.
@REM /RESTARTEXITCODE=exit code
@REM Specifies a custom exit code that Setup is to return when the system needs to be restarted.
@REM /CLOSEAPPLICATIONS
@REM Instructs Setup to close applications using files that need to be updated.
@REM /NOCLOSEAPPLICATIONS
@REM Prevents Setup from closing applications using files that need to be updated.
@REM /FORCECLOSEAPPLICATIONS
@REM Instructs Setup to force close when closing applications.
@REM /FORCENOCLOSEAPPLICATIONS
@REM Prevents Setup from force closing when closing applications.
@REM /LOGCLOSEAPPLICATIONS
@REM Instructs Setup to create extra logging when closing applications for debugging purposes.
@REM /RESTARTAPPLICATIONS
@REM Instructs Setup to restart applications.
@REM /NORESTARTAPPLICATIONS
@REM Prevents Setup from restarting applications.
@REM /LOADINF="filename"
@REM Instructs Setup to load the settings from the specified file after having checked the command line.
@REM /SAVEINF="filename"
@REM Instructs Setup to save installation settings to the specified file.
@REM /LANG=language
@REM Specifies the internal name of the language to use.
@REM /DIR="x:\dirname"
@REM Overrides the default directory name.
@REM /GROUP="folder name"
@REM Overrides the default folder name.
@REM /NOICONS
@REM Instructs Setup to initially check the Don't create a Start Menu folder check box.
@REM /TYPE=type name
@REM Overrides the default setup type.
@REM /COMPONENTS="comma separated list of component names"
@REM Overrides the default component settings.
@REM /TASKS="comma separated list of task names"
@REM Specifies a list of tasks that should be initially selected.
@REM /MERGETASKS="comma separated list of task names"
@REM Like the /TASKS parameter, except the specified tasks will be merged with the set of tasks that would have otherwise been selected by default.
@REM /PASSWORD=password
@REM Specifies the password to use.

@REM For more detailed information, please visit https://jrsoftware.org/ishelp/index.php?topic=setupcmdline

echo Testing Cursor installation...

echo Backing up TEMP and TMP
set BACKUP_TEMP=%TEMP%
set BACKUP_TMP=%TMP%

echo Setting TEMP and TMP to C:\TEMPFK
setx TEMP C:\TEMPFK /M
setx TMP C:\TEMPFK /M

echo Running Cursor installer
C:\Users\FKGEISTA\Downloads\CursorSetup-x64-1.6.26.exe
if %errorlevel% neq 0 (
    echo Error: Cursor installer failed
)

echo Restoring TEMP and TMP
setx TEMP %BACKUP_TEMP% /M
setx TMP %BACKUP_TMP% /M
echo Done

