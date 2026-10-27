import React from 'react';
import { View, Text, ScrollView } from 'react-native';
import { useStored, DEFAULT_SETTINGS } from '../store';
import { fmtDuration, fmtDist, fmtSpeed } from '../geo';
import { Tile, H1, Row } from '../ui';
import { C, card } from '../theme';

export default function Stats() {
  const [rides] = useStored('rides', []);
  const [fuel] = useStored('fuel', []);
  const [settings] = useStored('settings', DEFAULT_SETTINGS);
  const miles = settings.miles;

  const dist = rides.reduce((a, r) => a + r.distance, 0);
  const time = rides.reduce((a, r) => a + r.elapsed, 0);
  const max = rides.reduce((a, r) => Math.max(a, r.max), 0);
  const best = rides.reduce((a, r) => Math.max(a, r.distance), 0);

  // ultime 8 settimane
  const week = 7 * 24 * 3600 * 1000;
  const now = Date.now();
  const bars = Array.from({ length: 8 }, (_, i) => {
    const from = now - (8 - i) * week;
    return rides.filter((r) => r.start >= from && r.start < from + week).reduce((a, r) => a + r.distance, 0);
  });
  const top = Math.max(1, ...bars);

  const spent = fuel.reduce((a, f) => a + (f.cost || 0), 0);
  const liters = fuel.reduce((a, f) => a + f.liters, 0);
  const per100 = dist > 0 && liters > 0 ? (liters / (dist / 1000)) * 100 : null;
  const perKm = dist > 0 && spent > 0 ? spent / (dist / 1000) : null;

  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <H1>Statistiche</H1>
      <Row>
        <Tile title="GIRI" value={rides.length} />
        <Tile title="KM TOTALI" value={fmtDist(dist, miles)} unit={miles ? 'mi' : 'km'} />
      </Row>
      <Row>
        <Tile title="TEMPO IN SELLA" value={fmtDuration(time)} />
        <Tile title="VELOCITÀ MAX" value={fmtSpeed(max, miles)} unit={miles ? 'mph' : 'km/h'} />
      </Row>
      <Row>
        <Tile title="GIRO PIÙ LUNGO" value={fmtDist(best, miles)} unit={miles ? 'mi' : 'km'} />
        <Tile title="SPESA BENZINA" value={spent.toFixed(0)} unit="€" />
      </Row>
      {per100 != null && (
        <Row>
          <Tile title="CONSUMO REALE" value={per100.toFixed(1)} unit="L/100km" />
          {perKm != null && <Tile title="COSTO AL KM" value={perKm.toFixed(2)} unit="€" />}
        </Row>
      )}
      <View style={[card, { marginTop: 4 }]}>
        <Text style={{ color: C.dim, fontSize: 11, fontWeight: '700', letterSpacing: 1, marginBottom: 10 }}>KM PER SETTIMANA (ULTIME 8)</Text>
        <View style={{ flexDirection: 'row', alignItems: 'flex-end', height: 120, gap: 8 }}>
          {bars.map((v, i) => (
            <View key={i} style={{ flex: 1, height: Math.max(4, (v / top) * 110), backgroundColor: i === 7 ? C.accent : '#ff8a1f66', borderRadius: 6 }} />
          ))}
        </View>
      </View>
    </ScrollView>
  );
}
