import { getRealtimeConfig } from './gameApi';

/**
 * Thin Supabase Realtime Protocol 1.0.0 client.
 * Only revision hints traverse a high-entropy, per-room broadcast topic.
 * A hint never authorizes an operation: all state reads require a player capability.
 * No state polling: reconnect and heartbeats are transport-level controls.
 */
export function connectRoomSocket(
  topic: string,
  onChange: () => void,
  onStatus: (status: 'connected'|'connecting'|'disconnected') => void
): () => void {
  const { publicUrl, publicKey } = getRealtimeConfig();
  if (!publicUrl || !publicKey || !/^room_[a-f0-9]{48}$/.test(topic)) {
    onStatus('disconnected');
    return () => {};
  }
  let socket: WebSocket | null = null;
  let stopped = false;
  let heartbeats: ReturnType<typeof setInterval> | undefined;
  let reconnect: ReturnType<typeof setTimeout> | undefined;
  let attempts = 0;
  let reference = 1;
  const wsUrl = publicUrl.replace(/^http/, 'ws') + '/realtime/v1/websocket?apikey=' +
    encodeURIComponent(publicKey) + '&vsn=1.0.0';
  const channel = 'realtime:' + topic;
  const send = (event: string, target: string, payload: Record<string, unknown>, ref: string, joinRef: string | null) => {
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ topic: target, event, payload, ref, join_ref: joinRef }));
    }
  };
  const connect = () => {
    if (stopped) return;
    onStatus('connecting');
    socket = new WebSocket(wsUrl);
    socket.onopen = () => {
      attempts = 0;
      reference = 1;
      send('phx_join', channel, {
        config: { broadcast: { self: false, ack: false }, presence: { enabled: false }, private: false }
      }, '1', '1');
      heartbeats = setInterval(() => {
        reference += 1;
        send('heartbeat', 'phoenix', {}, String(reference), null);
      }, 25000);
    };
    socket.onmessage = (incoming) => {
      let message: { event?: string; ref?: string; payload?: { event?: string; status?: string } };
      try { message = JSON.parse(String(incoming.data)); } catch { return; }
      if (message.event === 'phx_reply' && message.ref === '1') {
        if (message.payload?.status === 'ok') {
          onStatus('connected');
          onChange();
        } else {
          onStatus('disconnected');
        }
      }
      if (message.event === 'broadcast' && message.payload?.event === 'changed') {
        onChange();
      }
    };
    socket.onerror = () => { onStatus('disconnected'); };
    socket.onclose = () => {
      if (heartbeats) clearInterval(heartbeats);
      onStatus('disconnected');
      if (!stopped) {
        attempts = Math.min(attempts + 1, 5);
        reconnect = setTimeout(connect, Math.min(1000 * (2 ** attempts), 15000));
      }
    };
  };
  connect();
  return () => {
    stopped = true;
    if (heartbeats) clearInterval(heartbeats);
    if (reconnect) clearTimeout(reconnect);
    if (socket && socket.readyState < WebSocket.CLOSING) {
      socket.close(1000, 'leave');
    }
    socket = null;
  };
}
