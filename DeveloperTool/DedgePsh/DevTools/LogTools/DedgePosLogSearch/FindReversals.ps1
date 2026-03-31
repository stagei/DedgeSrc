# Create an array from values
$numbers = @(
    '"MessageCategory":"Reversal"'
)

# Search files in folder $env:OptPath\work\LogBackup\Unzipped for each string in the array
for ($i = 0; $i -lt $numbers.Length; $i++) {
    $number = $numbers[$i]
    $files = Get-ChildItem -Path "$env:OptPath\work\LogBackup\Unzipped" -Recurse -Filter "*vim_2024*.log" | Select-String -Pattern $number
    # write the filename and $number to the console

    if ($files) {
        foreach ($file in $files) {
            Add-Content -Path "$env:OptPath\work\LogBackup\FindReversalTrx.log" -Value ("Found $number in file: " + $file.Path + ". Line: " + $file.Line)
            if ($file.Line.Contains('"Result":"Success"')) {
                Write-Host "Found $number in " $file.Path
                # Log result to FindReversalTrx.log
                $pattern = "00\d{4}-\d{6}-\d{1}"
                $line = $file.Line
                $trxResultTemp = $line | Select-string -Pattern "00\d{4}-\d{6}-\d{1}" -AllMatches
                $trxResult = $trxResultTemp.Matches.Value
                # Log only the matched string to FindReversalTrxEcrId.log
                Add-Content -Path "$env:OptPath\work\LogBackup\FindReversalTrxEcrId.log" -Value "$trxResult"
            }
        }
    }
}

#"2024-04-27 14:00:14.6476 INFO  11 Verifone.Vim.Internal.Protocol.Epas.EpasProtocolHandler - TerminalId: BT_HFS2, Handle event: Type: Receive, Load: {"SaleToPOIResponse":{"MessageHeader":{"MessageClass":"Service","MessageCategory":"Reversal","MessageType":"Response","ServiceID":"404478203","SaleID":"FKABT_HFS2","POIID":"BT_HFS2"},"ReversalResponse":{"Response":{"Result":"Failure","ErrorCondition":"NotFound","AdditionalResponse":"Reason: Failed to get transaction"},"POIData":{"POITransactionID":{"TransactionID":"010288037309202024042717142264700002327000001","TimeStamp":"2024-04-27T14:01:10.000+00:00"}},"ReversedAmount":"200.00"}}}"

