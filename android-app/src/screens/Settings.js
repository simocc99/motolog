import React from 'react';
import { View, Text, ScrollView, Switch } from 'react-native';
import { useStored, DEFAULT_SETTINGS } from '../store';
import { applySettings } from '../tracker';
import { Btn, H1, Row } from '../ui';
import { C, card } from '../theme';

function Item({ label, hint, children }) {
  return (
    <View style={{ paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#ffffff10' }}>
      <Row style={{ alignItems: 'center', marginBottom: 0 }}>
        <View style={{ flex: 1 }}>
          <Text style={{ color: C.text, fontSize: 15 }}>{label}</Text>
          {hint ? <Text style={{ color: C.dim, fontSize: 12 }}>{hint}</Text> : null}
        </View>
        {children}
      </Row>
    </View>
  );
}

export default function Settings() {
  const [s, setS] = useStored('settings', DEFAULT_SETTINGS);
  const set = (k, v) => {
    const next = { ...s, [k]: v };
    setS(next);
    applySettings(next);
  };
  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <H1>Altro</H1>
      <View style={card}>
        <Item label="Miglia invece di km">
          <Switch value={s.miles} onValueChange={(v) => set('miles', v)} trackColor={{ true: C.accent }} />
        </Item>
        <Item label="Risparmio batteria" hint="Dopo 25 s di inattività lo schermo diventa nero; sensori meno frequenti.">
          <Switch value={s.saver} onValueChange={(v) => set('saver', v)} trackColor={{ true: C.accent }} />
        </Item>
        <Item label="Avvisi vocali" hint="Limite di velocità, pausa, chi resta indietro nel gruppo.">
          <Switch value={s.voice} onValueChange={(v) => set('voice', v)} trackColor={{ true: C.accent }} />
        </Item>
        <Item label="Avviso limite di velocità">
          <Switch value={s.speedAlert} onValueChange={(v) => set('speedAlert', v)} trackColor={{ true: C.accent }} />
        </Item>
        <Item label={`Limite: ${s.speedLimit} km/h`}>
          <Btn label="−" onPress={() => set('speedLimit', Math.max(30, s.speedLimit - 10))} />
          <Btn label="+" onPress={() => set('speedLimit', Math.min(300, s.speedLimit + 10))} />
        </Item>
        <Item label={`Pausa ogni ${s.breakHours} h`} hint="0 = disattivata">
          <Btn label="−" onPress={() => set('breakHours', Math.max(0, s.breakHours - 1))} />
          <Btn label="+" onPress={() => set('breakHours', Math.min(6, s.breakHours + 1))} />
        </Item>
      </View>
      <Text style={{ color: C.dim, fontSize: 12, marginTop: 12 }}>
        MotoLog per Android · i dati restano sul telefono. Il gruppo usa solo il server che scegli tu.
      </Text>
    </ScrollView>
  );
}
