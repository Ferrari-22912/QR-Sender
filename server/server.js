const { WebSocketServer } = require('ws');
const crypto = require('crypto');

const wss = new WebSocketServer({ host: '0.0.0.0', port: Number(process.env.PORT || 8787), maxPayload: 2 * 1024 * 1024 });
const rooms = new Map(); // otp -> { host, peer, expires }
const attempts = new Map(); // coarse per-IP join throttle
const makeOtp = () => String(crypto.randomInt(0, 1_000_000_000)).padStart(10, '0');
const send = (ws, message) => { if (ws?.readyState === 1) ws.send(JSON.stringify(message)); };

function remove(ws) {
  const otp = ws.room;
  if (!otp) return;
  const room = rooms.get(otp);
  if (!room) return;
  if (room.host === ws) {
    send(room.peer, { type: 'peer_disconnected' });
    rooms.delete(otp);
  } else if (room.peer === ws) {
    room.peer = null;
    send(room.host, { type: 'peer_disconnected' });
  }
}

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return send(ws, { type: 'error', message: 'Invalid message.' }); }
    if (msg.type === 'host') {
      let otp;
      do { otp = makeOtp(); } while (rooms.has(otp));
      ws.room = otp;
      rooms.set(otp, { host: ws, peer: null, expires: Date.now() + 10 * 60 * 1000 });
      return send(ws, { type: 'hosted', otp, expiresAt: Date.now() + 10 * 60 * 1000 });
    }
    if (msg.type === 'join') {
      const ip = ws._socket?.remoteAddress || 'unknown';
      const now = Date.now();
      const prior = attempts.get(ip);
      if (!prior || now - prior.started > 60_000) attempts.set(ip, { started: now, count: 1 });
      else prior.count += 1;
      if ((attempts.get(ip)?.count || 0) > 20) return send(ws, { type: 'error', message: 'Too many pairing attempts from this address. Wait a minute and try again.' });
      const otp = String(msg.otp || '').replace(/\D/g, '');
      const room = rooms.get(otp);
      if (!room || room.expires < Date.now()) {
        if (room) rooms.delete(otp);
        return send(ws, { type: 'error', message: 'Code expired or not found. Ask the host to create a new session.' });
      }
      if (room.peer && room.peer.readyState === 1) return send(ws, { type: 'error', message: 'This session already has a connected sender.' });
      ws.room = otp;
      room.peer = ws;
      send(ws, { type: 'connected', role: 'sender' });
      send(room.host, { type: 'peer_connected', role: 'sender' });
      return;
    }
    if (msg.type === 'leave') { remove(ws); ws.room = null; return; }
    const room = rooms.get(ws.room);
    if (!room) return send(ws, { type: 'error', message: 'Session is no longer available.' });
    const target = room.host === ws ? room.peer : room.host;
    if (!target || target.readyState !== 1) return send(ws, { type: 'error', message: 'Your peer is offline.' });
    // Relay only application payloads, never allow clients to forge server control events.
    if (['control', 'file_start', 'file_chunk', 'file_end', 'media', 'text'].includes(msg.type)) send(target, msg);
  });
  ws.on('close', () => remove(ws));
  ws.on('error', () => remove(ws));
});

setInterval(() => {
  for (const [otp, room] of rooms) {
    if (room.expires < Date.now()) {
      send(room.host, { type: 'error', message: 'Session expired. Start a new host session.' });
      send(room.peer, { type: 'error', message: 'Session expired.' });
      rooms.delete(otp);
    }
  }
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30_000);

console.log(`QR Sender local relay listening on ws://0.0.0.0:${wss.options.port}`);
