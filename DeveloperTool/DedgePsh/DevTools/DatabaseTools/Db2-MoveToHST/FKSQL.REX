/* Kjører SQL-file mot angitt database                           */
/*                                                               */
/* Syntax:  1.           2.         3.                           */
/* FKSQL sql-file database outputfile                            */
/*                                                               */
/* FKSQL K:\FKAVD\SQL\EKS.SQL BASISPRO                           */
/* FKSQL K:\FKAVD\SQL\EKS.SQL BASISPRO MINFILE.LOG               */
/*                                                               */
/* Output legges i FKSQL.userid (der du tar kommandoen fra),     */
/* med mindre du har gitt inn outfputfile som 3. parameter       */
/*---------------------------------------------------------------*/
 if rxFuncquery('SysLoadFuncs') <> 0 then do
    call RxFuncAdd 'SysLoadFuncs', 'RexxUtil', 'SysLoadFuncs'
 end
 call SysLoadFuncs
/*---------------------------------------------------------------*/
returkode = 0
parse arg SQL_FILE database UTFILE
sql_file = strip(sql_file)
/* tester input */
if SQL_FILE = '' | database = '' then do
  say 'Input: sqlfile db outfile-navn'
  say
  say '    sqlfile     - sqlfile etter samme regler som SPUFI (--,//,; osv.)'
  say '    database           '
  say '    outfilenavn - kan utelates'
  l = 'Feil ved kall til FKSQL'
  call skriv_ut
  exit(99)
end
if stream(SQL_FILE, C,'QUERY EXISTS') = '' then do
  l = 'Finner ikke filen ' SQL_FILE
  say l
  call skriv_ut
  exit(98)
  end
else do
  S = linein(SQL_FILE,1)
  if S = '' then do
    l = 'Ikke tilgang til filen' SQL_FILE
    say l
    call skriv_ut
    exit(97)
  end
end
UTFILE   = strip(UTFILE)
/* danner filenavn */
un = ''
un = translate(value('username',,'environment'))
if cn = '' | cn = ' '    then do
   l   = 'Username finnes ikke - benytter XXX'
   say l
   call skriv_ut
   un = 'XXX'
end
temp = ''
temp = translate(value('TEMP',,'environment'))
if temp = '' then do
  temp = translate(value('TMP',,'environment'))
end
if temp = '' then temp = 'C:'
sql_fx  = filespec("name",sql_file)
parse var sql_fx sql_fn '.' resten
do ai = 1 to 50
   FKSQLA = temp'\'un'_FKSQL_'ai'.AKT'
   IF stream(FKSQLA, c,'query exists') <> '' THEN DO
     rk = SysFileDelete(FKSQLA)
     if rk = 0 then do
       leave
     end
   end
   else do
     leave
   end
end
CALL LINEOUT FKSQLA,'AKTIV !'
FKSQL1 = temp'\'un'_FKSQL_'ai'.INN' /* preparert inn-file */
FKSQL2 = temp'\'un'_FKSQL_'ai'.UT'  /* output fra 'DB2' */
FKSQLF = temp'\'un'_FKSQL_'ai'.UFF' /* framlest feilmelding */
if utfile <> '' then do
   FKSQLU = utfile                  /* output til user */
   end
else do
   FKSQLU = 'FKSQL.'un
end
RK = SYSFILEDELETE(FKSQLU)

dbase = database
RK = SYSFILEDELETE(FKSQLF)
call dann_sql

rk = sysfiledelete(fksql1)
rk = sysfiledelete(fksql2)
do s = 1 to antsql
  p = pos(';',sqltab.s)
  if p > 0 then do
     CALL LINEOUT FKSQL1,sqltab.s
     say time() sqltab.s
     call stream FKSQL1, c, 'close'
    'DB2' '-z'FKSQL2 '-a -s -c +o -t -v -f'FKSQL1
     call sjekk_resultat
 /*   say 'Kjørt mot' database 'SQLCODE: ' sqlk  */
    if sqlk <> 0 & sqlk <> +100 then 'type' FKSQLf
    returkode = sqlk
    rk = sysfiledelete(fksql1)
    rk = sysfiledelete(fksql2)
    say ' '
    end
  else do
     CALL LINEOUT FKSQL1,sqltab.s
     say time() sqltab.s
  end
end
call slutt
/* **************************************************************************** */
SLUTT:
/* **************************************************************************** */
call stream FKSQLU, c, 'close'
say time()  'Resultat-file:' FKSQLU
call stream FKSQLA, c, 'close'
rk = SysFileDelete(FKSQLA)
exit(returkode)
/* **************************************************************************** */
DANN_SQL:
/* **************************************************************************** */

sqltab. = ''
antsql = 1
sqltab.1 = 'CONNECT TO' dbase ';'
S = linein(SQL_FILE,1)
do until STREAM(SQL_FILE,'S') <> 'READY' | S = ''
  l1 = strip(s)
  IF SUBSTR(l1,1,1) = '-'    THEN do
    S = linein(SQL_FILE)
    iterate
  end
  IF SUBSTR(l1,1,1) = '/'    THEN do
    leave
  end
  antsql = antsql + 1
  sqltab.antsql = strip(S,trailing)
  p = pos(';',l1)
  S = linein(SQL_FILE)
END
if p = 0 then do
  antsql = antsql + 1
  sqltab.antsql = ';'
end
antsql = antsql + 1
sqltab.antsql = 'CONNECT RESET;'
call stream SQL_FILE, c, 'close'

RETURN(0)


/* **************************************************************************** */
SJEKK_RESULTAT:
/* **************************************************************************** */
moddir = ' '
modind = ' '
sqlkode = 0
SQL1 = ' '
d = 0
N = LINEIN(FKSQL1,1,1)
n = ''
L = LINEIN(FKSQL2,1,1)
sqlk = 0
PARSE UPPER VAR L SQL1 SQLRESTEN
do UNTIL STREAM(FKSQL2,'S') <> 'READY'
  IF (SUBSTR(L,1,17) = 'SQLCA Information' | SUBSTR(L,1,17) = 'SQLCA-opplysninge') THEN DO
    DO UNTIL STREAM(FKSQL2,'S') <> 'READY'
      LS = substr(L,11,70)
      parse var LS x1 x2 x3 x4 x5 x6 x7 x8
      IF SUBSTR(L,2,9) = 'sqlcaid :' THEN DO
        sqlkode = strip(x5)
        if sqlkode <> 0 & sqlkode <> 100 then do
          d = 1
          sqlk = sqlkode
        end
      END
      IF SUBSTR(L,2,13) = 'sqlerrd : (1)' THEN DO
        moddir  = x6
      END
      IF SUBSTR(L,2,13) = '          (4)' THEN DO
        modind  = x4
      END
      IF SUBSTR(L,2,9) = 'sqlstate:' THEN DO
        IF SQL1 = 'CALL' & sqlkode = 810 THEN DO
           /* får sqlcode 810 av og til, selv om alt synes OK ved CALL til stored proc */
           sqlkode = 0
           sqlk    = 0
           d = 0
        END
        state = x1
        if d = 0 then do
          lin = '***** SQLCODE:' sqlkode '*****'
          CALL LINEOUT FKSQLU,lin
          say time() lin
          end
        else do
          call skriv_ut
          SAY time() '** FEIL OPPDAGET, LESER FRAM FEILMELDING'
          'DB2 +o -z'FKSQLF '?' state
          F = LINEIN(FKSQLF,1,1)
          DO UNTIL STREAM(FKSQLF,'S') <> 'READY'
            CALL LINEOUT FKSQLU,f
            say time() f
            F = LINEIN(FKSQLF)
          END
        END
        IF SQL1 = 'INSERT' | SQL1 = 'DELETE' | SQL1 = 'UPDATE' THEN DO
            lin = 'Antall rader direkte berørt         :' moddir
            CALL LINEOUT FKSQLU,lin
            say time() lin
            lin = 'Antall rader berørt pga. relasjoner :' modind
            CALL LINEOUT FKSQLU,lin
            say time() lin
        END
        L = LINEIN(FKSQL2)
        DO UNTIL STREAM(FKSQL2,'S') <> 'READY'
          if l = ' ' then do
            L = LINEIN(FKSQL2)
            iterate
          end
          PARSE UPPER VAR L SQL1 SQLRESTEN
          moddir = ' '
          modind = ' '
          sqlkode = 0
          D = 0
          L = LINEIN(FKSQL2)
          lin = '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - '
          CALL LINEOUT FKSQLU,lin
          say time() lin
          /* Leser fram original SQL */
          if n = '' then do
            N = LINEIN(FKSQL1)
          end
          DO UNTIL STREAM(FKSQL1,'S') <> 'READY'
            CALL LINEOUT FKSQLU,n
            if  pos(';',N) > 0 then do
              n = ''
              leave
              end
            else do
              N = LINEIN(FKSQL1)
            end
          END
          leave
        end
        CALL LINEOUT FKSQLU,' '
        leave
      END
      IF D = 1 THEN DO
        call skriv_ut
      END
      L = LINEIN(FKSQL2)
    END
  END
  call skriv_ut
  L = LINEIN(FKSQL2)
END
call stream FKSQL1, c, 'close'
call stream FKSQL2, c, 'close'
call stream FKSQLF, c, 'close'
return(0)

RETURN(0)
/* --------------------------------------------------------------- */
SKRIV_UT:
/* --------------------------------------------------------------- */
  CALL LINEOUT FKSQLU,L
  return
