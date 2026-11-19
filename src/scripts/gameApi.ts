/**
 * Supabase RPC adapter. All mutable operations are enforced by PostgreSQL.
 * The only public credential is the Supabase publishable key.
 * Room capability tokens never appear in URLs or Realtime messages.
 */
export interface GameSession {
  code: string;
  token: string;
  topic: string;
  recovery?: string;
}
export interface GamePlayer {
  id: string;
  alias: string;
  role: 'host' | 'player';
  status: 'connected' | 'disconnected' | 'left';
  balance: number;
  position: number;
  order: number | null;
  inJail: boolean;
  jailAttempts: number;
  bankrupt: boolean;
}
export type SpaceType = 'start'|'property'|'railroad'|'utility'|'tax'|'chance'|'community'|'jail'|'go_to_jail'|'parking'|'other';
export interface GameSpace {
  position: number;
  name: string;
  type: SpaceType;
  group: string | null;
  price: number | null;
  rents: number[] | null;
  buildCost: number | null;
  mortgage: number | null;
  ownerId: string | null;
  mortgaged: boolean;
  level: number;
}
export interface RoomInfo {
  code: string;
  name: string | null;
  status: 'waiting'|'active'|'finished';
  maxPlayers: number;
  diceMode: 'virtual'|'physical';
  initialBalance: number;
  goBonus: number;
  bailAmount: number;
  turnNumber: number;
  turnRolled: boolean;
  lastRollDouble: boolean;
  doublesStreak: number;
  currentPlayerId: string | null;
  pendingAmount: number;
  pendingPlayerId: string | null;
  pendingToId: string | null;
  pendingReason: string | null;
  lastRollTotal: number;
  revision: number;
  topic: string;
}
export interface GameEvent {
  id: number;
  type: string;
  actorId: string | null;
  data: Record<string, unknown>;
  at: string;
}
export interface LedgerEntry {
  id: number;
  from: string | null;
  to: string | null;
  amount: number;
  description: string;
  at: string;
}
export interface GameRoll {
  id: number;
  playerId: string;
  d1: number;
  d2: number;
  from: number;
  to: number;
  turn: number;
  mode: 'virtual'|'physical';
}
export interface GameTrade {
  id: string;
  from: string;
  to: string;
  giveCash: number;
  takeCash: number;
  giveSpaces: number[];
  takeSpaces: number[];
  status: string;
}
export interface GameAuction {
  id: string;
  position: number;
  status: string;
  minimum: number;
  highBid: number;
  highBidder: string | null;
}
export interface CardChallenge {
  id: number;
  playerId: string;
  turn: number;
  position: number;
  deck: 'chaman'|'tombola';
  cardNumber: number|null;
  title: string|null;
  instruction: string|null;
  outcome: 'pending'|'completed'|'failed'|'cancelled';
  effect: 'none'|'bank_receive'|'bank_pay'|'pay_player'|'collect_player'|'move'|'jail'|'release_jail';
  amount: number|null;
  otherPlayerId: string|null;
  targetPosition: number|null;
  note: string|null;
  source: 'dice'|'manual';
  drawnAt: string;
  resolvedAt: string|null;
}
export interface CardTotals {
  chaman: number;
  tombola: number;
  pending: number;
  completed: number;
  failed: number;
  cancelled: number;
}
export interface CardSnapshot { cards:CardChallenge[]; totals:CardTotals }
export interface GameSnapshot {
  room: RoomInfo;
  me: { id: string; role: 'host'|'player' };
  players: GamePlayer[];
  spaces: GameSpace[];
  events: GameEvent[];
  ledger: LedgerEntry[];
  rolls: GameRoll[];
  trades: GameTrade[];
  auctions: GameAuction[];
  cards: CardChallenge[];
  cardTotals: CardTotals;
}
const publicUrl = (import.meta.env.PUBLIC_SUPABASE_URL || '').replace(/\/+$/, '');
const publicKey = import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY || '';
export function getRealtimeConfig() { return { publicUrl, publicKey }; }

export async function gameRpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  if (!publicUrl || !publicKey) {
    throw new Error('Faltan PUBLIC_SUPABASE_URL o PUBLIC_SUPABASE_PUBLISHABLE_KEY.');
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(publicUrl + '/rest/v1/rpc/' + name, {
      method: 'POST',
      headers: { apikey: publicKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
      signal: controller.signal,
      cache: 'no-store'
    });
    const json: unknown = await response.json();
    if (!response.ok) {
      const detail = json && typeof json === 'object' && 'message' in json
        ? String((json as { message: unknown }).message) : 'No se pudo completar la operación';
      throw new Error(detail);
    }
    return json as T;
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new Error('La conexión demoró demasiado; comprueba tu internet.');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}
export function sessionKey(code: string) {
  return 'monopoly:session:v1:' + code.toUpperCase();
}
export function saveSession(session: GameSession) {
  localStorage.setItem(sessionKey(session.code), JSON.stringify({
    code: session.code.toUpperCase(), token: session.token, topic: session.topic
  }));
}
export function readSession(code: string): GameSession | null {
  try {
    const value = localStorage.getItem(sessionKey(code));
    if (!value) return null;
    const data: GameSession = JSON.parse(value);
    return data.code.toUpperCase() === code.toUpperCase() && /^[a-f0-9]{64}$/.test(data.token)
      ? data : null;
  } catch { return null; }
}
export function clearSession(code: string) { localStorage.removeItem(sessionKey(code)); }
export function money(amount: number): string {
  return 'S/ ' + new Intl.NumberFormat('es-PE', { maximumFractionDigits: 0 }).format(amount);
}
export async function getSnapshot(session: GameSession): Promise<GameSnapshot> {
  const params={ p_code: session.code, p_token: session.token };
  const [room, cards]=await Promise.all([
    gameRpc<GameSnapshot>('game_snapshot',params),
    gameRpc<CardSnapshot>('game_card_snapshot',params)
  ]);
  return { ...room, cards:cards.cards, cardTotals:cards.totals };
}
export function act(session: GameSession, action: string, data: Record<string, unknown> = {}) {
  return gameRpc<{ ok: boolean }>('game_action', {
    p_code: session.code, p_token: session.token, p_action: action, p_data: data
  });
}
export function propertyAction(session: GameSession, action: string, position: number) {
  return gameRpc<{ ok: boolean }>('game_property', {
    p_code: session.code, p_token: session.token, p_action: action, p_position: position
  });
}
export function tradeAction(session: GameSession, action: string, data: Record<string, unknown>) {
  return gameRpc<{ ok: boolean; id?: string }>('game_trade', {
    p_code: session.code, p_token: session.token, p_action: action, p_data: data
  });
}
export function auctionAction(session: GameSession, action: string, data: Record<string, unknown>) {
  return gameRpc<{ ok: boolean; id?: string }>('game_auction', {
    p_code: session.code, p_token: session.token, p_action: action, p_data: data
  });
}

export function cardAction(session: GameSession, action: string, data: Record<string, unknown> = {}) {
  return gameRpc<{ok:boolean;cardId:number}>('game_card_action',{
    p_code:session.code,p_token:session.token,p_action:action,p_data:data
  });
}
