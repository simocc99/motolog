# MotoLog 🏍️

App iOS (SwiftUI, iOS 17+) per registrare e analizzare i giri in moto.

## Funzionalità
- **Registrazione live**: velocità, distanza, tempo, media, massima, quota, dislivello, in background e a schermo bloccato
- **Cruscotto** scuro con indicatore di **angolo di piega** (sinistra/destra) e **forze G**
- **Mappa live** con traccia del percorso
- **Dettaglio giro**: percorso colorato per velocità, grafici (velocità, quota, piega, G), replay con slider, valutazione a stelle, note, scelta moto
- **Export GPX** di ogni giro e backup JSON di tutti i dati
- **Statistiche** per settimana/mese/anno/sempre, grafici km, record personali, ripartizione per moto
- **Traguardi** (17 badge)
- **Garage**: più moto, contachilometri automatico, manutenzione a chilometri con promemoria, rifornimenti con consumo L/100km, scadenze (bollo, assicurazione, revisione) con notifiche
- **Annunci vocali** ogni km, **rilevamento caduta** con chiamata al 112, **recupero giro** se l'app si chiude
- Unità metriche/imperiali, schermo sempre acceso

## Build gratuita (senza toccare il tuo Mac)
Ogni push su `main` avvia GitHub Actions (macOS runner gratuito per repo pubbliche):
compila l'app e pubblica `MotoLog-unsigned.ipa` nella release **latest** e come artifact.

Per installarla su iPhone, l'IPA va firmato con il tuo Apple ID (gratis, scade dopo 7 giorni) usando
[Sideloadly](https://sideloadly.io), [AltStore](https://altstore.io) o SideStore.

Il progetto Xcode è generato da `project.yml` con [XcodeGen](https://github.com/yonaskolb/XcodeGen).
