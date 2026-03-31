$PSVersionTable.PSVersion
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host "PowerShell major version must be 5" -ForegroundColor Red
    exit 1
}

# Set UI language based on user choice
$uiLanguage = if ($env:USERNAME.ToUpper() -eq 'FKGEISTA' -or $env:USERNAME.ToUpper() -eq 'FKSVEERI') {
    'en-US'
} else {
    'nb-NO'
}

Write-Host "Setting Windows UI language to $uiLanguage"

Set-WinUILanguageOverride -Language $uiLanguage

# Set the system locale (used for non-Unicode programs) to Norwegian Bokmål
Set-WinSystemLocale -SystemLocale nb-NO

Set-Culture nb-NO

# Set the geographic location to Norway (0xb1 is the GeoID for Norway)
Set-WinHomeLocation -GeoId 0xb1

# Add both English and Norwegian to the language list, with English first
# Note: This affects the Windows language list order and fallback languages,
# but the actual UI display language is controlled by Set-WinUILanguageOverride below
# Add English first for spell checking and other language-specific features, followed by Norwegian
Set-WinUserLanguageList -LanguageList en-US, nb-NO -Force

# Create a new language list with Norwegian as base
$langList = New-WinUserLanguageList -Language nb-NO

# Clear any existing keyboard layouts
$langList[0].InputMethodTips.Clear()

# Add Norwegian keyboard layout (0414:00000414 is the language ID for Norwegian)
$langList[0].InputMethodTips.Add('0414:00000414')

# Apply the updated language list with Norwegian keyboard
Set-WinUserLanguageList -LanguageList $langList -Force

# Set timezone to Central European Time (covers Norway)
Set-TimeZone -Id 'Central Europe Standard Time'

Set-Culture nb-NO

