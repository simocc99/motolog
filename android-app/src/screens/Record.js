import React, { useEffect, useState, useRef } from 'react';
import { View, Text, ScrollView, Alert, Pressable, StatusBar } from 'react-native';
import { useKeepAwake } from 'expo-keep-awake';
import { subscribe, init, start, pause, stop, dismissBreak, snapshot } from '../tracker';
import { useStored, DEFAULT_SETTINGS } from '../store';
import { fmtDuration, fmtDist, fmtSpeed } from '../geo';
import Gauge from '../Gauge';
import { Tile, Chip, Btn, Row } from '../ui';
import { C, card } from '../theme';

export default function Record() {
  const [t, setT] = useState(snapshot());
  const [settings] = useStored('settings', DEFAULT_SETTINGS);
  const [rides, setRides] = useStored('rides', []);
  const [bikes] = useStored('bikes', []);
  const [bikeIdx, setBikeIdx] = useState(0);
  const [dark, setDark] = useState(false);
  const idle = useRef(null);
  const [denied, setDenied] = useState(false);

  useKeepAwake();
  useEffect(() => {
    init().then((ok) => setDenied(!ok));
    return subscribe(setT);
  }, []);

  const recording = t.status !== 'idle';
  const miles = settings.miles;

  // Risparmio batteria: schermo nero dopo 25 s di inattività mentre registri.
  const wake = () => {
    setDark(false);
    clearTimeout(idle.current);
    if (settings.saver && recording) idle.current = setTimeout(() => setDark(true), 25000);
  };
  useEffect(() => {
    wake();
    return () => clearTimeout(idle.current);
  }, [recording, settings.saver]);

  const bike = bikes[bikeIdx] || null;

  const finish = () =>
    Alert.alert('Concludere il giro?', undefined, [
      { text: 'Continua', style: 'cancel' },
      {
        text: 'Termina',
        style: 'destructive',
        onPress: async () => {
          const ride = await stop(bike?.id);
          if (ride) setRides((r) => [ride, ...r]);
          else Alert.alert('Giro troppo corto', 'Non l’ho salvato.');
        },
      },
    ]);

  const battery = t.battery != null && t.battery >= 0 ? Math.round(t.battery * 100) : null;
  const gps = t.accuracy == null ? ['GPS…', C.dim] : t.accuracy < 15 ? ['GPS OTTIMO', C.green] : t.accuracy < 40 ? ['GPS OK', C.accent] : ['GPS DEBOLE', C.red];

  return (
    <View style={{ flex: 1 }}>
      <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 30, alignItems: 'center' }} onTouchStart={wake}>
        <Row style={{ alignSelf: 'stretch', justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <Chip text={recording ? (t.status === 'paused' ? 'IN PAUSA' : 'REGISTRO') : 'PRONTO'} color={recording ? C.accent2 : C.green} />
          <Pressable onPress={() => !recording && bikes.length > 1 && setBikeIdx((bikeIdx + 1) % bikes.length)}>
            <Chip text={bike ? `${bike.name}` : 'Nessuna moto'} color={C.accent} />
          </Pressable>
          <Chip text={gps[0]} color={gps[1]} />
        </Row>
        {denied && <Text style={{ color: C.red, marginBottom: 8 }}>Serve il permesso di posizione per usare l’app.</Text>}

        <Gauge value={fmtSpeed(t.speed, miles)} unit={miles ? 'MPH' : 'KM/H'} miles={miles} />
        {t.overLimit && <Chip text={`OLTRE IL LIMITE ${settings.speedLimit}`} color={C.red} />}
        {t.breakDue && (
          <Pressable onPress={dismissBreak} style={{ marginTop: 8 }}>
            <Chip text="FAI UNA PAUSA · tocca per ignorare" color={C.accent} />
          </Pressable>
        )}

        <Row style={{ alignSelf: 'stretch', marginTop: 14 }}>
          <View style={[card, { flex: 2, alignItems: 'center' }]}>
            <Text style={{ color: C.dim, fontSize: 11, fontWeight: '700', letterSpacing: 1 }}>PIEGA</Text>
            <Text style={{ color: C.text, fontSize: 40, fontWeight: '800' }}>{Math.round(Math.abs(t.lean))}°</Text>
            <Text style={{ color: C.dim }}>
              ← {Math.round(t.leanLeft)}°    {Math.round(t.leanRight)}° →
            </Text>
          </View>
          <View style={[card, { flex: 1 }]}>
            <Text style={{ color: C.dim, fontSize: 11, fontWeight: '700', letterSpacing: 1 }}>FORZA G</Text>
            <Text style={{ color: C.text, fontSize: 28, fontWeight: '800' }}>{t.g.toFixed(1)}</Text>
            <Text style={{ color: C.dim, fontSize: 11 }}>MAX</Text>
            <Text style={{ color: C.accent, fontSize: 20, fontWeight: '800' }}>{t.gMax.toFixed(1)}</Text>
          </View>
        </Row>

        <Row style={{ alignSelf: 'stretch' }}>
          <Tile title="DISTANZA" value={fmtDist(t.distance, miles)} unit={miles ? 'mi' : 'km'} />
          <Tile title="TEMPO" value={fmtDuration(t.elapsed)} />
          <Tile title="MEDIA" value={t.elapsed > 0 ? fmtSpeed(t.distance / t.elapsed, miles) : 0} unit={miles ? 'mph' : 'km/h'} />
        </Row>
        <Row style={{ alignSelf: 'stretch' }}>
          <Tile title="MAX" value={fmtSpeed(t.max, miles)} unit={miles ? 'mph' : 'km/h'} />
          <Tile title="SALITA" value={Math.round(t.ascent)} unit="m" />
          <Tile title="BATTERIA" value={battery ?? '—'} unit="%" color={battery != null && battery < 20 ? C.red : C.text} />
        </Row>

        {!recording ? (
          <Btn filled label="INIZIA GIRO" onPress={start} style={{ alignSelf: 'stretch', marginTop: 8, paddingVertical: 18 }} />
        ) : (
          <Row style={{ alignSelf: 'stretch', marginTop: 8 }}>
            <Btn label={t.status === 'paused' ? 'RIPRENDI' : 'PAUSA'} onPress={pause} style={{ flex: 1 }} />
            <Btn filled color={C.accent2} label="FINE" onPress={finish} style={{ flex: 1 }} />
          </Row>
        )}
      </ScrollView>

      {dark && recording && (
        <Pressable
          onPress={wake}
          style={{ position: 'absolute', top: 0, bottom: 0, left: 0, right: 0, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' }}
        >
          <Text style={{ color: '#ffffff55', fontSize: 64, fontWeight: '800' }}>{fmtSpeed(t.speed, miles)}</Text>
          <Text style={{ color: '#ffffff33' }}>{miles ? 'mph' : 'km/h'} · tocca per riattivare</Text>
        </Pressable>
      )}
    </View>
  );
}
