param(
	[Parameter(Mandatory = $false)]
	[string]$Receiver = "+4795762742",
	[Parameter(Mandatory = $false)]
	[switch]$SendSms
)
Import-Module GlobalFunctions -Force

$url = "http://$($env:COMPUTERNAME.ToUpper()):9000/MF_STATISTICS"
Invoke-WebRequest -Uri $url -OutFile e:\batchscript\soa\mfstats_sms.txt
$normal = gc e:\batchscript\soa\mfstats_sms.txt|Select-String "normal processing threads running"
$stat = $normal.Line.Replace("normal processing threads running (max", "/").replace(")", "")
$ct = $stat.Split("/")
$dt = Get-Date -Format "yyyyMMddHHmm"
$wkmonpath = "\\DEDGE.fk.no\erpprog\COBNT\monitor\" + $dt + "_soa.mon"
$message = $dt + " SOA"
if([int]$ct[0].Trim() -lt 500) {
	$message += " 0000 " + "SOA OK: " + $normal
	Write-LogMessage $message -Level INFO
} else {
	$message += " 1000 " + "SOA Threads HIGH: " + $normal
	$message += " Sjekk <a href=`"http://" + $($env:COMPUTERNAME.ToUpper()) + ":9000/MF_STATISTICS`" target=`"_blank`">SOA</a>"
	Write-LogMessage $message -Level WARN
	if($SendSms) {
		Send-Sms -Receiver $Receiver -Message $message
	}
}
if(-not $SendSms) {
	Set-Content -Path $wkmonpath -Value $message
}

