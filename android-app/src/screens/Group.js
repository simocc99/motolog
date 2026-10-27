import React, { useEffect, useState } from 'react';
import { View, Text, ScrollView, TextInput, Share } from 'react-native';
import { subscribe } from '../tracker';
import { subscribeGroup, join, startDemo, leave, setGapLimit, setVoice, ensureId } from '../group';
import { useStored, DEFAULT_SETTINGS } from '../store';
import { fmtMeters, haversine } from '../geo';
import MapWeb from '../MapWeb';
import { Btn, Chip, H1, Row } from '../ui';
import { C, card } from '../theme';

const input = { backgroundColor: C.fill, color: C.text, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 10, marginBottom: 8 };
const rnd = () => Array.from({ length: 5 }, () => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 31)]).join('');

export default function Group() {
  const [g, setG] = useState({ active: false, riders: [], behind: [], gapLimit: 500 });
  const [me, setMe] = useState(null);
  const [server, setServer] = useStored('groupServer', '');
  const [name, setName] = useStored('groupName', '');
  const [code, setCode] = useStored('groupCode', '');
  const [settings] = useStored('settings', DEFAULT_SETTINGS);
  const [bad, setBad] = useState(false);

  useEffect(() => {
    ensureId();
    const a = subscribeGroup(setG);
    const b = subscribe((t) => {
      if (t.loc) {
        setMe(t.loc);
      }
    });
    return () => {
      a();
      b();
    };
  }, []);
  useEffect(() => setVoice(settings.voice), [settings.voice]);

  if (!g.active) {
    return (
      <ScrollView contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
        <H1>Gruppo</H1>
        <View style={card}>
          <Text style={{ color: C.text, fontWeight: '800', marginBottom: 8 }}>Gruppo reale</Text>
          <TextInput style={input} placeholder="Il tuo nome" placeholderTextColor={C.dim} value={name} onChangeText={setName} />
          <Row>
            <TextInput style={[input, { flex: 1, marginBottom: 0 }]} placeholder="Codice del gruppo" placeholderTextColor={C.dim} autoCapitalize="characters" value={code} onChangeText={setCode} />
            <Btn label="Nuovo" onPress={() => setCode(rnd())} />
          </Row>
          <TextInput style={input} placeholder="Server (ws://…:8787)" placeholderTextColor={C.dim} autoCapitalize="none" autoCorrect={false} value={server} onChangeText={setServer} />
          {bad && <Text style={{ color: C.red, marginBottom: 8 }}>Indirizzo non valido: deve iniziare con ws:// o wss://</Text>}
          <Btn filled label="Entra nel gruppo" disabled={code.length < 3 || !server} onPress={async () => setBad(!(await join(server, code, name)))} />
          <Text style={{ color: C.dim, fontSize: 12, marginTop: 8 }}>
            Serve il piccolo server della cartella server/ (basta `node server.js` su un PC). Tutti usano lo stesso codice e lo stesso indirizzo.
          </Text>
        </View>
        <View style={[card, { marginTop: 12 }]}>
          <Btn label="Prova con piloti simulati" onPress={() => startDemo(name)} />
          <Text style={{ color: C.dim, fontSize: 12, marginTop: 8 }}>Senza server: tre piloti finti ti girano attorno e uno resta sempre più indietro.</Text>
        </View>
      </ScrollView>
    );
  }

  const behindIds = new Set(g.behind.map((b) => b.id));
  const pins = g.riders.map((r) => ({ lat: r.lat, lon: r.lon, label: r.name.slice(0, 1).toUpperCase(), color: r.isMe ? C.accent : behindIds.has(r.id) ? C.red : C.blue }));
  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <View style={{ height: 280, borderRadius: 18, overflow: 'hidden', marginBottom: 12 }}>
        <MapWeb pins={pins} />
      </View>
      <Row style={{ alignItems: 'center' }}>
        <Chip text={g.demo ? 'DEMO' : g.connected ? 'COLLEGATO' : 'RICONNESSIONE…'} color={g.connected ? C.green : C.accent} />
        <Text style={{ color: C.dim, fontWeight: '700', flex: 1 }}>Codice {g.code}</Text>
        {!g.demo && <Btn label="Condividi" onPress={() => Share.share({ message: `Entra nel mio gruppo MotoLog: codice ${g.code}, server ${server}` })} />}
      </Row>
      <View style={[card, { marginBottom: 12 }]}>
        <Row style={{ alignItems: 'center', marginBottom: 0 }}>
          <Text style={{ color: C.text, flex: 1 }}>Avviso se più lontano di {fmtMeters(g.gapLimit)}</Text>
          <Btn label="−" onPress={() => setGapLimit(Math.max(200, g.gapLimit - 100))} />
          <Btn label="+" onPress={() => setGapLimit(Math.min(3000, g.gapLimit + 100))} />
        </Row>
      </View>
      {[...g.riders].sort((a, b) => (b.isMe ? 1 : 0) - (a.isMe ? 1 : 0)).map((r) => {
        const b = g.behind.find((x) => x.id === r.id);
        return (
          <View key={r.id} style={[card, { marginBottom: 8, flexDirection: 'row', alignItems: 'center' }]}>
            <View style={{ flex: 1 }}>
              <Text style={{ color: C.text, fontWeight: '800', fontSize: 16 }}>{r.isMe ? `${r.name} (tu)` : r.name}</Text>
              <Text style={{ color: C.dim, fontSize: 12 }}>
                {Math.round((r.speed || 0) * 3.6)} km/h{!r.isMe && me ? ` · a ${fmtMeters(haversine(me, r))}` : ''}
              </Text>
            </View>
            {b && <Chip text={`INDIETRO ${fmtMeters(b.gap)}`} color={C.red} />}
          </View>
        );
      })}
      <Btn label="Esci dal gruppo" color={C.red} onPress={leave} style={{ marginTop: 8 }} />
    </ScrollView>
  );
}
