@REM md "%OptPath%\Data\ScheduledTasksWindowsExport\p-no1fkmprd-app"
@REM cd "%OptPath%\Data\ScheduledTasksWindowsExport\p-no1fkmprd-app"

@REM xcopy "c:\windows\system32\tasks" "%OptPath%\Data\ScheduledTasksWindowsExport\p-no1fkmprd-app" /E /I /Y

@REM setx "OptPath" "E:\opt" /M

@REM md "%OptPath%\Data\ScheduledTasksWindowsExport\t-no1fkmtst-app"
@REM cd "%OptPath%\Data\ScheduledTasksWindowsExport\t-no1fkmtst-app"

@REM xcopy "c:\windows\system32\tasks" "%OptPath%\Data\ScheduledTasksWindowsExport\t-no1fkmtst-app" /E /I /Y

rd /q /s "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp13"
rd /q /s "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp14"
rd /q /s "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp12"
rd /q /s "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\t-no1batch-vm01""

md "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp13\p-no1fkmprd-app\WindowsDirectExport"
md "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp14\p-no1fkmprd-app\WindowsDirectExport"
md "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp12\p-no1fkmprd-app\WindowsDirectExport"
md "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\t-no1batch-vm01\t-no1fkmtst-app\WindowsDirectExport"
xcopy "\\sfkerp13\opt\Data\ScheduledTasksWindowsExport\p-no1fkmprd-app" "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp13\p-no1fkmprd-app\WindowsDirectExport" /E /I /Y
xcopy "\\sfkerp14\opt\Data\ScheduledTasksWindowsExport\p-no1fkmprd-app" "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp14\p-no1fkmprd-app\WindowsDirectExport" /E /I /Y
xcopy "\\sfkerp12\opt\Data\ScheduledTasksWindowsExport\p-no1fkmprd-app" "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\sfkerp12\p-no1fkmprd-app\WindowsDirectExport" /E /I /Y
xcopy "\\t-no1batch-vm01\opt\Data\ScheduledTasksWindowsExport\t-no1fkmtst-app" "C:\opt\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\customtasks\t-no1batch-vm01\t-no1fkmtst-app\WindowsDirectExport" /E /I /Y

