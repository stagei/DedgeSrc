# Melding til administrator — Lillestrøm Osteopati

Hei,

Vi holder på å sette opp en ny nettside for Lillestrøm Osteopati som skal erstatte den eksisterende WordPress-siden på lillestrom-osteopati.no.

For å kunne gjennomføre dette trenger vi følgende informasjon fra Domeneshop-kontoen:

---

## 1. SFTP-tilgang (for filopplasting)

Vi trenger påloggingsinformasjon for å koble til webhotellet via SFTP:

- **SFTP-brukernavn** (finnes under Domeneshop > Webhotell-fanen for domenet)
- **SFTP-passord** (kan tilbakestilles fra samme sted om nødvendig)
- **Server:** sftp.domeneshop.no (dette vet vi allerede)

> Du finner dette ved å logge inn på https://www.domeneshop.no, velge domenet lillestrom-osteopati.no, og gå til **Webhotell**-fanen.

---

## 2. MySQL-database (valgfritt)

Dersom vi ønsker å ta backup av den eksisterende WordPress-databasen før vi fjerner den, trenger vi:

- **Database-navn**
- **Database-brukernavn**
- **Database-passord**

> Finnes under Domeneshop > Webhotell > MySQL > Vis/endre

---

## 3. Domeneshop innlogging (valgfritt)

Alternativt kan du gi oss midlertidig tilgang til selve Domeneshop-kontrollpanelet, så kan vi hente informasjonen selv:

- **Innlogging:** https://www.domeneshop.no
- **E-post/brukernavn:**
- **Passord:**

---

## Hva vi skal gjøre

1. Ta backup av eksisterende WordPress-filer og database
2. Fjerne WordPress-filene fra webhotellet
3. Laste opp den nye statiske nettsiden (HTML/CSS/JS)
4. Verifisere at alt fungerer

Den nye siden er raskere, sikrere og krever ingen vedlikehold (ingen WordPress-oppdateringer, plugins eller databaseavhengigheter).

---

## Kontaktinfo

Har du spørsmål eller trenger hjelp med å finne informasjonen, ta gjerne kontakt.

Med vennlig hilsen,
[Ditt navn]
