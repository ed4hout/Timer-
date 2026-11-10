# Ed’s Tabata – iPhone-app

Een echte iPhone-app voor je tabata-timer en je Briloner LED-bord (Action).

**Wat de app beter doet dan de webversie**
- De piepjes klinken **over Spotify heen**: de muziek blijft spelen, ook via je Bluetooth-box.
- Werkt ook met de **stilschakelaar** aan.
- Blijft lopen en piepen als je **scherm uit** staat of je een andere app opent.
- Verbindt automatisch opnieuw met je bord.

## Installeren (eenmalig, ±10 minuten)

Je hebt nodig: je Mac, je iPhone met kabel, en je Apple ID.

1. **Xcode installeren**: open de App Store op je Mac, zoek *Xcode* en installeer het (gratis, groot bestand).
2. **Project downloaden**: ga naar github.com/ed4hout/Timer- → groene knop **Code** → **Download ZIP**. Pak het zip-bestand uit.
3. Open in de map `ios` het bestand **`EdsTabata.xcodeproj`** (dubbelklikken).
4. **Apple ID toevoegen**: Xcode → Settings → Accounts → **+** → Apple ID → log in.
5. Klik links bovenaan op **EdsTabata** (blauw icoon) → tabblad **Signing & Capabilities** → kies bij **Team** je naam (*Personal Team*).
   - Krijg je een melding over de *Bundle Identifier*? Verander `nl.ed4hout.edstabata` in iets unieks, bijv. `nl.ed4hout.edstabata2`.
6. **iPhone aansluiten** met de kabel en ontgrendelen. Tik op *Vertrouw* als dat gevraagd wordt.
7. **Ontwikkelaarsmodus aanzetten** op je iPhone: Instellingen → Privacy en beveiliging → **Ontwikkelaarsmodus** → aan → iPhone herstart.
8. Kies bovenaan in Xcode je **iPhone** als bestemming en druk op **▶︎ (Run)**.
9. De eerste keer: op je iPhone naar Instellingen → Algemeen → **VPN en apparaatbeheer** → je Apple ID → **Vertrouw**. Daarna nog eens op ▶︎ drukken.
10. Sta **Bluetooth** toe als de app daarom vraagt. Klaar!

> Met een gratis Apple ID blijft de app **7 dagen** werken. Daarna sluit je je iPhone aan en druk je opnieuw op ▶︎ in Xcode. Met een betaald ontwikkelaarsaccount (€99/jaar) blijft hij gewoon staan.

## Gebruik

- **Timer**: start/pauze, reset en overslaan. De ring, rondes en het bord tonen live waar je bent.
- **Schema**: stel tijden in (per 5 seconden), sla trainingen op met **＋**, en klap **Teksten & kleuren** open om per fase je eigen tekst en kleur te kiezen.
- **Bord**: verbinden, helderheid, sportplaatjes, eigen bericht, draaien en **geluid** (per moment een geluid kiezen, volume, en *Muziek zachter tijdens training*).

Problemen? Stuur een screenshot van de foutmelding in Xcode, dan los ik het op.
