param(
    $filename = "")

Write-Host "================================================================================="
Write-Host "Skript for å tilbakestille FKAVDNT til siste produksjonsetting av: $filename"
Write-Host "================================================================================="

# sjekk om filnavnet inneholder punktum og opprett feilmelding hvis det gjør det
if ($filename -match "\.") {
    Write-Host "**> Feil: Filnavnet inneholder punktum."
    exit
}
Write-Host "--> Filnavn: $filename"

$cblArchiveFolder = "K:\CBLARKIV\$filename\"

# Sjekk om $cblArchiveFolder eksisterer
if (-not (Test-Path $cblArchiveFolder -PathType Container )) {
    Write-Host "**> Feil: $cblArchiveFolder eksisterer ikke. Ingenting å tilbakestille."
    exit
}

$tempFolder = "C:\TEMPFK\RestoreProdVersionToDev\"
# Fjern temp-mappen hvis den eksisterer
if (Test-Path $tempFolder) {
    Remove-Item -Recurse -Force $tempFolder  | Out-Null
}
$fileTempFolder = $tempFolder + $filename + "\"

# Create folder $tempFolder
New-Item -ItemType Directory -Path $fileTempFolder | Out-Null

$targetFolder = "k:\fkavd\nt\"
$targetFolderSrc = "k:\fkavd\nt\"
$targetFolderCpy = "K:\fkavd\sys\cpy\"

$targetFileInt = $targetFolder + $filename + ".int"
$targetFileBnd = $targetFolder + $filename + ".bnd"
$targetFileIdy = $targetFolder + $filename + ".idy"

# Finn den nyeste zip-filen i $cblArchiveFolder
$latestZip = Get-ChildItem -Path $cblArchiveFolder -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$fileTempFolder = $tempFolder + $filename + "\"

# Pakk ut den nyeste zip-filen til $tempFolder
Expand-Archive -Path $latestZip.FullName -DestinationPath $fileTempFolder

$files = Get-ChildItem -Path $fileTempFolder -Filter "*.*" -Exclude "*.txt" -File -Recurse | Select-Object @{Name = "FullName"; Expression = { $_.FullName.Replace($tempFolder, "") } }, LastWriteTime, Length
Write-Host "--> Innhold i siste zip fil i cblarkiv :" $latestZip.Name
$files | Format-Table -Property FullName, LastWriteTime, Length -AutoSize

$array = @()

# Spør brukeren om de vil tilbakestille til den nyeste zip-filen
$revert = Read-Host "--> Tilbakestill kildekode (cbl/cpy) til den nyeste zip-filen? (j/n)"

if ($revert -ne "j" -and $revert -ne "J") {
    Write-Host "**> Tilbakestilling av kildekode for $filename avbrutt."
    exit
}

# løkke gjennom alle filene i $tempFolder
foreach ($file in Get-ChildItem -Path $fileTempFolder"*.*" -File -Exclude "*.txt") {
    $targetFile = $targetFolderSrc + $file.Name
    Copy-Item $file.FullName $targetFile
    Write-Host "--> Kopierte $file til $targetFile"
    if ($file.Extension -eq ".BND") {
        $array += $file.Name
    }
}
# Kopier $tempFolder"*.cbl " $targetFolderSrc
$fileTempFolder = $fileTempFolder + "cpy\"

# løkke gjennom alle filene i $tempFolder
foreach ($file in Get-ChildItem -Path $fileTempFolder"*.*" -Exclude "*.txt") {
    $targetFile = $targetFolderCpy + $file.Name
    Copy-Item $file.FullName $targetFile
    Write-Host "--> Kopierte $file til $targetFile."
}

$cmdarray = @()
$cmdarray += "k:"
$cmdarray += "cd $targetFolder"
foreach ($file in $array) {
    $command = "rexx " + $targetFolder + "dirbind " + $targetFolder + $file + " fkavdnt"
    $cmdarray += $command
}

# $cmdarray += "pause"
$cmdarray += "exit"

$cmdFile = $tempFolder + "BindFiles.cmd"
# $cmdarray | Out-File $cmdFile -Encoding ascii

set-content -Path $cmdFile  -Value $cmdarray
db2cmd.exe -w $cmdFile
Write-Host "--> Bind fullført"

# Sett endret tidsstempel for målfilen
# check if the target file exists
if (-not (Test-Path $targetFileInt -PathType Leaf )) {
    (Get-Item $targetFileBnd).LastWriteTimeUtc = (Get-Item $targetFileInt).LastWriteTimeUtc
    Write-Host "--> Endret tidsstempel for $targetFileBnd satt til å matche $targetFileInt."
}

(Get-Item $targetFileIdy).LastWriteTimeUtc = (Get-Item $targetFileInt).LastWriteTimeUtc
Write-Host "--> Endret tidsstempel for $targetFileIdy satt til å matche $targetFileInt."

Remove-Item -Recurse -Force $tempFolder | Out-Null
Write-Host "--> Fjernet $tempFolder."
Write-Host "==> Tilbakestilling av kildekode for $filename er fullført."

