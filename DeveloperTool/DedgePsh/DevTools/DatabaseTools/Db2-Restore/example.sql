    -- *****************************************************************************

-- ** automatisk opprettet omdiriger-gjenopprettingsskript

-- *****************************************************************************

UPDATE COMMAND OPTIONS USING S ON Z ON INLDEV_NODE0000.out V ON;

SET CLIENT ATTACH_MEMBER  0;

SET CLIENT CONNECT_MEMBER 0;

-- *****************************************************************************

-- ** automatisk opprettet omdiriger-gjenopprettingsskript

-- *****************************************************************************

RESTORE DATABASE INLDEV

-- USER  <bruker-ID

-- USING '<passord>'

FROM 'E:\DbRestore'

TAKEN AT 20250714151333

-- ON 'E:'

DBPATH ON 'E:'

INTO INLDEV

-- NEWLOGPATH DEFAULT

-- WITH <ant-buff> BUFFERS

BUFFER 2050

-- REPLACE HISTORY FILE

REPLACE EXISTING

REDIRECT

PARALLELISM 10

WITHOUT ROLLING FORWARD

WITHOUT PROMPTING

;

-- *****************************************************************************

-- ** lagergruppedefinisjon

-- **   Standard lagergruppe-ID                  = 0

-- **   Antall lagergrupper                      = 1

-- *****************************************************************************

-- *****************************************************************************

-- ** Lagergruppenavn                            = IBMSTOGROUP

-- **   Lagergruppe-ID                           = 0

-- **   Datakode                                 = Ingen

-- *****************************************************************************

-- SET STOGROUP PATHS FOR IBMSTOGROUP

-- ON 'E:'

-- ;

-- *****************************************************************************

-- ** tabellplassdefinisjon

-- *****************************************************************************

-- *****************************************************************************

-- ** Tabellplassnavn                            = SYSCATSPACE

-- **   Tabellplass-ID                       = 0

-- **   Tabellplasstype                          = Databasestyrt plass                      

-- **   Innholdstype for tabellplass             = Alle permanente data. Vanlig tabellplass.    

-- **   Sidest�rrelse for tabellplass (byte)     = 4096

-- **   Omr�dest�rrelse for tabellplass (sider)  = 4

-- **   Bruker automatisk lager                  = Ja     

-- **   Lagergruppe-ID                           = 0

-- **   Kildelagergruppe-ID                      = -1

-- **   Datakode                                 = Ingen

-- **   Automatisk endring av st�rrelse aktivert = Ja     

-- **   Totalt antall sider                      = 32768

-- **   Antall brukbare sider                    = 32764

-- **   St�rste registrerte verdi (sider)    = 32360

-- *****************************************************************************

-- *****************************************************************************

-- ** Tabellplassnavn                            = TEMPSPACE1

-- **   Tabellplass-ID                       = 1

-- **   Tabellplasstype                          = Systemstyrt plass                        

-- **   Innholdstype for tabellplass             = System midlertidig data                       

-- **   Sidest�rrelse for tabellplass (byte)     = 4096

-- **   Omr�dest�rrelse for tabellplass (sider)  = 32

-- **   Bruker automatisk lager                  = Ja     

-- **   Lagergruppe-ID                           = 0

-- **   Kildelagergruppe-ID                      = -1

-- **   Totalt antall sider                      = 1

-- *****************************************************************************

-- *****************************************************************************

-- ** Tabellplassnavn                            = USERSPACE1

-- **   Tabellplass-ID                       = 2

-- **   Tabellplasstype                          = Databasestyrt plass                      

-- **   Innholdstype for tabellplass             = Alle permanente data. Stor tabellplass.      

-- **   Sidest�rrelse for tabellplass (byte)     = 4096

-- **   Omr�dest�rrelse for tabellplass (sider)  = 32

-- **   Bruker automatisk lager                  = Ja     

-- **   Lagergruppe-ID                           = 0

-- **   Kildelagergruppe-ID                      = -1

-- **   Datakode                                 = -1

-- **   Automatisk endring av st�rrelse aktivert = Ja     

-- **   Totalt antall sider                      = 8192

-- **   Antall brukbare sider                    = 8160

-- **   St�rste registrerte verdi (sider)    = 96

-- *****************************************************************************

-- *****************************************************************************

-- ** start omdirigert gjenoppretting

-- *****************************************************************************

RESTORE DATABASE INLDEV CONTINUE;

-- *****************************************************************************

-- ** filslutt

-- *****************************************************************************


 
 