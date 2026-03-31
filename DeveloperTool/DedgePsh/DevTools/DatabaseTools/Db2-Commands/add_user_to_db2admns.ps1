Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\fksveeri" -ErrorAction Stop

Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\fkgeista" -ErrorAction Stop

Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\$env:USERNAME" -ErrorAction Stop

Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\db2nt" -ErrorAction Stop

Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere" -ErrorAction Stop

Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full" -ErrorAction Stop

Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\DB2ADMNS" -ErrorAction Stop

Add-LocalGroupMember -Group DB2USERS -member "$env:USERDOMAIN\Domain Users" -ErrorAction Stop

Get-LocalGroupMember -Group DB2ADMNS | Format-Table -AutoSize

Get-LocalGroupMember -Group DB2USERS | Format-Table -AutoSize

