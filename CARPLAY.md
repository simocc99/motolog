# CarPlay e MotoLog

**Stato: non incluso nella build attuale, di proposito.**

## Perché
CarPlay richiede un *entitlement* speciale che Apple concede solo su richiesta, e solo per categorie precise
(navigazione, audio, comunicazione, ricarica, parcheggio, ristoranti…). Un'app "tachimetro / registro giri"
non rientra in nessuna categoria standard.
Inoltre l'IPA non firmata che installi con Sideloadly/AltStore/SideStore con un Apple ID gratuito **non può
contenere entitlement a pagamento/ristretti**: aggiungerlo farebbe fallire l'installazione di tutta l'app.

## Cosa si può fare
1. **Navigazione (categoria `com.apple.developer.carplay-maps`)**: il navigatore beta (NavEngine) potrebbe
   comparire su CarPlay. Serve un account Apple Developer a pagamento (99 €/anno) e l'approvazione di Apple.
2. **Senza entitlement**: le moto con "CarPlay" di solito usano lo schermo della moto come uno schermo del
   telefono (Apple Maps, musica). La voce del navigatore di MotoLog e gli avvisi vocali (gruppo, limite,
   pausa) passano già dall'audio del telefono, quindi arrivano nel casco/impianto Bluetooth.
3. **Schermo sempre acceso a basso consumo**: la modalità risparmio batteria è pensata per il telefono sul manubrio.

## Se vuoi procedere
Dimmi se hai (o vuoi prendere) l'account sviluppatore: allora aggiungo il target CarPlay in un ramo separato
così la build gratuita non si rompe.
