import React from 'react';
import { View, Text } from 'react-native';
import Svg, { Path, Line, Defs, LinearGradient, Stop } from 'react-native-svg';
import { C } from './theme';

const TOP = 300;
const START = 135;
const SWEEP = 270;

function polar(cx, cy, r, deg) {
  const a = (deg * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
}

function arc(cx, cy, r, from, to) {
  const [x1, y1] = polar(cx, cy, r, from);
  const [x2, y2] = polar(cx, cy, r, to);
  const large = to - from > 180 ? 1 : 0;
  return `M ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2}`;
}

/** Tachimetro fino a 300 km/h (185 mph). `value` è già nell'unità scelta. */
export default function Gauge({ value, unit, size = 280, miles }) {
  const top = miles ? 185 : TOP;
  const cx = size / 2;
  const cy = size / 2;
  const r = size / 2 - 18;
  const frac = Math.min(1, Math.max(0, value / top));
  const end = START + SWEEP * frac;
  const ticks = [];
  for (let v = 0; v <= top; v += miles ? 20 : 20) {
    const f = v / top;
    const deg = START + SWEEP * f;
    const major = v % (miles ? 40 : 50) === 0 || v === 0;
    const [x1, y1] = polar(cx, cy, r + 4, deg);
    const [x2, y2] = polar(cx, cy, r - (major ? 12 : 6), deg);
    ticks.push(<Line key={v} x1={x1} y1={y1} x2={x2} y2={y2} stroke={major ? '#ffffff88' : '#ffffff33'} strokeWidth={major ? 2 : 1} />);
  }
  const color = frac < 0.5 ? C.green : frac < 0.75 ? C.accent : C.accent2;
  return (
    <View style={{ width: size, height: size * 0.82, alignItems: 'center' }}>
      <Svg width={size} height={size} style={{ position: 'absolute', top: 0 }}>
        <Defs>
          <LinearGradient id="g" x1="0" y1="0" x2="1" y2="0">
            <Stop offset="0" stopColor={C.green} />
            <Stop offset="1" stopColor={color} />
          </LinearGradient>
        </Defs>
        <Path d={arc(cx, cy, r, START, START + SWEEP)} stroke="#ffffff14" strokeWidth={14} strokeLinecap="round" fill="none" />
        {frac > 0.004 && <Path d={arc(cx, cy, r, START, end)} stroke="url(#g)" strokeWidth={14} strokeLinecap="round" fill="none" />}
        {ticks}
      </Svg>
      <View style={{ position: 'absolute', top: size * 0.3, alignItems: 'center' }}>
        <Text style={{ color: C.text, fontSize: size * 0.3, fontWeight: '800', fontVariant: ['tabular-nums'] }}>{Math.round(value)}</Text>
        <Text style={{ color: C.dim, fontSize: 15, fontWeight: '700', letterSpacing: 3 }}>{unit}</Text>
      </View>
    </View>
  );
}
