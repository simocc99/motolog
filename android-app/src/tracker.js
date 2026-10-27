import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import { DeviceMotion } from 'expo-sensors';
import * as Battery from 'expo-battery';
import * as Speech from 'expo-speech';
import { haversine } from './geo';
import { get, save, DEFAULT_SETTINGS } from './store';

const TASK = 'motolog-location';

const initial = () => ({
  status: 'idle', // idle | recording | paused
  startedAt: 0,
  elapsed: 0,
  distance: 0,
  speed: 0,
  max: 0,
  ascent: 0,
  altitude: null,
  lean: 0,
  leanLeft: 0,
  leanRight: 0,
  g: 0,
  gMax: 0,
  loc: null,
  accuracy: null,
  points: [],
  battery: null,
  batteryStart: null,
  overLimit: false,
  breakDue: false,
});

let s = initial();
const listeners = new Set();
let timer = null;
let lastTs = 0;
let lastPoint = 0;
let lastAlt = null;
let settings = DEFAULT_SETTINGS;
let watcher = null;
let motionSub = null;
let lastLimitSpoken = 0;
let breakAt = 0;

function emit() {
  listeners.forEach((f) => f({ ...s }));
}

export function subscribe(f) {
  listeners.add(f);
  f({ ...s });
  return () => listeners.delete(f);
}

export function snapshot() {
  return { ...s };
}

function say(text) {
  if (!settings.voice) return;
  Speech.speak(text, { language: 'it-IT' });
}

function onLocation(l) {
  if (!l || l.timestamp <= lastTs) return;
  lastTs = l.timestamp;
  const c = l.coords;
  const speed = c.speed != null && c.speed >= 0 ? c.speed : 0;
  s.loc = { lat: c.latitude, lon: c.longitude };
  s.accuracy = c.accuracy;
  s.speed = speed < 0.7 ? 0 : speed;
  s.altitude = c.altitude;

  if (s.status === 'recording') {
    const prev = s.points[s.points.length - 1];
    if (prev && c.accuracy != null && c.accuracy < 35 && speed > 0.7) {
      const d = haversine(prev, s.loc);
      if (d < 500) s.distance += d;
    }
    if (c.altitude != null && c.accuracy != null && c.accuracy < 30) {
      if (lastAlt != null && c.altitude - lastAlt > 1) s.ascent += c.altitude - lastAlt;
      if (lastAlt == null || Math.abs(c.altitude - lastAlt) > 1) lastAlt = c.altitude;
    }
    s.max = Math.max(s.max, s.speed);
    if (l.timestamp - lastPoint >= 3000) {
      lastPoint = l.timestamp;
      s.points.push({ lat: s.loc.lat, lon: s.loc.lon, speed: s.speed, lean: s.lean, time: l.timestamp });
    }
    const limit = settings.speedLimit / 3.6;
    const over = settings.speedAlert && s.speed > limit;
    if (over && !s.overLimit && Date.now() - lastLimitSpoken > 30000) {
      lastLimitSpoken = Date.now();
      say('Attenzione, stai superando il limite di velocità.');
    }
    s.overLimit = over;
  }
  emit();
}

TaskManager.defineTask(TASK, ({ data, error }) => {
  if (error || !data) return;
  (data.locations || []).forEach(onLocation);
});

let inited = false;
export async function init() {
  if (inited) return true;
  settings = { ...DEFAULT_SETTINGS, ...(await get('settings', DEFAULT_SETTINGS)) };
  const perm = await Location.requestForegroundPermissionsAsync();
  if (perm.status !== 'granted') return false;
  inited = true;
  if (!watcher) {
    watcher = await Location.watchPositionAsync(
      { accuracy: Location.Accuracy.High, timeInterval: 1000, distanceInterval: 0 },
      onLocation
    );
  }
  try {
    const lvl = await Battery.getBatteryLevelAsync();
    s.battery = lvl;
    Battery.addBatteryLevelListener(({ batteryLevel }) => {
      s.battery = batteryLevel;
      emit();
    });
  } catch {}
  emit();
  return true;
}

export function applySettings(next) {
  settings = { ...DEFAULT_SETTINGS, ...next };
}

function startMotion() {
  if (motionSub) return;
  DeviceMotion.setUpdateInterval(settings.saver ? 250 : 100);
  let n = 0;
  motionSub = DeviceMotion.addListener((m) => {
    if (s.status !== 'recording') return;
    const roll = m.rotation ? (m.rotation.gamma * 180) / Math.PI : 0;
    const a = m.accelerationIncludingGravity || { x: 0, y: 0, z: 0 };
    const g = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) / 9.81;
    s.lean = Math.max(-70, Math.min(70, roll));
    s.leanLeft = Math.max(s.leanLeft, -Math.min(0, s.lean));
    s.leanRight = Math.max(s.leanRight, Math.max(0, s.lean));
    s.g = Math.abs(g - 1);
    s.gMax = Math.max(s.gMax, s.g);
    // aggiorno la UI al massimo 4 volte al secondo
    if (++n % (settings.saver ? 1 : 3) === 0) emit();
  });
}

function stopMotion() {
  motionSub?.remove();
  motionSub = null;
}

export async function start() {
  s = { ...initial(), battery: s.battery, loc: s.loc, accuracy: s.accuracy, status: 'recording', startedAt: Date.now() };
  s.batteryStart = s.battery;
  lastPoint = 0;
  lastAlt = null;
  breakAt = Date.now() + settings.breakHours * 3600 * 1000;
  try {
    const bg = await Location.requestBackgroundPermissionsAsync();
    if (bg.status === 'granted') {
      await Location.startLocationUpdatesAsync(TASK, {
        accuracy: Location.Accuracy.High,
        timeInterval: 1000,
        distanceInterval: 3,
        showsBackgroundLocationIndicator: true,
        foregroundService: {
          notificationTitle: 'MotoLog sta registrando il giro',
          notificationBody: 'Tocca per tornare all’app',
          notificationColor: '#ff8a1f',
        },
      });
    }
  } catch {}
  startMotion();
  timer = setInterval(() => {
    if (s.status === 'recording') {
      s.elapsed += 1;
      if (!s.breakDue && settings.breakHours > 0 && Date.now() >= breakAt) {
        s.breakDue = true;
        say('Sei in sella da un po’. Fai una pausa.');
      }
      emit();
      if (s.elapsed % 60 === 0) save('draft', { ...s, points: s.points });
    }
  }, 1000);
  emit();
}

export function pause() {
  if (s.status === 'recording') s.status = 'paused';
  else if (s.status === 'paused') s.status = 'recording';
  emit();
}

export function dismissBreak() {
  s.breakDue = false;
  breakAt = Date.now() + settings.breakHours * 3600 * 1000;
  emit();
}

/** Ferma la registrazione e restituisce il giro (o null se troppo corto). */
export async function stop(bikeId) {
  clearInterval(timer);
  stopMotion();
  try {
    if (await TaskManager.isTaskRegisteredAsync(TASK)) await Location.stopLocationUpdatesAsync(TASK);
  } catch {}
  const ride =
    s.elapsed >= 10 && s.points.length > 1
      ? {
          id: String(Date.now()),
          bikeId,
          start: s.startedAt,
          elapsed: s.elapsed,
          distance: s.distance,
          max: s.max,
          avg: s.elapsed > 0 ? s.distance / s.elapsed : 0,
          ascent: s.ascent,
          leanLeft: s.leanLeft,
          leanRight: s.leanRight,
          gMax: s.gMax,
          batteryStart: s.batteryStart,
          batteryEnd: s.battery,
          points: s.points,
        }
      : null;
  s = { ...initial(), battery: s.battery, loc: s.loc, accuracy: s.accuracy };
  save('draft', null);
  emit();
  return ride;
}
