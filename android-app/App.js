import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, SafeAreaView, StatusBar } from 'react-native';
import Record from './src/screens/Record';
import Rides from './src/screens/Rides';
import Stats from './src/screens/Stats';
import Garage from './src/screens/Garage';
import Group from './src/screens/Group';
import Settings from './src/screens/Settings';
import { C } from './src/theme';
import { init, subscribe } from './src/tracker';
import { updateMe, ensureId } from './src/group';

const TABS = [
  ['Registra', '●', Record],
  ['Giri', '☰', Rides],
  ['Statistiche', '▮', Stats],
  ['Garage', '⚙', Garage],
  ['Gruppo', '👥', Group],
  ['Altro', '⋯', Settings],
];

export default function App() {
  const [i, setI] = useState(0);
  useEffect(() => {
    ensureId();
    init();
    return subscribe((t) => {
      if (t.loc) updateMe(t.loc, t.speed, t.battery != null && t.battery >= 0 && t.battery < 0.2);
    });
  }, []);
  const Screen = TABS[i][2];
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: C.bg, paddingTop: StatusBar.currentHeight || 0 }}>
      <StatusBar barStyle="light-content" backgroundColor={C.bg} />
      <View style={{ flex: 1 }}>
        <Screen />
      </View>
      <View style={{ flexDirection: 'row', backgroundColor: '#1d1d24', borderTopWidth: 1, borderTopColor: '#ffffff10' }}>
        {TABS.map(([label, icon], n) => (
          <TouchableOpacity key={label} onPress={() => setI(n)} style={{ flex: 1, alignItems: 'center', paddingVertical: 8 }}>
            <Text style={{ fontSize: 18, color: n === i ? C.accent : C.dim }}>{icon}</Text>
            <Text style={{ fontSize: 10, fontWeight: '700', color: n === i ? C.accent : C.dim }}>{label}</Text>
          </TouchableOpacity>
        ))}
      </View>
    </SafeAreaView>
  );
}
