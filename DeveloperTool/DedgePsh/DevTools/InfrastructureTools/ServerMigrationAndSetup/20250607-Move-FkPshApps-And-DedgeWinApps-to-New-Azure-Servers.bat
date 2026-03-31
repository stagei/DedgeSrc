rd /q /s "\\p-no1fkmprd-app\opt\DedgeWinApps\"
md "\\p-no1fkmprd-app\opt\DedgeWinApps\"
xcopy "\\p-no1fkmprd-app\opt\apps\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\" /E /Y
xcopy "\\p-no1fkmprd-app\APPS\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\" /E /Y
xcopy "\\sfkerp14\opt\apps\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\"
xcopy "\\p-no1fkmprd-app\opt\psh\*" "\\p-no1fkmprd-app\opt\DedgePshApps\" /E /Y
xcopy "\\p-no1fkmprd-app\opt\psh\*" "\\p-no1fkmprd-app\opt\DedgePshApps\" /E /Y
xcopy "\\p-no1fkmprd-app\sched\*" "\\p-no1fkmprd-app\opt\DedgePshApps\" /E /Y
xcopy "\\p-no1fkmprd-app\opt\*" "\\p-no1fkmprd-app\opt\DedgePshApps\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\"
xcopy "\\sfk-erp-03\opt\psh\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\" /E /Y

rd /q /s "\\t-no1fkmtst-app\opt\DedgeWinApps\"
md "\\t-no1fkmtst-app\opt\DedgeWinApps\"
xcopy "\\t-no1batch-vm01\opt\apps\*" "\\t-no1fkmtst-app\opt\DedgeWinApps\" /E /Y

rd /q /s "\\t-no1fkmtst-app\opt\DedgePshApps\"
md "\\t-no1fkmtst-app\opt\DedgePshApps\"
xcopy "\\sfk-erp-03\batch\*" "\\t-no1fkmtst-app\opt\DedgePshApps\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgeWinApps\FixJob\"
md "\\p-no1fkmprd-app\opt\DedgeWinApps\FixJob\"
xcopy "\\p-no1fkmprd-app\opt\apps\FixJob\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\FixJob\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\ad\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\ad\"
xcopy "\\p-no1fkmprd-app\opt\psh\ad\*" "\\p-no1fkmprd-app\opt\DedgePshApps\ad\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgeWinApps\DedgeDailyRoutine\"
md "\\p-no1fkmprd-app\opt\DedgeWinApps\DedgeDailyRoutine\"
xcopy "\\p-no1fkmprd-app\opt\apps\DedgeDailyRoutine\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\DedgeDailyRoutine\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgeWinApps\GetPeppolDirectory\"
md "\\p-no1fkmprd-app\opt\DedgeWinApps\GetPeppolDirectory\"
xcopy "\\p-no1fkmprd-app\opt\apps\GetPeppolDirectory\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\GetPeppolDirectory\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\HentSLF\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\HentSLF\"
xcopy "\\p-no1fkmprd-app\opt\psh\HentSLF\*" "\\p-no1fkmprd-app\opt\DedgePshApps\HentSLF\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgeWinApps\FkmUtils\"
md "\\p-no1fkmprd-app\opt\DedgeWinApps\FkmUtils\"
xcopy "\\p-no1fkmprd-app\opt\apps\FkmUtils\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\FkmUtils\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\DM010Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\DM010Runner\"
xcopy "\\sfk-erp-03\opt\psh\FAT\DM010Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\DM010Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT007Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT007Runner\"
xcopy "\\sfk-erp-03\opt\psh\FAT\MT007Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT007Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\CopyToMIG\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\CopyToMIG\"
xcopy "\\sfk-erp-03\opt\psh\FAT\CopyToMIG\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\CopyToMIG\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT014Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT014Runner\"
xcopy "\\sfk-erp-03\opt\psh\FAT\MT014Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT014Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT015Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT015Runner\"
xcopy "\\sfk-erp-03\opt\psh\FAT\MT015Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT015Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT038Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT038Runner\"
xcopy "\\sfk-erp-03\opt\psh\FAT\MT038Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT038Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT039Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT039Runner\"
xcopy "\\sfk-erp-03\opt\psh\FAT\MT039Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\MIG\MT039Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\DM010Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\DM010Runner\"
xcopy "\\sfk-erp-03\opt\psh\DM010Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\DM010Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT007Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT007Runner\"
xcopy "\\sfk-erp-03\opt\psh\MT007Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT007Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\CopyToSIT\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\CopyToSIT\"
xcopy "\\sfk-erp-03\opt\psh\CopyToKAT\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\CopyToSIT\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT014Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT014Runner\"
xcopy "\\sfk-erp-03\opt\psh\MT014Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT014Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT015Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT015Runner\"
xcopy "\\sfk-erp-03\opt\psh\MT015Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT015Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT038Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT038Runner\"
xcopy "\\sfk-erp-03\opt\psh\MT038Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT038Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT039Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT039Runner\"
xcopy "\\sfk-erp-03\opt\psh\MT039Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\SIT\MT039Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT003Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT003Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT003Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT003Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT007Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT007Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT007Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT007Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\CopyToVFK\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\CopyToVFK\"
xcopy "\\sfk-erp-03\opt\psh\VFK\CopyToVFK\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\CopyToVFK\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT014Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT014Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT014Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT014Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT015Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT015Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT015Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT015Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT020Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT020Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT020Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT020Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT041Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT041Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT041Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT041Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT042Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT042Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT042Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT042Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT047Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT047Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT047Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT047Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT055Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT055Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT055Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT055Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT056Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT056Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT056Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT056Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT063Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT063Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT063Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT063Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT068Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT068Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFK\MT068Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFK\MT068Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\COBVFT\cdsimport\"
md "\\t-no1fkmfsp-app\COBVFT\cdsimport\"
xcopy "\\sfk-erp-03\COBVFT\cdsimport\*" "\\t-no1fkmfsp-app\COBVFT\cdsimport\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT003Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT003Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT003Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT003Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT004Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT004Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT004Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT004Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT007Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT007Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT007Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT007Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\CopyToVFT\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\CopyToVFT\"
xcopy "\\sfk-erp-03\opt\psh\VFT\CopyToVFT\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\CopyToVFT\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT014Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT014Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT014Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT014Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT015Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT015Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT015Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT015Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT020Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT020Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT020Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT020Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT041Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT041Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT041Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT041Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\mt042runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\mt042runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\mt042runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\mt042runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT047Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT047Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT047Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT047Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT050Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT050Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT050Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT050Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT055Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT055Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT055Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT055Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT056Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT056Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT056Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT056Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT060Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT060Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT060Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT060Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT063Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT063Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT063Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT063Runner\" /E /Y

rd /q /s "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT068Runner\"
md "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT068Runner\"
xcopy "\\sfk-erp-03\opt\psh\VFT\MT068Runner\*" "\\t-no1fkmfsp-app\opt\DedgePshApps\VFT\MT068Runner\" /E /Y

rd /q /s "\\t-no1fkmtst-app\opt\DedgePshApps\Ehandel-Test\"
md "\\t-no1fkmtst-app\opt\DedgePshApps\Ehandel-Test\"
xcopy "\\sfk-erp-03\batch\*" "\\t-no1fkmtst-app\opt\DedgePshApps\Ehandel-Test\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\Agrideler\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\Agrideler\"
xcopy "\\p-no1fkmprd-app\opt\psh\Agrideler\*" "\\p-no1fkmprd-app\opt\DedgePshApps\Agrideler\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\brreg\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\brreg\"
xcopy "\\p-no1fkmprd-app\opt\psh\brreg\*" "\\p-no1fkmprd-app\opt\DedgePshApps\brreg\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\BRREG\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\BRREG\"
xcopy "\\p-no1fkmprd-app\opt\psh\BRREG\*" "\\p-no1fkmprd-app\opt\DedgePshApps\BRREG\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\Start-BsbaorScripts\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\Start-BsbaorScripts\"
xcopy "\\p-no1fkmprd-app\sched\*" "\\p-no1fkmprd-app\opt\DedgePshApps\Start-BsbaorScripts\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\DM010Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\DM010Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\DM010Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\DM010Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\ExportAllScheduledTasks\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\ExportAllScheduledTasks\"
xcopy "\\p-no1fkmprd-app\opt\psh\ExportAllScheduledTasks\*" "\\p-no1fkmprd-app\opt\DedgePshApps\ExportAllScheduledTasks\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\Run-Gxbfloi\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\Run-Gxbfloi\"
xcopy "\\p-no1fkmprd-app\opt\*" "\\p-no1fkmprd-app\opt\DedgePshApps\Run-Gxbfloi\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\FLogRulesRunner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\FLogRulesRunner\"
xcopy "\\p-no1fkmprd-app\opt\psh\FLogRulesRunner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\FLogRulesRunner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\Skansen\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\Skansen\"
xcopy "\\p-no1fkmprd-app\opt\psh\Skansen\*" "\\p-no1fkmprd-app\opt\DedgePshApps\Skansen\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\KSL\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\KSL\"
xcopy "\\p-no1fkmprd-app\opt\psh\KSL\*" "\\p-no1fkmprd-app\opt\DedgePshApps\KSL\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\Enhetsregisteret\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\Enhetsregisteret\"
xcopy "\\p-no1fkmprd-app\opt\psh\Enhetsregisteret\*" "\\p-no1fkmprd-app\opt\DedgePshApps\Enhetsregisteret\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\hentslf\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\hentslf\"
xcopy "\\p-no1fkmprd-app\opt\psh\hentslf\*" "\\p-no1fkmprd-app\opt\DedgePshApps\hentslf\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\Kveldssjekk\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\Kveldssjekk\"
xcopy "\\p-no1fkmprd-app\opt\psh\Kveldssjekk\*" "\\p-no1fkmprd-app\opt\DedgePshApps\Kveldssjekk\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\KvernelandGarantiExport\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\KvernelandGarantiExport\"
xcopy "\\p-no1fkmprd-app\opt\psh\KvernelandGarantiExport\*" "\\p-no1fkmprd-app\opt\DedgePshApps\KvernelandGarantiExport\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\LandaxPUFF\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\LandaxPUFF\"
xcopy "\\p-no1fkmprd-app\opt\psh\LandaxPUFF\*" "\\p-no1fkmprd-app\opt\DedgePshApps\LandaxPUFF\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgeWinApps\FKAFSWatcherActions\"
md "\\p-no1fkmprd-app\opt\DedgeWinApps\FKAFSWatcherActions\"
xcopy "\\p-no1fkmprd-app\APPS\FKAFSWatcherActions\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\FKAFSWatcherActions\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\PickupPointReport\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\PickupPointReport\"
xcopy "\\p-no1fkmprd-app\opt\psh\PickupPointReport\*" "\\p-no1fkmprd-app\opt\DedgePshApps\PickupPointReport\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\CBLRun\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\CBLRun\"
xcopy "\\p-no1fkmprd-app\opt\psh\CBLRun\*" "\\p-no1fkmprd-app\opt\DedgePshApps\CBLRun\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\cdsmonitor\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\cdsmonitor\"
xcopy "\\p-no1fkmprd-app\opt\psh\cdsmonitor\*" "\\p-no1fkmprd-app\opt\DedgePshApps\cdsmonitor\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\copytoprod\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\copytoprod\"
xcopy "\\p-no1fkmprd-app\opt\psh\copytoprod\*" "\\p-no1fkmprd-app\opt\DedgePshApps\copytoprod\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\D4BPlukkRunner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\D4BPlukkRunner\"
xcopy "\\p-no1fkmprd-app\opt\psh\D4BPlukkRunner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\D4BPlukkRunner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\DM021Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\DM021Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\DM021Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\DM021Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\ED007Check\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\ED007Check\"
xcopy "\\p-no1fkmprd-app\opt\psh\ED007Check\*" "\\p-no1fkmprd-app\opt\DedgePshApps\ED007Check\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\MT003Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\MT003Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\MT003Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\MT003Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\MT004Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\MT004Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\MT004Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\MT004Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\MT007Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\MT007Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\MT007Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\MT007Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\MT014Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\MT014Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\MT014Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\MT014Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\CopyToProd\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\CopyToProd\"
xcopy "\\p-no1fkmprd-app\opt\psh\CopyToProd\*" "\\p-no1fkmprd-app\opt\DedgePshApps\CopyToProd\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\MT015Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\MT015Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\MT015Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\MT015Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\MT038Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\MT038Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\MT038Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\MT038Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\MT039Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\MT039Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\MT039Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\MT039Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\VI001Runner\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\VI001Runner\"
xcopy "\\p-no1fkmprd-app\opt\psh\VI001Runner\*" "\\p-no1fkmprd-app\opt\DedgePshApps\VI001Runner\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgePshApps\PIMEKSP\"
md "\\p-no1fkmprd-app\opt\DedgePshApps\PIMEKSP\"
xcopy "\\p-no1fkmprd-app\opt\psh\PIMEKSP\*" "\\p-no1fkmprd-app\opt\DedgePshApps\PIMEKSP\" /E /Y

rd /q /s "\\p-no1fkmprd-app\opt\DedgeWinApps\KimenExport\"
md "\\p-no1fkmprd-app\opt\DedgeWinApps\KimenExport\"
xcopy "\\sfkerp14\opt\apps\KimenExport\*" "\\p-no1fkmprd-app\opt\DedgeWinApps\KimenExport\" /E /Y

rd /q /s "\\t-no1fkmtst-app\opt\DedgeWinApps\DedgeDailyRoutine\"
md "\\t-no1fkmtst-app\opt\DedgeWinApps\DedgeDailyRoutine\"
xcopy "\\t-no1batch-vm01\opt\apps\DedgeDailyRoutine\*" "\\t-no1fkmtst-app\opt\DedgeWinApps\DedgeDailyRoutine\" /E /Y

