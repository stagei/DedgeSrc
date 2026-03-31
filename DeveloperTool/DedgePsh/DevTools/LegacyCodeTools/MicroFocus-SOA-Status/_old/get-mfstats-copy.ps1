Invoke-WebRequest -Uri "http://p-no1fkmprd-soa:9000/MF_STATISTICS" -OutFile e:\batchscript\soa\mfstats.txt                           
$normal = gc e:\batchscript\soa\mfstats.txt|Select-String "normal processing threads running"                                 
$stat = $normal.Line.Replace("normal processing threads running (max", "/").replace(")", "")                      
$ct = $stat.Split("/")
$dt = get-date -format "yyyyMMddhhmm"
$wkmonpath = "\\DEDGE.fk.no\erpprog\COBNT\monitor\" + $dt + "_soa.mon"
$message = $dt + " SOA"
if([int]$ct[0].Trim() -lt 50) { 
	$message = $message + " 0000 " + "SOA OK: " + $normal
	write-host $message
} else {
	$message = $message + " 1000 " + "SOA Threads HIGH: " + $normal
	$message = $message + ' Sjekk <a href="http://p-no1fkmprd-soa:9000/MF_STATISTICS" target="_blank">SOA</a>'
	write-host $message
}

write-host $message
# set-content -Path $wkmonpath -Value $message


