Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module SoftwareUtils -Force

$taskbarPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$shortcuts = @(
    @{
        Name = "Task Scheduler"
        Path = Get-CommandPathWithFallback -Name "taskschd.msc"
        IconPath = Get-CommandPathWithFallback -Name "taskschd.msc"
        Arguments = "/s"
    },
    @{
        Name = "Code"
        Path = Get-CommandPathWithFallback -Name "code.cmd"
        IconPath = Get-CommandPathWithFallback -Name "code.cmd"
        Arguments = ""
    },
    @{
        Name = "Cmd"
        Path = Get-CommandPathWithFallback -Name "cmd.exe"
        IconPath = Get-CommandPathWithFallback -Name "cmd.exe"
        Arguments = ""
    },
    @{
        Name = "PowerShell"
        Path = Get-CommandPathWithFallback -Name "powershell.exe"
        IconPath = Get-CommandPathWithFallback -Name "powershell.exe"
        Arguments = ""
    },
    @{
        Name = "Powershell Core"
        Path = Get-CommandPathWithFallback -Name "pwsh.exe"
        IconPath = Get-CommandPathWithFallback -Name "pwsh.exe"
        Arguments = ""
    },
    @{
        Name = "Db2 Admin CLI"
        Path = Get-CommandPathWithFallback -Name "db2cmdadmin.exe"
        IconPath = "$env:OptPath\DedgePshApps\Db2-CreateDb2CliShortCuts\IBM-DB2Admin.ico"
        Arguments = ""
    }
)

foreach ($shortcut in $shortcuts) {
    if ($shortcut.Path.Substring(1, 2) -eq ":\") {
        Add-TaskBarShortcut -ShortcutName $shortcut.Name -TargetPath $shortcut.Path -IconPath $shortcut.IconPath -Arguments $shortcut.Arguments
    }
}

