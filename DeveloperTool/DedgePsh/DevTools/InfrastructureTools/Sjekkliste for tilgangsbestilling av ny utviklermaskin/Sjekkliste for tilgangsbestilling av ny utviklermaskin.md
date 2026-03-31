<p align="center"><span style="font-size:2.5em; font-weight:bold; text-decoration: underline;">SJEKKLISTE VED BESTILLING AV NY UTVIKLERMASKIN</span></p>


Denne sjekklisten dekker alle nødvendige tilganger og tiltak du bør sikre ved bestilling av ny utviklermaskin til utvikler, spesielt laget bestilling mot brukerstøtte og sikkerhet.


# Sikkerhets avdelingen

## Intune
- Intune - Devices - CyberArkEPM
- Intune - Devices - ASR Developers
# Policy
- Legge til PC i CyberArk EPM policy

# Brukerstøtte avdelingen

## Entra Tilganger
- Program Forsprang - Felles
- IT utvikling
- IT
- Intune_FKA_APP_Trio10
- InTune_FK_APP_IBM_DB2
- Dedge Stabilisering
- Dedge
- FKA / Drift og utvikling
- FKA / D22 (intern)
- FKA / Beste praksis Butikk
- ENTRA_APP_AVD_TEST-FK-Meny_Basisprod
- ENTRA_APP_AVD_TEST-FK-Meny-RPA
- ENTRA_APP_AVD_TEST-FK-Meny-Forhandler
- ENTRA_APP_AVD_QMF_for_Windows
- ENTRA_APP_AVD_POS_LoggAvAlt
- ENTRA_APP_AVD_POS_FK-Meny
- ENTRA_APP_AVD_Microsoft_Edge
- ENTRA_APP_AVD_Fleet_Planner_PROD
- ENTRA_APP_AVD_FK-Meny2
- ENTRA_APP_AVD_FK-Meny_Vareforsyning_Test_BASISVFT
- ENTRA_APP_AVD_FK-Meny_Vareforsyning_KAT_BASISVFK
- ENTRA_APP_AVD_FK-Meny_Test_Script
- ENTRA_APP_AVD_FK-Meny_Test
- ENTRA_APP_AVD_FK-Meny_SBTR_Pilot
- ENTRA_APP_AVD_FK-Meny_SBTR
- ENTRA_APP_AVD_FK-Meny_RPA_TEST
- ENTRA_APP_AVD_FK-Meny_POS
- ENTRA_APP_AVD_FK-Meny_Pilot
- ENTRA_APP_AVD_FK-Meny_KT_Ordre
- ENTRA_APP_AVD_FK-Meny_KT-Ordre_Test
- ENTRA_APP_AVD_FK-Meny_KT-butikk
- ENTRA_APP_AVD_FK-Meny_KAT_BASISSIT
- ENTRA_APP_AVD_FK-Meny_Innlan
- ENTRA_APP_AVD_FK-Meny_Funksjonstest_BASISMIG
- ENTRA_APP_AVD_FK-Meny_Forhandler_TEST
- ENTRA_APP_AVD_FK-Meny_Forhandler
- ENTRA_APP_AVD_FK-Meny_Brukerregister_Test_BASISVFT
- ENTRA_APP_AVD_FK-Meny_Brukerregister_KAT_BASISVFK
- ENTRA_APP_AVD_FK-Meny_Brukerregister_BasisTST
- ENTRA_APP_AVD_FK-Meny_Brukerregister_BasisSIT
- ENTRA_APP_AVD_FK-Meny_Brukerregister_BASISMIG
- ENTRA_APP_AVD_FK-Meny_Brukerregister
- ENTRA_APP_AVD_FK-Meny_Basisrap
- ENTRA_APP_AVD_FK-Meny_Basisprod_TEST
- ENTRA_APP_AVD_FK-Meny
- ENTRA_APP_AVD_DB2_Kommandolinjebehandler
- Dobbeltbetaling Butikk
- azure_p-backup_reader


## AD Tilganger
### Nettverk & VPN-tilgang
- VPN_FKA

### Andre applikasjoner
- APP_FleetPlanner_Azure_P
- APP_Momentum_Andre
- APP_QMF_Azure_P

### ERP- & Datatilgang
- ACL_ERPDATA_RW

### FK Meny Tilganger
- APP_Dedge_Azure_P
- APP_Dedge_2_Azure_P
- APP_Dedge_Onprem_P
- APP_Dedge_Brukerregister_Azure_P
- APP_Dedge_Forhandler_Azure_P
- APP_Dedge_Innlan_Azure_P
- APP_Dedge_POS_Azure_P
- APP_Dedge_Utvikling_Azure_P
- APP_Dedge_BasisMIG_Azure_P
- APP_Dedge_BasisRAP_Azure_P
- APP_Dedge_BasisSIT_Azure_P
- APP_Dedge_BasisTST_Azure_P
- APP_Dedge_BasisVFK_Azure_P
- APP_Dedge_BasisVFT_Azure_P
- APP_Dedge_Azure_T
- APP_Dedge_Brukerregister_Azure_T
- APP_Dedge_Forhandler_Azure_T
- APP_Dedge_BasisRAP_Azure_T
- APP_Dedge_KIBLog_Azure_P
- APP_Dedge_KTButikk_Azure_P
- APP_Dedge_KTOrdre_Azure_P
- APP_Dedge_RPA_Azure_P
- APP_Dedge_SBTR_Azure_P

### Generell filtilgang
- ACL_Filserver_admins_R
- ACL_Dedge_Servere_Utviklere
- ACL_Dedge_Utviklere
- ACL_Dedge_Utviklere_Modernisering

### Netprog-/Optima
- ACL_Netprog_optimering_RW

### Prosjektspesifikk tilgang
- ACL_Felles_Forsprang_RW
- ACL_Felles_Forsparng_Fase1dokumentasjon_DPTeknisk_CutOffDedge

### Programvare (SCCM Grupper)
- SCCM_USER_Cisco_AnyConnect_Client
- SCCM_USER_DBeaver
- SCCM_USER_IBM_DB2_Client_x64
- SCCM_USER_IBM_DIV
- SCCM_USER_Irfanview
- SCCM_USER_ServiceManager
- SCCM_USER_Teamviewer_Master
- SCCM_USER_Trio_Enterprise