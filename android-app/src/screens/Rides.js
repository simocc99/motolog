import React, { useState } from 'react';
import { View, Text, ScrollView, TouchableOpacity, Alert, Share } from 'react-native';
import { useStored, DEFAULT_SETTINGS } from '../store';
import { fmtDuration, fmtDist, fmtSpeed, dayLabel } from '../geo';
import MapWeb from '../MapWeb';
import { Tile, Btn, H1, Row } from '../ui';
import { C, card } from '../theme';

function gpx(r) {
  const pts = r.points
    .map((p) => `<trkpt lat="${p.lat}" lon="${p.lon}"><time>${new Date(p.time).toISOString()}</time></trkpt>`)
    .join('');
  return `<?xml version="1.0"?><gpx version="1.1" creator="MotoLog"><trk><name>Giro ${dayLabel(r.start)}</name><trkseg>${pts}</trkseg></trk></gpx>`;
}

function Detail({ ride, onBack, onDelete, miles }) {
  const line = ride.points.map((p) => [p.lat, p.lon]);
  const a = ride.points[0];
  const b = ride.points[ride.points.length - 1];
  const pins = [
    { lat: a.lat, lon: a.lon, label: 'A', color: C.green },
    { lat: b.lat, lon: b.lon, label: 'B', color: C.red },
  ];
  const used = ride.batteryStart != null && ride.batteryEnd != null ? Math.round((ride.batteryStart - ride.batteryEnd) * 100) : null;
  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <TouchableOpacity onPress={onBack}>
        <Text style={{ color: C.accent, fontWeight: '700', marginBottom: 8 }}>‹ Giri</Text>
      </TouchableOpacity>
      <H1>{dayLabel(ride.start)}</H1>
      <View style={{ height: 260, borderRadius: 18, overflow: 'hidden', marginBottom: 12 }}>
        <MapWeb line={line} pins={pins} />
      </View>
      <Row>
        <Tile title="DISTANZA" value={fmtDist(ride.distance, miles)} unit={miles ? 'mi' : 'km'} />
        <Tile title="TEMPO" value={fmtDuration(ride.elapsed)} />
      </Row>
      <Row>
        <Tile title="MEDIA" value={fmtSpeed(ride.avg, miles)} unit={miles ? 'mph' : 'km/h'} />
        <Tile title="MAX" value={fmtSpeed(ride.max, miles)} unit={miles ? 'mph' : 'km/h'} />
      </Row>
      <Row>
        <Tile title="PIEGA SX / DX" value={`${Math.round(ride.leanLeft)}° / ${Math.round(ride.leanRight)}°`} />
        <Tile title="SALITA" value={Math.round(ride.ascent)} unit="m" />
      </Row>
      {used != null && used > 0 && (
        <View style={[card, { marginBottom: 10 }]}>
          <Text style={{ color: C.text }}>
            Batteria: {used}% usata
            {ride.elapsed > 360 ? ` · ${(used / (ride.elapsed / 3600)).toFixed(1)}% all’ora` : ''}
          </Text>
        </View>
      )}
      <Row>
        <Btn label="Condividi GPX" onPress={() => Share.share({ message: gpx(ride), title: 'Giro MotoLog' })} style={{ flex: 1 }} />
        <Btn
          label="Elimina"
          color={C.red}
          onPress={() => Alert.alert('Eliminare il giro?', undefined, [{ text: 'Annulla', style: 'cancel' }, { text: 'Elimina', style: 'destructive', onPress: onDelete }])}
          style={{ flex: 1 }}
        />
      </Row>
    </ScrollView>
  );
}

export default function Rides() {
  const [rides, setRides] = useStored('rides', []);
  const [settings] = useStored('settings', DEFAULT_SETTINGS);
  const [open, setOpen] = useState(null);
  const miles = settings.miles;
  const ride = rides.find((r) => r.id === open);

  if (ride) return <Detail ride={ride} miles={miles} onBack={() => setOpen(null)} onDelete={() => { setRides((x) => x.filter((r) => r.id !== open)); setOpen(null); }} />;

  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <H1>Giri</H1>
      {rides.length === 0 && <Text style={{ color: C.dim }}>Nessun giro ancora. Registra il primo dalla schermata Registra.</Text>}
      {rides.map((r) => (
        <TouchableOpacity key={r.id} onPress={() => setOpen(r.id)} style={[card, { marginBottom: 10 }]}>
          <Text style={{ color: C.text, fontSize: 17, fontWeight: '700' }}>{dayLabel(r.start)}</Text>
          <Text style={{ color: C.dim, marginTop: 4 }}>
            {fmtDist(r.distance, miles)} {miles ? 'mi' : 'km'} · {fmtDuration(r.elapsed)} · max {fmtSpeed(r.max, miles)} {miles ? 'mph' : 'km/h'}
          </Text>
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
}
