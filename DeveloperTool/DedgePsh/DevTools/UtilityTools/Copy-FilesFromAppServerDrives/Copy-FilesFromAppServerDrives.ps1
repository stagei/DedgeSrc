# Copy files from network location to local temp folder, excluding log files and files larger than 100 MB
Write-Host "Copying newer files from \\p-no1fkmprd-app\opt to $env:OptPath\data\PrdSrcCpy\<servername>\opt Folder `n(excluding *.log and *.csv files and files larger than 100 MB)" -ForegroundColor Blue
$serverList = @("p-no1fkmprd-app")
foreach ($server in $serverList) {
    Remove-Item "$env:OptPath\data\PrdSrcCpy\$server\optFolder" -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path "$env:OptPath\data\PrdSrcCpy\$server\optFolder" -ItemType Directory -Force
    robocopy "\\$server\opt" "$env:OptPath\data\PrdSrcCpy\$server\opt" /E /XF *.log *.csv /MAX:104857600 /XO
}
Write-Host "All done!" -ForegroundColor Green

