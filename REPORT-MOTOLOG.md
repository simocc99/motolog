# MotoLog – report della notte (28 ottobre 2026)

## Novità iOS
- **Gruppo**: scheda in Garage → *Gruppo*. Mappa con tutti i piloti, distanza da te, velocità, e avviso
  **"rimasto indietro"** (chip rosso, banner nella schermata Registra e voce) se un pilota è oltre la soglia
  scelta (default 500 m dal compagno più vicino, regolabile 200 m–3 km).
  - Con server: `node server/server.js` su un PC (nessuna dipendenza), stesso codice e indirizzo per tutti.
  - Senza server: *Prova con piloti simulati* (tre piloti finti, uno resta indietro) e *Condividi dove sono* (link Apple Maps).
- **Sicurezza**: promemoria pausa ogni N ore (default 2), avviso se superi il limite impostato, e dopo una caduta
  il pulsante **"Avvisa il contatto"** prepara l'SMS col tuo punto.
- **Controllo prima di partire**, **parcheggio** ("dove ho lasciato la moto"), **tramonto** (avviso fari), **analisi del giro**.

## Batteria
- GPS a bassa precisione quando sei fermo o l'app non registra, si ferma se esci dall'app senza registrare.
- Sensori di movimento a 5 Hz (4 Hz in risparmio), interfaccia aggiornata max 4 volte/s.
- **Risparmio batteria**: dopo 25 s senza toccare, schermo nero (OLED = quasi zero consumo) con la velocità in grigio.
- Navigatore a 12 fps in risparmio, 30 normale. Chip con % e ore residue; ogni giro salva la batteria usata.
- Gruppo: invio posizione ogni 5 s (10 s sotto il 20% di batteria), riconnessione con attesa crescente.

## Android (nuovo)
App React Native/Expo in `android-app/`, stessa grafica e funzioni: tachimetro 300 km/h, piega e G, giri con mappa
e GPX, statistiche (con costo benzina e consumo), garage con serbatoio e autonomia, gruppo con demo, risparmio batteria.
APK costruito da GitHub Actions (release `latest-android`).

## Cosa ho verificato e cosa NO
- Verificato nel simulatore iPhone: Garage, card Gruppo, demo con 3 piloti sulla mappa e lista, build iOS su GitHub OK.
- Server Node testato con due client simulati nella stessa stanza.
- **NON verificato su un telefono vero**: GPS, piega/G, registrazione a schermo spento, voce, vibrazioni, SMS,
  notifiche, fluidità reale del navigatore, consumo di batteria reale (i numeri sopra sono le tecniche applicate, non misure).
- **Android**: la build su GitHub è riuscita (APK nella release `latest-android`), ma l'app non l'ho mai avviata su un dispositivo o emulatore Android: potrebbero esserci errori a runtime.

## Decisioni per te
1. **Server del gruppo**: per usarlo fuori casa serve un PC/VPS raggiungibile (consiglio Tailscale o un `wss://`).
   Non uso nessun servizio esterno senza il tuo ok.
2. **CarPlay**: serve un entitlement Apple (account sviluppatore a pagamento) e romperebbe l'installazione gratuita.
   Dettagli in `CARPLAY.md`. Dimmi se vuoi procedere.
3. **Chat vocale di gruppo**: richiede streaming audio (WebRTC) e un server dedicato; per ora ho fatto le posizioni.

## Stato build e release (28 ottobre, ore 6:00)
- **iOS**: ultime build GitHub Actions riuscite. IPA non firmata nella release `latest` (installa con Sideloadly/AltStore/SideStore).
- **Android**: la prima build era fallita (mancava `expo-asset`), corretta: ultima build riuscita. APK nella release `latest-android`.
  Abilita "origini sconosciute" per installarlo. Mai avviata su un dispositivo Android.
- **Non fatto**: statistiche costi benzina su iOS (su Android ci sono), CarPlay, chat vocale.
