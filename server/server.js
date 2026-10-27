// Server del gruppo MotoLog: nessuna dipendenza, basta `node server.js`.
// Ogni "stanza" è un codice: chi entra con lo stesso codice vede gli altri sulla mappa.
// Non c'è cifratura né password oltre al codice: per uso su Internet mettilo dietro
// una VPN (es. Tailscale) o un proxy HTTPS (wss://).
const http = require('http');
const crypto = require('crypto');

const PORT = process.env.PORT || 8787;
const MAX_PER_ROOM = 20;
const STALE_MS = 120000;
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

const rooms = new Map(); // codice -> Set di client

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('MotoLog group server: ' + rooms.size + ' gruppi attivi\n');
});

server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) return socket.destroy();
  const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
  socket.write(['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade',
    'Sec-WebSocket-Accept: ' + accept, '', ''].join('\r\n'));
  const client = { socket, room: null, info: null, buf: Buffer.alloc(0) };
  socket.on('data', (d) => { client.buf = Buffer.concat([client.buf, d]); readFrames(client); });
  socket.on('close', () => leave(client));
  socket.on('error', () => { leave(client); socket.destroy(); });
});

function readFrames(client) {
  for (;;) {
    const b = client.buf;
    if (b.length < 2) return;
    const opcode = b[0] & 0x0f, masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f, off = 2;
    if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
    else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
    if (len > 4096) { client.socket.destroy(); return; }
    const need = off + (masked ? 4 : 0) + len;
    if (b.length < need) return;
    let payload = b.subarray(off + (masked ? 4 : 0), need);
    if (masked) { const m = b.subarray(off, off + 4); payload = Buffer.from(payload.map((x, i) => x ^ m[i % 4])); }
    client.buf = b.subarray(need);
    if (opcode === 8) { client.socket.end(); return; }
    if (opcode === 9) { frame(client, 0x8a, payload); continue; }       // ping -> pong
    if (opcode === 1) handle(client, payload.toString('utf8'));
  }
}

function frame(client, first, payload) {
  let header;
  if (payload.length < 126) header = Buffer.from([first, payload.length]);
  else { header = Buffer.alloc(4); header[0] = first; header[1] = 126; header.writeUInt16BE(payload.length, 2); }
  if (!client.socket.destroyed) client.socket.write(Buffer.concat([header, payload]));
}
const send = (client, obj) => frame(client, 0x81, Buffer.from(JSON.stringify(obj)));

function handle(client, text) {
  let m; try { m = JSON.parse(text); } catch { return; }
  if (m.type === 'join') {
    leave(client);
    const code = String(m.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
    if (!code) return;
    const room = rooms.get(code) || new Set();
    if (room.size >= MAX_PER_ROOM) return send(client, { type: 'error', message: 'Gruppo pieno' });
    rooms.set(code, room);
    room.add(client);
    client.room = code;
    client.info = { id: String(m.id || '').slice(0, 40), name: String(m.name || 'Pilota').slice(0, 20), lat: null, lon: null, speed: 0, ts: Date.now() };
    send(client, { type: 'joined', code });
  } else if (m.type === 'pos' && client.info) {
    if (Number.isFinite(m.lat) && Number.isFinite(m.lon)) {
      Object.assign(client.info, { lat: m.lat, lon: m.lon, speed: Number(m.speed) || 0, ts: Date.now() });
    }
  } else if (m.type === 'leave') {
    leave(client);
  }
}

function leave(client) {
  if (!client.room) return;
  const room = rooms.get(client.room);
  if (room) { room.delete(client); if (room.size === 0) rooms.delete(client.room); }
  client.room = null;
}

// Ogni 2 secondi ognuno riceve la lista aggiornata del proprio gruppo.
setInterval(() => {
  const now = Date.now();
  for (const room of rooms.values()) {
    const riders = [...room].filter((c) => c.info && c.info.lat !== null && now - c.info.ts < STALE_MS)
      .map((c) => ({ id: c.info.id, name: c.info.name, lat: c.info.lat, lon: c.info.lon, speed: c.info.speed, age: Math.round((now - c.info.ts) / 1000) }));
    for (const c of room) send(c, { type: 'roster', riders });
  }
}, 2000);

server.listen(PORT, () => console.log('MotoLog group server in ascolto sulla porta ' + PORT));
