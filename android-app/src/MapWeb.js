import React, { useRef, useEffect } from 'react';
import { WebView } from 'react-native-webview';

const HTML = `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>html,body,#m{height:100%;margin:0;background:#17171d}
.pin{width:32px;height:32px;border-radius:16px;color:#fff;font:800 14px sans-serif;display:flex;align-items:center;justify-content:center;border:2px solid #fff;box-sizing:border-box}
.leaflet-container{background:#17171d}</style></head><body><div id="m"></div><script>
var map=L.map('m',{zoomControl:false}).setView([45.46,9.19],13);
L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',{maxZoom:19,attribution:'© OpenStreetMap © CARTO'}).addTo(map);
var layer=L.layerGroup().addTo(map);var fitted=false;
function draw(d){layer.clearLayers();var all=[];
 if(d.line&&d.line.length>1){L.polyline(d.line,{color:'#ff8a1f',weight:5}).addTo(layer);all=all.concat(d.line);}
 (d.pins||[]).forEach(function(p){
  var i=L.divIcon({className:'',html:'<div class="pin" style="background:'+p.color+'">'+p.label+'</div>',iconSize:[32,32],iconAnchor:[16,16]});
  L.marker([p.lat,p.lon],{icon:i}).addTo(layer);all.push([p.lat,p.lon]);});
 if(all.length&&(d.fit||!fitted)){map.fitBounds(all,{padding:[40,40],maxZoom:17});fitted=true;}}
window.draw=draw;</script></body></html>`;

/** Mappa scura con un percorso e/o dei segnaposto: { line:[[lat,lon]], pins:[{lat,lon,label,color}] } */
export default function MapWeb({ line, pins, style }) {
  const ref = useRef(null);
  const ready = useRef(false);
  const last = useRef('');

  const push = () => {
    const data = JSON.stringify({ line: line || [], pins: pins || [] });
    if (!ready.current || data === last.current) return;
    last.current = data;
    ref.current?.injectJavaScript(`window.draw(${data});true;`);
  };

  useEffect(push, [line, pins]);

  return (
    <WebView
      ref={ref}
      style={[{ backgroundColor: '#17171d' }, style]}
      originWhitelist={['*']}
      source={{ html: HTML }}
      onLoadEnd={() => {
        ready.current = true;
        push();
      }}
      javaScriptEnabled
      scrollEnabled={false}
    />
  );
}
