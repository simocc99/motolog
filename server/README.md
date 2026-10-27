# Server del gruppo MotoLog

Serve per vedere sulla mappa dell'app dove sono gli altri della tua comitiva e
ricevere un avviso se qualcuno resta indietro. Non c'è nessun account: chi entra
con lo stesso **codice** è nello stesso gruppo.

## Avvio (PC Windows, Mac o Linux con Node.js)

```
node server.js
```

Nessuna installazione di pacchetti. Porta predefinita 8787 (`PORT=9000 node server.js` per cambiarla).

## Come raggiungerlo dal telefono

- **In casa (stessa Wi-Fi):** `ws://IP-DEL-PC:8787`
- **In giro (consigliato):** installa Tailscale sul PC e sui telefoni e usa
  `ws://NOME-PC.tailnet:8787`. La connessione resta privata.
- **Su Internet aperto:** metti il server dietro un proxy HTTPS e usa `wss://`.
  Senza password il codice è l'unica protezione: scegline uno lungo.

Nell'app: Garage › Gruppo, scrivi l'indirizzo del server, il tuo nome e il codice.

## Cosa viaggia

Ogni 4-5 secondi l'app invia nome, posizione e velocità. Il server non salva nulla su disco:
la posizione resta in memoria fino a 2 minuti dopo l'ultimo invio.
