delete
from dbm.kd_kont_ordre k
where 
not exists(select 1 from dbm.ordrehode o
    where k.avdnr = o.avdnr and k.ordrenr = o.ordrenr)
and 
not exists(select 1 from dbm.h_ordrehode h
    where k.avdnr = h.avdnr and k.ordrenr = h.ordrenr)
