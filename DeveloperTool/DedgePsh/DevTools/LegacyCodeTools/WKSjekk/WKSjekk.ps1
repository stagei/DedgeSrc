# powershell-script for å ta fram logger etter nattens kjøringer
#//file://DEDGE.fk.no/erpprog/cobnt/wksjekk.log

# list contents of wksjekk.log in a new window
Start-Process pwsh.exe -ArgumentList '-noexit','-Command', 'get-content -Path \\DEDGE.fk.no\erpprog\cobnt\wksjekk.log'

# file://DEDGE.fk.no/erpprog/cobnt/sjekkpgm.log
Start-Process pwsh.exe -ArgumentList '-noexit','-Command', 'get-content -Path \\DEDGE.fk.no\erpprog\cobnt\sjekkpgm.log'

# file://DEDGE.fk.no/erpprog/cobnt/restrap.log
Start-Process pwsh.exe -ArgumentList '-noexit','-Command', 'get-content -Path \\DEDGE.fk.no\erpprog\cobnt\restrap.log'

