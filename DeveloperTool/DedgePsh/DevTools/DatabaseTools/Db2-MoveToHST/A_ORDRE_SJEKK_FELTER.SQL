--Sjekk før export/import at det ikke har kommet til nye kolonner i BASISPRO
--
--   Alle tabeller kal ha ett felt mer i BASISHST (AAR)
--
--
select 'BASISPRO', substr(TABNAME,1,32), count(*) 
 from syscat.columns
--select substr(TABNAME,1,32), substr(COLNAME,1,32) from syscat.columns
where TABSCHEMA = 'DBM'
and TABNAME IN (
'AH_ORDREHODE',
'AH_ORDRELINJER',
'H_VERKSTEDHODE',
'H_VERKSTED_TIMER',
'H_VERKSTEDTEKST')
group by tabname
order by tabname;
connect to basishst;
select 'BASISHST', substr(TABNAME,1,32), count(*) 
 from syscat.columns
--select substr(TABNAME,1,32), substr(COLNAME,1,32) from syscat.columns
where TABSCHEMA = 'DBM'
and TABNAME IN (
'AH_ORDREHODE',
'AH_ORDRELINJER',
'H_VERKSTEDHODE',
'H_VERKSTED_TIMER',
'H_VERKSTEDTEKST')
group by tabname
order by tabname;
//
