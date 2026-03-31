param (
    [string]$folderPath = "C:\tmp\checkin2"  # Default path, can be overridden by passing parameter
)

# Azure DevOps Organization and Project details
$organization = "Dedge"
$project = "Dedge"
$repository = "Dedge"
$apiVersion = "7.1"  # API version
$personalAccessToken = "f53cdny64fbuehfy3rofdbz5mxgjnvhlxwmgbjrazg745uey4euq" # Your Personal Access Token with appropriate permissions

# Encode PAT for Authorization in the header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$personalAccessToken"))
$headers = @{
    Authorization = "Basic $base64AuthInfo"
}

# Get the latest commit SHA from the master branch
$shaUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/refs?filter=heads/master&api-version=$apiVersion"
$shaResponse = Invoke-RestMethod -Uri $shaUrl -Method Get -Headers $headers
$latestSha = $shaResponse.value[0].objectId
Write-Host "Latest SHA on master: $latestSha"

# Function to recursively get all files in the directory
function Get-FilesRecursively {
    param (
        [string]$path
    )
    Get-ChildItem -Path $path -Recurse -File
}

# Function to check if a file exists in the repository
function Check-FileExists {
    param (
        [string]$filePath
    )
    $fileUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/items?path=$filePath&api-version=$apiVersion"
    try {
        $fileResponse = Invoke-RestMethod -Uri $fileUrl -Method Get -Headers $headers
        return $true
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            return $false
        } else {
            throw $_
        }
    }
}

# Collect all files from the specified directory recursively
$files = Get-FilesRecursively -path $folderPath

# Prepare the list of changes for the API request
$changes = @()
foreach ($file in $files) {
    # Calculate the path relative to the $folderPath
    $relativePath = $file.FullName.Substring($folderPath.Length + 1).Replace('\', '/')

    $fileExists = Check-FileExists -filePath $relativePath

    # $content = Get-Content -Path $file.FullName -Raw
    # $encodedContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    $content = Get-Content -Path $file.FullName -Raw -Encoding 1252
    $encodedContent = [Convert]::ToBase64String([System.Text.Encoding]::GetEncoding(1252).GetBytes($content))

    $changes += @{
        changeType = if ($fileExists) { "edit" } else { "add" }
        item = @{
            path = $relativePath
        }
        newContent = @{
            content = $encodedContent
            contentType = "base64encoded"
        }
    }
}

# Construct the body of the request
$body = @{
    refUpdates = @(
        @{
            name = "refs/heads/master"
            oldObjectId = $latestSha
        }
    )
    commits = @(
        @{
            comment = "Automated commit of files from $folderPath"
            changes = $changes
        }
    )
} | ConvertTo-Json -Depth 5

# URL for the REST API call to push changes
$url = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/pushes?api-version=$apiVersion"

# Execute the REST API call
try {
    $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json"
    Write-Host "Push successful to master branch."
    Write-Host "Response: $response"
} catch {
    Write-Host "Error during push: $_"
    $_.Exception.Response | Format-List -Force # Additional debug info
}

