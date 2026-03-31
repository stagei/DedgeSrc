-- Juli 2005
-- Disse ordrene forsvant i forb. m/oppretting av partinr.
-- Var ikke ovf. til BASISHST tidl. og ble slettet fra dbm.h_ordre.....
-- Hentes inn fra BASISRAP
--
  EXPORT TO K:\FKAVD\BASISHST\ORDREHFX1.IXF OF IXF
       SELECT INT(H.TILFAKTDATO/10000), H.*
       FROM DBM.ORDREHODE H
where (
     (h.avdnr = 2005 and h.ordrenr in (
          556320,
          556335,
          556381))
or (h.avdnr = 2500 and h.ordrenr in (
          482559,
          482601,
          543573,
          556349))
   ) ;
  EXPORT TO K:\FKAVD\BASISHST\ORDRELFX1.IXF OF IXF
      SELECT INT(H.TILFAKTDATO/10000), L.*
      FROM DBM.ORDREHODE H, DBM.ORDRELINJER L
      WHERE H.AVDNR = L.AVDNR
        AND H.ORDRENR = L.ORDRENR
and   (
     (h.avdnr = 2005 and h.ordrenr in (
          556320,
          556335,
          556381))
or (h.avdnr = 2500 and h.ordrenr in (
          482559,
          482601,
          543573,
          556349))
   ) ;
  EXPORT TO K:\FKAVD\BASISHST\ORDREMfx1.IXF OF IXF
      SELECT INT(H.TILFAKTDATO/10000), M.*
      FROM DBM.ORDREHODE H, DBM.ORDREMERKNAD M
      WHERE H.AVDNR = M.AVDNR
        AND H.ORDRENR = M.ORDRENR
and   (
     (h.avdnr = 2005 and h.ordrenr in (
          556320,
          556335,
          556381))
or (h.avdnr = 2500 and h.ordrenr in (
          482559,
          482601,
          543573,
          556349))
   ) ;
