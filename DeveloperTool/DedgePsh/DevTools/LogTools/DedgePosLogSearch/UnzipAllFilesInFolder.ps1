# Unzip all files in folder $env:OptPath\work\LogBackup and save them in $env:OptPath\work\LogBackup\Unzipped
Get-ChildItem -Path $env:OptPath\work\LogBackup -Filter p-no1fkmprd-app*.zip | ForEach-Object {
    $zipFile = $_.FullName
    $destination = "$env:OptPath\work\LogBackup\Unzipped"
    # check if the destination folder exists, if not create it
    if (-not (Test-Path -Path $destination)) {
        New-Item -ItemType Directory -Path $destination
    }
    $destination = "$env:OptPath\work\LogBackup\Unzipped\p-no1fkmprd-app"
    # check if the destination folder exists, if not create it
    if (-not (Test-Path -Path $destination)) {
        New-Item -ItemType Directory -Path $destination
    }
    Expand-Archive -Path $zipFile -DestinationPath $destination
}

# Unzip all files in folder $env:OptPath\work\LogBackup and save them in $env:OptPath\work\LogBackup\Unzipped
Get-ChildItem -Path $env:OptPath\work\LogBackup -Filter sfk-batch-vm01*.zip | ForEach-Object {
    $zipFile = $_.FullName
    $destination = "$env:OptPath\work\LogBackup\Unzipped"
    # check if the destination folder exists, if not create it
    if (-not (Test-Path -Path $destination)) {
        New-Item -ItemType Directory -Path $destination
    }
    $destination = "$env:OptPath\work\LogBackup\Unzipped\sfk-batch-vm01"
    # check if the destination folder exists, if not create it
    if (-not (Test-Path -Path $destination)) {
        New-Item -ItemType Directory -Path $destination
    }
    Expand-Archive -Path $zipFile -DestinationPath $destination
}

