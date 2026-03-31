# Variables
$organization = "Dedge"
$project = "Dedge"
$repositoryId = "Dedge"
$pat = "hax4fdkic466xx7pxdcizf6ecj6mcluy74ht4ofeqr5auzq2pd7a"
$textToFind = "bkfinfa"
$apiVersion = "6.0-preview.1"
$apiVersion = "7.1-preview.1"

# Base64-encode the Personal Access Token (PAT)
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))

# Define the search request body manually
$body = @"
{
    "searchText": "$textToFind",
    "filters": {
        "Project": ["$project"],
        "Repository": ["$repositoryId"]
    },
    "`$top": 100
}
"@

# Search API URL
$searchUrl = "https://almsearch.dev.azure.com/$organization/_apis/search/codesearchresults?api-version=$apiVersion"

# Output the body to see what is being sent
Write-Output "Request Body: $body"

# Invoke the search request
$response = Invoke-RestMethod -Uri $searchUrl -Method Post -Body $body -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

# Parse and display results
foreach ($result in $response.results) {
    $fileName = $result.fileName
    $matches = $result.matches | ForEach-Object { $_.previewText } # This gets a preview/snippet containing the search text
    Write-Output "Found in file: $fileName"
    # Write all lines containing the search text
    foreach ($match in $matches) {
        Write-Output "  $match"
    }
}

