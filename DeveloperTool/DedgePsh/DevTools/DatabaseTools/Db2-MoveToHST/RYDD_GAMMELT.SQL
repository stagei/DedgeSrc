  delete from dbm.ah_ordrelinjer_endr
--SELECT date(TIDSPUNKT),count(*)
--FROM dbm.AH_ORDRELINJER_ENDR e
  WHERE NOT EXISTS (select 1 FROM dbm.AH_ORDRELINJER L
      WHERE e.avdnr = l.AVDNR
      AND e.ordrenr = l.ORDRENR
      AND e.linjenr = l.linjenr)
 AND tidspunkt < '2009-01-01-00.00.00.000000'
 GROUP BY date(tidspunkt)
 ORDER BY date(tidspunkt)
