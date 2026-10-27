import React from 'react';
import { View, Text, TouchableOpacity } from 'react-native';
import { C, card } from './theme';

export function Tile({ title, value, unit, color, style }) {
  return (
    <View style={[card, { flex: 1 }, style]}>
      <Text style={{ color: C.dim, fontSize: 11, fontWeight: '700', letterSpacing: 1 }}>{title}</Text>
      <Text style={{ color: color || C.text, fontSize: 26, fontWeight: '800', marginTop: 2 }}>
        {value}
        {unit ? <Text style={{ color: C.dim, fontSize: 13, fontWeight: '600' }}> {unit}</Text> : null}
      </Text>
    </View>
  );
}

export function Chip({ text, color = C.green }) {
  return (
    <View style={{ backgroundColor: color + '30', paddingHorizontal: 10, paddingVertical: 5, borderRadius: 14 }}>
      <Text style={{ color, fontSize: 12, fontWeight: '800' }} numberOfLines={1}>
        {text}
      </Text>
    </View>
  );
}

export function Btn({ label, onPress, color = C.accent, filled = false, disabled, style }) {
  return (
    <TouchableOpacity
      disabled={disabled}
      onPress={onPress}
      style={[
        {
          paddingVertical: 12,
          paddingHorizontal: 16,
          borderRadius: 14,
          alignItems: 'center',
          backgroundColor: filled ? color : C.fill,
          opacity: disabled ? 0.4 : 1,
        },
        style,
      ]}
    >
      <Text style={{ color: filled ? '#000' : color, fontWeight: '800', fontSize: 15 }}>{label}</Text>
    </TouchableOpacity>
  );
}

export function H1({ children }) {
  return <Text style={{ color: C.text, fontSize: 30, fontWeight: '800', marginBottom: 12 }}>{children}</Text>;
}

export function Row({ children, style }) {
  return <View style={[{ flexDirection: 'row', gap: 10, marginBottom: 10 }, style]}>{children}</View>;
}
