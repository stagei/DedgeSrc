param(
    [string]$receiver,
    [string]$message
)

Import-Module -Name GlobalFunctions -Force
if ($receiver -eq "-h" -or $receiver -eq "--help" -or $receiver -eq "/?") {
    Write-Host "Usage: Send-Sms <receiver> <message>"
    Write-Host ""
    Write-Host "Send an SMS message to the specified receiver. Use +<countrycode><number> for the receiver, without spaces or special characters."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  Send-Sms +4712345678 'Hello World'"
    Write-Host "  Send-Sms +4712345678,+4787654321 'Message to multiple receivers'"
    exit 0
}

Send-Sms -receiver $receiver -message $message

