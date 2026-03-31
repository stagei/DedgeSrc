# create File list
# BRHDEBX
# BSFOPVA
# D4BCUSTP
# DBFBRAPG
# DRHRRAPG
# GMAMONI
# GMVOKLT
# M3MITMAS
# OKHRSPT

$files = @("BRHDEBX", "BSFOPVA", "D4BCUSTP", "DBFBRAPG", "DRHRRAPG", "GMAMONI", "GMVOKLT", "M3MITMAS", "OKHRSPT")

# check all  directories  k:\fkavd\NT,  k:\fkavd\utgatt , k:\cblarkiv for  files
# if file is not found in k:\fkavd\NT, k:\fkavd\utgatt , k:\cblarkiv then write path to console

$folderList = @("k:\fkaavd\NT", "k:\fkaavd\utgatt", "k:\cblarkiv")

foreach ($file in $files) {
    foreach ($folder in $folderList) {
        # check directories recursively for any file or folder with the name $file
        $found = Get-ChildItem -Path $folder -Recurse -Filter $file -ErrorAction SilentlyContinue
        if ($found -eq $null) {
            Write-Host "File $file not found in $folder"
        }
        else {
            Write-Host "File $file found in $folder"
        }
    }
}

