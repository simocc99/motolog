import * as Speech from 'expo-speech';
import { haversine } from './geo';
import { get, save } from './store';

/** Gruppo di moto: stesso protocollo WebSocket del server in server/server.js. */
let ws = null;
let active = false;
let demo = false;
let connected = false;
let code = '';
let myName = 'Io';
let myId = null;
let url = '';
let me = null;
let remote = [];
let lastSent = 0;
let retry = 0;
let demoTimer = null;
let demoStep = 0;
let gapLimit = 500;
let voice = true;
const announced = {};
const subs = new Set();

function state() {
  const all = remote.filter((r) => r.age < 90);
  if (me) all.push({ id: myId, name: myName, lat: me.lat, lon: me.lon, speed: me.speed || 0, age: 0, isMe: true });
  const behind = [];
  if (all.length > 1) {
    all.forEach((r) => {
      if (r.isMe) return;
      let nearest = Infinity;
      all.forEach((o) => {
        if (o.id !== r.id) nearest = Math.min(nearest, haversine(r, o));
      });
      if (nearest > gapLimit) behind.push({ id: r.id, name: r.name, gap: nearest });
    });
  }
  return { active, demo, connected, code, riders: all, behind, gapLimit, myId };
}

function emit() {
  const st = state();
  subs.forEach((f) => f(st));
  if (voice) {
    st.behind.forEach((b) => {
      if (Date.now() - (announced[b.id] || 0) > 90000) {
        announced[b.id] = Date.now();
        Speech.speak(`${b.name} è rimasto indietro.`, { language: 'it-IT' });
      }
    });
  }
}

export function subscribeGroup(f) {
  subs.add(f);
  f(state());
  return () => subs.delete(f);
}

export async function ensureId() {
  if (!myId) {
    myId = await get('groupId', null);
    if (!myId) {
      myId = String(Date.now()) + Math.random().toString(36).slice(2, 8);
      save('groupId', myId);
    }
  }
  return myId;
}

export function setGapLimit(m) {
  gapLimit = m;
  emit();
}

export function setVoice(v) {
  voice = v;
}

function send(o) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(o));
}

function connect() {
  if (!active || demo) return;
  try {
    ws = new WebSocket(url);
  } catch {
    return;
  }
  const mine = ws;
  ws.onopen = () => {
    connected = true;
    retry = 0;
    send({ type: 'join', code, id: myId, name: myName });
    emit();
  };
  ws.onmessage = (e) => {
    try {
      const m = JSON.parse(e.data);
      if (m.type === 'roster') {
        remote = (m.riders || []).filter((r) => r.id !== myId);
        emit();
      }
    } catch {}
  };
  const lost = () => {
    if (ws !== mine) return;
    connected = false;
    emit();
    if (!active) return;
    retry += 1;
    setTimeout(() => active && !connected && connect(), Math.min(30, 2 ** retry) * 1000);
  };
  ws.onclose = lost;
  ws.onerror = lost;
}

export async function join(server, c, name) {
  await ensureId();
  if (!/^wss?:\/\//.test(server.trim())) return false;
  leave();
  url = server.trim();
  code = c.toUpperCase();
  myName = name || 'Io';
  demo = false;
  active = true;
  connect();
  emit();
  return true;
}

export async function startDemo(name) {
  await ensureId();
  leave();
  code = 'DEMO';
  myName = name || 'Io';
  demo = true;
  active = true;
  connected = true;
  demoStep = 0;
  demoTimer = setInterval(demoTick, 2000);
  emit();
}

export function leave() {
  send({ type: 'leave' });
  try {
    ws?.close();
  } catch {}
  ws = null;
  clearInterval(demoTimer);
  demoTimer = null;
  active = false;
  connected = false;
  demo = false;
  remote = [];
  emit();
}

/** Chiamato a ogni fix GPS: invia al massimo ogni 5 s (10 s con la batteria sotto il 20%). */
export function updateMe(loc, speed, lowBattery) {
  me = { ...loc, speed };
  if (!active) return;
  if (demo) return emit();
  if (!connected || Date.now() - lastSent < (lowBattery ? 10000 : 5000)) return;
  lastSent = Date.now();
  send({ type: 'pos', lat: loc.lat, lon: loc.lon, speed: Math.max(0, speed || 0) });
}

function demoTick() {
  if (!me) return;
  demoStep += 1;
  const at = (n, e) => ({ lat: me.lat + n / 111320, lon: me.lon + e / (111320 * Math.cos((me.lat * Math.PI) / 180)) });
  remote = [
    { id: 'd1', name: 'Marco', ...at(-90, 25), speed: 21, age: 1 },
    { id: 'd2', name: 'Giulia', ...at(260, -30), speed: 24, age: 2 },
    { id: 'd3', name: 'Luca', ...at(-120 - demoStep * 18, 15), speed: 14, age: 1 },
  ];
  emit();
}
