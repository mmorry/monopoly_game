import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { act, auctionAction, cardAction, clearSession, gameRpc, getSnapshot, propertyAction, readSession, saveSession, tradeAction,
  type GameSession, type GameSnapshot } from '../../scripts/gameApi';
import { connectRoomSocket } from '../../scripts/gameSocket';
import LobbyPanel from './LobbyPanel';
import GamePanel from './GamePanel';
import BoardPanel from './BoardPanel';
import MarketPanel from './MarketPanel';
import CardChallengesPanel from './CardChallengesPanel';
import VirtualCardModal from './VirtualCardModal';

export interface GameActions {
  act: (action: string, data?: Record<string, unknown>) => Promise<void>;
  property: (action: string, position: number) => Promise<void>;
  trade: (action: string, data: Record<string, unknown>) => Promise<void>;
  auction: (action: string, data: Record<string, unknown>) => Promise<void>;
  card: (action: string, data: Record<string, unknown>) => Promise<void>;
  finishVirtualCard: (id:number) => Promise<void>;
  useJailPass: (deck:'chaman'|'tombola') => Promise<void>;
  declineProperty: () => Promise<void>;
  cardMode: (mode: 'physical'|'virtual') => Promise<void>;
  setSpace: (data: Record<string, unknown>) => Promise<void>;
  assignF3182Title: (data: Record<string, unknown>) => Promise<void>;
  restoreF3182Board: () => Promise<void>;
  settings: (data: Record<string, unknown>) => Promise<void>;
  start: () => Promise<void>;
  finish: () => Promise<void>;
  leave: () => Promise<void>;
}
const panel = 'rounded-2xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6';
export default function RoomApp() {
  const [code, setCode] = useState('');
  const [session, setSession] = useState<GameSession | null>(null);
  const [snapshot, setSnapshot] = useState<GameSnapshot | null>(null);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [recovery, setRecovery] = useState('');
  const [resumeToken,setResumeToken]=useState('');
  const [accessCopied,setAccessCopied]=useState(false);
  const [busy, setBusy] = useState(false);
  const [connection, setConnection] = useState<'connected'|'connecting'|'disconnected'>('disconnected');
  const [tab, setTab] = useState<'mesa'|'tablero'|'banco'|'negociar'|'cartas'|'historial'>('mesa');
  const busyLoad = useRef(false);
  const refreshQueued = useRef(false);

  useEffect(() => {
    const value = new URLSearchParams(window.location.search).get('codigo')?.trim().toUpperCase() || '';
    setCode(value);
    if (value) setSession(readSession(value));
  }, []);

  const refresh = useCallback(async () => {
    if (!session) return;
    if (busyLoad.current) {
      refreshQueued.current = true;
      return;
    }
    busyLoad.current = true;
    try {
      do {
        refreshQueued.current = false;
        const data = await getSnapshot(session);
        setSnapshot(data);
        setError('');
      } while (refreshQueued.current);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo consultar la partida.');
    } finally {
      busyLoad.current = false;
    }
  }, [session]);

  useEffect(() => { if (session) void refresh(); }, [session, refresh]);
  useEffect(() => {
    if (!session || !snapshot?.room.topic || snapshot.room.status === 'finished') return;
    return connectRoomSocket(snapshot.room.topic, () => { void refresh(); }, next => {
      setConnection(next);
      if (next==='connected') void refresh();
    });
  }, [session, snapshot?.room.topic, snapshot?.room.status, refresh]);
  useEffect(() => {
    const onVisible = () => { if (document.visibilityState === 'visible') void refresh(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);

  const perform = useCallback(async (operation: () => Promise<unknown>, confirmation?: string) => {
    if (confirmation && !window.confirm(confirmation)) return;
    setBusy(true);
    setError('');
    setMessage('');
    try {
      await operation();
      // All successful actions are visible in room state, no redundant success alert.
      await refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'La operación no pudo completarse.');
    } finally {
      setBusy(false);
    }
  }, [refresh]);

  const actions = useMemo<GameActions>(() => ({
    act: (action, data = {}) => session ? perform(() => act(session, action, data)) : Promise.resolve(),
    property: (action, position) => session ? perform(() => propertyAction(session, action, position)) : Promise.resolve(),
    trade: (action, data) => session ? perform(() => tradeAction(session, action, data)) : Promise.resolve(),
    auction: (action, data) => session ? perform(() => auctionAction(session, action, data)) : Promise.resolve(),
    card: (action, data) => session ? perform(() => cardAction(session, action, data)) : Promise.resolve(),
    finishVirtualCard: (id) => session ? perform(() => gameRpc('game_finish_virtual_card',{
      p_code:session.code,p_token:session.token,p_card_id:id
    })) : Promise.resolve(),
    useJailPass: (deck) => session ? perform(() => gameRpc('game_use_jail_pass',{
      p_code:session.code,p_token:session.token,p_deck:deck
    })) : Promise.resolve(),
    declineProperty: () => session ? perform(() => gameRpc('game_decline_property',{
      p_code:session.code,p_token:session.token
    })) : Promise.resolve(),
    cardMode: (mode) => session ? perform(() => gameRpc('game_card_mode',{
      p_code:session.code,p_token:session.token,p_mode:mode
    })) : Promise.resolve(),
    restoreF3182Board: () => session ? perform(
      () => gameRpc('game_load_f3182_board', {p_code:session.code,p_token:session.token}),
      '¿Restaurar las 40 casillas oficiales F3182? Se perderán las modificaciones manuales del tablero. Esta acción solo funciona antes de iniciar la partida.') : Promise.resolve(),
    assignF3182Title: (data) => session ? perform(() => gameRpc('game_assign_f3182_title',
      { p_code: session.code, p_token: session.token, ...data })) : Promise.resolve(),
    setSpace: (data) => session ? perform(() => gameRpc('game_set_space',
      { p_code: session.code, p_token: session.token, ...data })) : Promise.resolve(),
    settings: (data) => session ? perform(() => gameRpc('game_settings',
      { p_code: session.code, p_token: session.token, ...data })) : Promise.resolve(),
    start: () => session ? perform(() => gameRpc('game_start_room',
      { p_code: session.code, p_token: session.token })) : Promise.resolve(),
    finish: () => session ? perform(() => gameRpc('game_finish_room',
      { p_code: session.code, p_token: session.token }),
      '¿Terminar la partida para todos? Esta acción es irreversible.') : Promise.resolve(),
    leave: () => session ? perform(async () => {
      await gameRpc('game_leave_room', { p_code: session.code, p_token: session.token });
      clearSession(session.code);
      window.location.assign('/');
    }, '¿Abandonar esta sala?') : Promise.resolve()
  }), [session, perform]);

  const me = snapshot?.players.find(p => p.id === snapshot.me.id);
  const host = snapshot?.me.role === 'host';
  const waiting = snapshot?.room.status === 'waiting';
  const finished = snapshot?.room.status === 'finished';
  const current = snapshot?.room.currentPlayerId === snapshot?.me.id;
  const latestRoll = snapshot?.rolls[0];
  const latestSpace = latestRoll && snapshot?.spaces.find(s=>s.position===latestRoll.to);
  const latestOwner = latestSpace && snapshot?.players.find(p=>p.id===latestSpace.ownerId);
  const latestPlayer = latestRoll && snapshot?.players.find(p=>p.id===latestRoll.playerId);


  async function recover(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!code || !/^[a-f0-9]{64}$/.test(recovery.trim())) {
      setError('La clave de recuperación debe tener 64 caracteres hexadecimales.');
      return;
    }
    setBusy(true);
    try {
      const restored = await gameRpc<GameSession>('game_recover_host', {
        p_code: code, p_recovery: recovery.trim()
      });
      saveSession(restored);
      setRecovery('');
      setSession(restored);
      setError('');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo recuperar la sesión.');
    } finally { setBusy(false); }
  }

  async function restorePlayerSession(event:FormEvent<HTMLFormElement>){
    event.preventDefault();
    const token=resumeToken.trim().toLowerCase();
    if(!code||!/^[a-f0-9]{64}$/.test(token)){
      setError('La clave de jugador debe contener 64 caracteres hexadecimales.');
      return;
    }
    setBusy(true);
    setError('');
    try{
      const result=await gameRpc<GameSnapshot>('game_snapshot',{p_code:code,p_token:token});
      const restored:GameSession={code,token,topic:result.room.topic};
      saveSession(restored);
      setSession(restored);
      setResumeToken('');
    }catch(e){
      setError(e instanceof Error?e.message:'No se pudo recuperar el acceso.');
    }finally{setBusy(false);}
  }
  async function copyPlayerAccess(){
    if(!session)return;
    try{
      await navigator.clipboard.writeText(session.token);
      setAccessCopied(true);
    }catch{setError('No se pudo copiar la clave. Revisa los permisos del navegador.');}
  }

  async function shareRoom() {
    const url = window.location.origin + '/unirse?codigo=' + encodeURIComponent(code);
    try {
      if (navigator.share) await navigator.share({ title: 'Monopoly Perú', text: 'Únete a mi partida', url });
      else { await navigator.clipboard.writeText(url); setMessage('Enlace de invitación copiado.'); }
    } catch {
      try { await navigator.clipboard.writeText(url); setMessage('Enlace copiado.'); }
      catch { setMessage('Enlace: ' + url); }
    }
  }

  return <div className="min-h-dvh bg-[#f7f0df] text-stone-950">
    <header className="border-b border-emerald-900/10 bg-emerald-950 text-white">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-5 sm:px-8">
        <a href="/" className="flex items-center gap-3 rounded-lg text-white focus-visible:outline focus-visible:outline-amber-300">
          <span className="grid size-10 place-items-center rounded-xl bg-emerald-600 font-black">M</span>
          <div><span className="block font-black tracking-tight">Monopoly Perú</span>
            <span className="block text-xs text-emerald-100">Banca y partida compartida</span></div>
        </a>
        {code && <div className="flex items-center gap-2">
          <span className="rounded-lg border border-emerald-300/30 px-3 py-2 font-mono text-sm font-bold tracking-wide">{code}</span>
          {snapshot && !finished && <button type="button" className="rounded-lg bg-amber-300 px-3 py-2 text-sm font-bold text-emerald-950" onClick={() => void shareRoom()}>Compartir</button>}
        </div>}
      </div>
    </header>
    <main className="mx-auto max-w-6xl px-4 pb-16 pt-6 sm:px-8">
      {!code && <section className={panel}>
        <h1 className="text-2xl font-bold">Código de sala no indicado</h1>
        <p className="mt-2 text-stone-700">Abre el enlace que te compartieron o crea una sala nueva.</p>
        <a className="mt-4 inline-block font-bold text-emerald-800 underline" href="/">Volver al inicio</a>
      </section>}
      {code && !session && <section className={panel + ' mx-auto max-w-lg'}>
        <h1 className="text-2xl font-black text-emerald-950">Recuperar acceso</h1>
        <p className="mt-3 text-sm text-stone-600">Esta sala no tiene una sesión guardada en este navegador. Puedes unirte como jugador o recuperar tu sesión de anfitrión.</p>
        <a className="mt-4 inline-flex rounded-xl bg-emerald-700 px-5 py-3 font-bold text-white" href={'/unirse?codigo=' + encodeURIComponent(code)}>Unirme como jugador</a>
        <form onSubmit={(event) => void restorePlayerSession(event)} className="mt-6 grid gap-3">
          <label className="font-semibold text-emerald-950" htmlFor="player-key">
            Regresar a mi partida (jugador)
          </label>
          <p className="text-xs text-stone-600">El ingreso de nuevos jugadores se cierra al iniciar, pero puedes recuperar tu ficha con la clave privada guardada, incluso en otro dispositivo.</p>
          <textarea id="player-key" value={resumeToken} onChange={e=>setResumeToken(e.target.value)}
            className="min-h-20 w-full rounded-xl border-2 border-stone-300 p-3 font-mono text-sm"
            required spellCheck={false} placeholder="Clave privada de jugador (64 caracteres)"/>
          <button disabled={busy} className="rounded-xl bg-emerald-800 px-5 py-3 font-bold text-white disabled:opacity-60">
            Recuperar mi ficha
          </button>
        </form>
        <form onSubmit={(event) => void recover(event)} className="mt-8 grid gap-3">
          <label className="font-semibold text-emerald-950" htmlFor="recovery-key">Clave de recuperación del anfitrión</label>
          <textarea id="recovery-key" value={recovery} onChange={event => setRecovery(event.target.value)}
            className="min-h-24 w-full rounded-xl border-2 border-stone-300 p-3 font-mono text-sm"
            required placeholder="Pega aquí tu clave privada" spellCheck={false} />
          <button disabled={busy} className="rounded-xl bg-emerald-700 px-5 py-3 font-bold text-white disabled:opacity-60">Recuperar sesión</button>
        </form>
      </section>}
      {code && session && !snapshot && <p role="status" className="rounded-xl bg-white p-5">Cargando partida y verificando tu sesión...</p>}
      {snapshot && me && <div>
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-xs font-black uppercase tracking-wider text-emerald-700">{waiting ? 'Preparación de sala' : finished ? 'Partida terminada' : 'Partida en curso'}</p>
            <h1 className="text-2xl font-black text-emerald-950 sm:text-3xl">{snapshot.room.name || 'Mesa de Monopoly Perú'}</h1>
            <p className="mt-1 text-sm text-stone-600">Juegas como <strong>{me.alias}</strong>{host ? ' · Anfitrión' : ''}</p>
            <button type="button" className="mt-2 text-xs font-semibold text-emerald-800 underline"
              onClick={()=>void copyPlayerAccess()}>
              {accessCopied?'Clave de acceso copiada':'Guardar mi clave de acceso / reingreso'}
            </button>
          </div>
          <span className={'rounded-full px-3 py-1.5 text-xs font-bold ' +
            (connection==='connected' ? 'bg-emerald-100 text-emerald-900' : 'bg-stone-200 text-stone-700')}>
            {finished ? 'Finalizada' : connection==='connected' ? 'En tiempo real' : connection==='connecting' ? 'Conectando...' : 'Reconectando...'}
          </span>
        </div>
        <nav className="mb-5 flex gap-2 overflow-x-auto pb-2" aria-label="Secciones de la sala">
          {(['mesa','tablero','banco','negociar','cartas','historial'] as const).filter(t => !waiting || (t!=='banco' && t!=='negociar' && t!=='cartas')).map(t =>
            <button key={t} type="button" aria-current={tab===t ? 'page' : undefined}
              onClick={() => setTab(t)}
              className={'shrink-0 rounded-xl px-4 py-2 text-sm font-bold capitalize ' +
                (tab===t?'bg-emerald-800 text-white':'bg-white text-emerald-900 ring-1 ring-stone-200')}>
              {t}</button>
          )}
        </nav>
        {!waiting && latestRoll && latestSpace && <div role="status" aria-live="polite"
          className="mb-4 rounded-xl border border-sky-200 bg-sky-50 p-3 text-sm text-sky-950">
          <strong>{latestPlayer?.alias||'Jugador'}:</strong> dados {latestRoll.d1} + {latestRoll.d2} =
          {' '}{latestRoll.d1+latestRoll.d2} · casilla {latestRoll.to}: <strong>{latestSpace.name}</strong>.
          {latestOwner && <span> Propiedad de <strong>{latestOwner.alias}</strong>
            {latestSpace.mortgaged?' (hipotecada: no genera alquiler)':
              latestOwner.id===latestRoll.playerId?' (propia)':' (alquiler al propietario)'}.</span>}
          {!latestOwner && ['property','railroad','utility'].includes(latestSpace.type) &&
            <span> Sin dueño: compra o subasta.</span>}
        </div>}
        <div aria-live="polite" role="status" className="mb-4 space-y-2">
          {error && <p className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm font-semibold text-red-800">{error}</p>}
          {message && <p className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900">{message}</p>}
        </div>
        {tab==='mesa' && (waiting ?
          <LobbyPanel state={snapshot} actions={actions} disabled={busy}/> :
          <GamePanel state={snapshot} actions={actions} disabled={busy}/>)}
        {tab==='tablero' && <BoardPanel state={snapshot} actions={actions} disabled={busy}/>}
        {tab==='banco' && !waiting && <GamePanel state={snapshot} actions={actions} disabled={busy} mode="bank"/>}
        {tab==='negociar' && !waiting && <MarketPanel state={snapshot} actions={actions} disabled={busy}/>}
        {tab==='cartas' && !waiting && <CardChallengesPanel state={snapshot} actions={actions} disabled={busy}/>}
        <VirtualCardModal state={snapshot} actions={actions} disabled={busy} error={error}/>
        {tab==='historial' && <section className={panel}>
          <h2 className="text-xl font-black text-emerald-950">Registro de la partida</h2>
          {snapshot.ledger.length>0 && <div className="mt-4">
            <h3 className="font-bold">Movimientos bancarios</h3>
            <ol className="mt-2 divide-y divide-stone-100">
              {snapshot.ledger.map(entry => <li key={entry.id} className="flex justify-between gap-3 py-2 text-sm">
                <span>{entry.description}</span><strong>{entry.amount.toLocaleString('es-PE')}</strong>
              </li>)}
            </ol>
          </div>}
          <h3 className="mt-5 font-bold">Eventos recientes</h3>
          <ol className="mt-2 divide-y divide-stone-100">
            {snapshot.events.map(event => <li key={event.id} className="py-2 text-sm text-stone-700">
              <strong>{event.type.replace(/_/g,' ')}</strong> · {snapshot.players.find(p=>p.id===event.actorId)?.alias || 'Banco'}
              <span className="ml-2 text-xs text-stone-500">{new Date(event.at).toLocaleTimeString('es-PE')}</span>
            </li>)}
          </ol>
          {snapshot.events.length===0 && <p className="mt-3 text-sm text-stone-500">Todavía no hay operaciones registradas.</p>}
        </section>}
        {finished && <p className="mt-5 rounded-xl bg-amber-100 p-4 text-center font-semibold text-amber-950">La partida ha terminado. Puedes consultar su estado, pero ya no se permiten transacciones.</p>}
        <div className="mt-7 flex justify-end gap-3">
          <button type="button" onClick={() => void refresh()} className="rounded-xl border border-emerald-700 px-4 py-2 text-sm font-bold text-emerald-900">Actualizar ahora</button>
          {waiting && !host && <button disabled={busy} type="button" onClick={() => void actions.leave()} className="rounded-xl border border-red-200 px-4 py-2 text-sm font-bold text-red-800">Salir de sala</button>}
          {host && !finished && <button disabled={busy} type="button" onClick={() => void actions.finish()} className="rounded-xl border border-red-200 px-4 py-2 text-sm font-bold text-red-800">Finalizar sala</button>}
        </div>
      </div>}
      {error && !snapshot && <p role="alert" className="mx-auto mt-4 max-w-lg rounded-xl border border-red-200 bg-red-50 p-4 text-red-800">{error}</p>}
    </main>
  </div>;
}
