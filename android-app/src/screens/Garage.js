import React, { useState } from 'react';
import { View, Text, ScrollView, TextInput, Alert, TouchableOpacity } from 'react-native';
import { useStored, DEFAULT_SETTINGS } from '../store';
import { Btn, H1, Row, Chip } from '../ui';
import { C, card } from '../theme';

const num = (s) => parseFloat(String(s).replace(',', '.')) || 0;

const input = { backgroundColor: C.fill, color: C.text, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 10, marginBottom: 8 };

/** Stima serbatoio: riparte dal pieno e consuma in base ai km fatti dopo, più veloce = più consumo. */
export function fuelState(bike, fuel, rides) {
  const tank = bike.tank || 0;
  const mine = fuel.filter((f) => f.bikeId === bike.id).sort((a, b) => a.date - b.date);
  const lastFull = [...mine].reverse().find((f) => f.full);
  if (!tank || !lastFull) return null;
  const learned = (() => {
    const fulls = mine.filter((f) => f.full);
    if (fulls.length < 2) return null;
    const km = fulls[fulls.length - 1].odo - fulls[0].odo;
    const l = mine.filter((f) => f.date > fulls[0].date && f.date <= fulls[fulls.length - 1].date).reduce((a, f) => a + f.liters, 0);
    return km > 50 && l > 0 ? (l / km) * 100 : null;
  })();
  const per100 = learned || 5.5;
  const since = rides.filter((r) => r.bikeId === bike.id && r.start >= lastFull.date);
  let used = 0;
  since.forEach((r) => {
    const kmh = r.avg * 3.6;
    const factor = Math.min(1.5, Math.max(0.85, 1 + 0.004 * (kmh - 80)));
    used += (r.distance / 1000) * (per100 / 100) * factor;
  });
  const added = mine.filter((f) => f.date > lastFull.date).reduce((a, f) => a + f.liters, 0);
  const liters = Math.max(0, Math.min(tank, tank - used + added));
  return { liters, range: (liters / per100) * 100, per100, learned: !!learned, low: liters < tank * 0.2 };
}

export default function Garage() {
  const [bikes, setBikes] = useStored('bikes', []);
  const [fuel, setFuel] = useStored('fuel', []);
  const [rides] = useStored('rides', []);
  const [settings] = useStored('settings', DEFAULT_SETTINGS);
  const [name, setName] = useState('');
  const [tank, setTank] = useState('');
  const [liters, setLiters] = useState({});
  const [cost, setCost] = useState({});
  const [full, setFull] = useState({});

  const odo = (b) => (b.odo || 0) + rides.filter((r) => r.bikeId === b.id).reduce((a, r) => a + r.distance / 1000, 0);

  const add = () => {
    if (!name.trim()) return;
    setBikes((b) => [...b, { id: String(Date.now()), name: name.trim(), tank: num(tank), odo: 0 }]);
    setName('');
    setTank('');
  };

  const addFuel = (b) => {
    const l = num(liters[b.id]);
    if (l <= 0) return Alert.alert('Inserisci i litri messi.');
    setFuel((f) => [...f, { id: String(Date.now()), bikeId: b.id, date: Date.now(), liters: l, cost: num(cost[b.id]), odo: odo(b), full: full[b.id] !== false }]);
    setLiters({ ...liters, [b.id]: '' });
    setCost({ ...cost, [b.id]: '' });
  };

  return (
    <ScrollView contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
      <H1>Garage</H1>
      {bikes.map((b) => {
        const st = fuelState(b, fuel, rides);
        const isFull = full[b.id] !== false;
        return (
          <View key={b.id} style={[card, { marginBottom: 12 }]}>
            <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
              <Text style={{ color: C.text, fontSize: 20, fontWeight: '800' }}>{b.name}</Text>
              <Text style={{ color: C.accent, fontSize: 20, fontWeight: '800' }}>{Math.round(odo(b))} km</Text>
            </Row>
            {st ? (
              <View style={{ marginBottom: 10 }}>
                <Chip text={`~${st.liters.toFixed(1)} L · ${Math.round(st.range)} km di autonomia`} color={st.low ? C.red : C.green} />
                <Text style={{ color: C.dim, fontSize: 12, marginTop: 4 }}>
                  Consumo {st.per100.toFixed(1)} L/100 km {st.learned ? '(imparato dai tuoi pieni)' : '(stima, serve un secondo pieno per imparare)'}
                </Text>
              </View>
            ) : (
              <Text style={{ color: C.dim, marginBottom: 10 }}>
                {b.tank ? 'Registra un pieno per avere la stima di benzina e autonomia.' : 'Imposta la capacità del serbatoio per la stima.'}
              </Text>
            )}
            <TextInput style={input} placeholder="Litri messi" placeholderTextColor={C.dim} keyboardType="decimal-pad" value={liters[b.id] || ''} onChangeText={(v) => setLiters({ ...liters, [b.id]: v })} />
            <TextInput style={input} placeholder="Importo (€)" placeholderTextColor={C.dim} keyboardType="decimal-pad" value={cost[b.id] || ''} onChangeText={(v) => setCost({ ...cost, [b.id]: v })} />
            <Row>
              <TouchableOpacity onPress={() => setFull({ ...full, [b.id]: !isFull })} style={{ flex: 1, justifyContent: 'center' }}>
                <Text style={{ color: C.text }}>{isFull ? '☑' : '☐'} Ho fatto il pieno</Text>
              </TouchableOpacity>
              <Btn label="Salva rifornimento" onPress={() => addFuel(b)} style={{ flex: 1 }} />
            </Row>
            <Btn
              label="Elimina moto"
              color={C.red}
              onPress={() => Alert.alert(`Eliminare ${b.name}?`, undefined, [{ text: 'Annulla', style: 'cancel' }, { text: 'Elimina', style: 'destructive', onPress: () => setBikes((x) => x.filter((y) => y.id !== b.id)) }])}
            />
          </View>
        );
      })}
      <View style={card}>
        <Text style={{ color: C.text, fontWeight: '800', marginBottom: 8 }}>Aggiungi una moto</Text>
        <TextInput style={input} placeholder="Nome (es. Yamaha Tracer 9)" placeholderTextColor={C.dim} value={name} onChangeText={setName} />
        <TextInput style={input} placeholder="Serbatoio (litri)" placeholderTextColor={C.dim} keyboardType="decimal-pad" value={tank} onChangeText={setTank} />
        <Btn filled label="Aggiungi" onPress={add} />
      </View>
    </ScrollView>
  );
}
