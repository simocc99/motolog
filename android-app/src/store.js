import { useEffect, useState, useCallback } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

const cache = {};
const subs = {};

async function load(key, fallback) {
  if (key in cache) return cache[key];
  try {
    const raw = await AsyncStorage.getItem(key);
    cache[key] = raw ? JSON.parse(raw) : fallback;
  } catch {
    cache[key] = fallback;
  }
  return cache[key];
}

export function save(key, value) {
  cache[key] = value;
  AsyncStorage.setItem(key, JSON.stringify(value)).catch(() => {});
  (subs[key] || []).forEach((f) => f(value));
}

export function get(key, fallback) {
  return load(key, fallback);
}

/** Come useState, ma salvato sul telefono e condiviso fra le schermate. */
export function useStored(key, fallback) {
  const [value, setValue] = useState(key in cache ? cache[key] : fallback);
  useEffect(() => {
    let alive = true;
    load(key, fallback).then((v) => alive && setValue(v));
    const f = (v) => alive && setValue(v);
    (subs[key] = subs[key] || []).push(f);
    return () => {
      alive = false;
      subs[key] = subs[key].filter((x) => x !== f);
    };
  }, [key]);
  const set = useCallback(
    (v) => save(key, typeof v === 'function' ? v(cache[key] ?? fallback) : v),
    [key]
  );
  return [value, set];
}

export const DEFAULT_SETTINGS = {
  miles: false,
  saver: true,
  speedAlert: true,
  speedLimit: 130,
  voice: true,
  breakHours: 2,
};
