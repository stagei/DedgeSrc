--step 1
export to avihode.ixf of ixf
select int(inngdato/10000), h.*
from dbm.a_vihode h
where avdnr = 8039
and inngdato between 20220101 and 20221231
and((ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (b.ordrestatus in('IA') or vinngstatus='VF'))));
--
export to avilin.ixf of ixf
select int(h.inngdato/10000), l.*
from dbm.a_vihode h
, dbm.a_vilin l
where h.avdnr = 8039
and h.inngdato between 20220101 and 20221231
and((h.ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (ordrestatus in('IA') or vinngstatus='VF'))))
and h.avdnr = l.avdnr
and h.inngangnr = l.inngangnr;
//
--select count(*) 
--Step 4
delete
from  dbm.a_vihode h 
where avdnr = 8039
and inngdato between 20220101 and 20221231
and((ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (b.ordrestatus in('IA') or vinngstatus='VF'))));
//
--Step 3
--select count(*) 
delete
from dbm.a_vilin l
where avdnr = 8039
and exists (select 1 from  dbm.a_vihode h
where l.avdnr = h.avdnr
and  l.inngangnr = h.inngangnr
and inngdato between 20220101 and 20220331
and((ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (b.ordrestatus in('IA') or vinngstatus='VF')))));
--//
delete
from dbm.a_vilin l
where avdnr = 8039
and exists (select 1 from  dbm.a_vihode h
where l.avdnr = h.avdnr
and  l.inngangnr = h.inngangnr
and inngdato between 20220401 and 20220631
and((ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (b.ordrestatus in('IA') or vinngstatus='VF')))));
delete
from dbm.a_vilin l
where avdnr = 8039
and exists (select 1 from  dbm.a_vihode h
where l.avdnr = h.avdnr
and  l.inngangnr = h.inngangnr
and inngdato between 20220701 and 20220931
and((ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (b.ordrestatus in('IA') or vinngstatus='VF')))));
delete
from dbm.a_vilin l
where avdnr = 8039
and exists (select 1 from  dbm.a_vihode h
where l.avdnr = h.avdnr
and  l.inngangnr = h.inngangnr
and inngdato between 20221001 and 20221231
and((ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (b.ordrestatus in('IA') or vinngstatus='VF')))));
//
step 2
import from avihode.ixf of ixf insert into
 dbm.ah_vihode;
--
import from avilin.ixf of ixf insert into
 dbm.ah_vilin;
//
import from avihode.ixf of ixf insert into
 dbm.ah_vihode;
import from avilin.ixf of ixf insert into
 dbm.ah_vilin;
//
//
