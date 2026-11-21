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
import PropertyOfferModal from './PropertyOfferModal';

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
  const [detailsOpen,setDetailsOpen]=useState(false);
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
    }, '¿Abandonar definitivamente? Perderás tu plaza y tu sesión actual. Para salir sin perder tu ficha, usa «Salir temporalmente».') : Promise.resolve()
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
  const hostPlayer=snapshot?.players.find(p=>p.role==='host');
  const openAuction=snapshot?.auctions.find(a=>a.status==='open');
  const navItems=[
    {id:'mesa',name:'Mesa',icon:'🎲'},
    {id:'tablero',name:'Tablero',icon:'▦'},
    {id:'banco',name:'Banco',icon:'₥'},
    {id:'negociar',name:'Tratos',icon:'⇄'},
    {id:'cartas',name:'Cartas',icon:'♧'},
    {id:'historial',name:'Registro',icon:'☷'}
  ] as const;


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
    <header className="border-b border-emerald-800 bg-emerald-950 text-white">
      <div className="mx-auto flex h-[68px] max-w-6xl items-center gap-2 px-3 sm:px-8">
        <a href="/" aria-label="Inicio" className="grid size-9 shrink-0 place-items-center rounded-xl bg-emerald-700 text-sm font-black text-white shadow-sm">M</a>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-extrabold text-white">Anfitrión: {hostPlayer?.alias||'Monopoly Perú'}</p>
          <p className="truncate font-mono text-[11px] text-emerald-200">Partida #{code||'—'}</p>
        </div>
        {snapshot && <span className={'size-2 shrink-0 rounded-full '+(connection==='connected'?'bg-emerald-300':'bg-amber-400')}
          title={connection==='connected'?'Conectado':'Sincronizando'} aria-label={connection==='connected'?'En tiempo real':'Sincronizando'}/>}
        {code && snapshot && !finished && <button type="button" onClick={()=>void shareRoom()}
          aria-label="Compartir invitación" title="Compartir" className="grid size-10 shrink-0 place-items-center rounded-xl border border-white/20 bg-white/10 hover:bg-white/20">
          <svg aria-hidden="true" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.7 10.7 6.6-4.4M8.7 13.3l6.6 4.4"/></svg>
        </button>}
        {snapshot && <button type="button" onClick={()=>setDetailsOpen(true)} aria-label="Detalles de la partida"
          title="Detalles de sala" className="grid size-10 shrink-0 place-items-center rounded-xl border border-white/20 bg-white/10 hover:bg-white/20">
          <svg aria-hidden="true" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/></svg>
        </button>}
      </div>
    </header>
    <main className="mx-auto max-w-6xl px-4 pb-32 pt-4 sm:px-8">
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
        {openAuction && tab==='mesa' && <button type="button" onClick={()=>setTab('negociar')}
          className="mb-4 flex w-full items-center justify-between rounded-xl border border-amber-300 bg-amber-100 p-3 text-sm font-bold text-amber-950">
          <span>Subasta activa · {snapshot.spaces[openAuction.position]?.name||'Propiedad'}</span>
          <span>Ver pujas ›</span>
        </button>}
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
        <PropertyOfferModal state={snapshot} actions={actions} disabled={busy}/>
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
        {detailsOpen && <div className="fixed inset-0 z-[60] flex items-center justify-center bg-stone-950/70 p-4" onClick={()=>setDetailsOpen(false)}>
          <section role="dialog" aria-modal="true" aria-labelledby="room-details-heading"
            className="w-full max-w-md rounded-3xl bg-[#fffaf0] p-6 shadow-2xl"
            onClick={e=>e.stopPropagation()}>
            <div className="flex items-center justify-between gap-3">
              <h2 id="room-details-heading" className="text-xl font-black text-emerald-950">Detalles de la partida</h2>
              <button type="button" aria-label="Cerrar detalles" onClick={()=>setDetailsOpen(false)}
                className="grid size-9 place-items-center rounded-full border border-stone-300 text-xl text-stone-700">×</button>
            </div>
            <dl className="mt-4 grid gap-3 text-sm">
              <div><dt className="text-xs font-bold uppercase text-stone-500">Nombre</dt><dd className="font-bold text-emerald-950">{snapshot.room.name||'Mesa de Monopoly Perú'}</dd></div>
              <div><dt className="text-xs font-bold uppercase text-stone-500">Anfitrión</dt><dd className="font-bold">{hostPlayer?.alias||'—'}</dd></div>
              <div><dt className="text-xs font-bold uppercase text-stone-500">Código de partida</dt><dd className="font-mono font-bold">{code}</dd></div>
              <div><dt className="text-xs font-bold uppercase text-stone-500">Estado y turno</dt><dd>{waiting?'Esperando jugadores':finished?'Finalizada':'En curso · Turno '+snapshot.room.turnNumber}</dd></div>
              <div><dt className="text-xs font-bold uppercase text-stone-500">Participantes</dt><dd>{snapshot.players.filter(p=>!p.bankrupt).length} de {snapshot.room.maxPlayers}</dd></div>
              <div><dt className="text-xs font-bold uppercase text-stone-500">Dados y cartas</dt><dd>Dados {snapshot.room.diceMode==='virtual'?'virtuales':'físicos'} · Cartas {snapshot.room.cardMode==='virtual'?'virtuales':'físicas'}</dd></div>
              <div><dt className="text-xs font-bold uppercase text-stone-500">Tu identidad</dt><dd>{me.alias}{host?' · Anfitrión':''}</dd></div>
              <div><dt className="text-xs font-bold uppercase text-stone-500">Conexión</dt><dd>{connection==='connected'?'En tiempo real':'Sincronizando'}</dd></div>
            </dl>
            <button type="button" onClick={()=>void copyPlayerAccess()}
              className="mt-5 w-full rounded-xl border border-emerald-700 px-4 py-3 text-sm font-bold text-emerald-900">
              {accessCopied?'Clave privada copiada':'Guardar clave privada de reingreso'}
            </button>
            <p className="mt-2 text-xs text-stone-500">No compartas esta clave: permite acceder a tu ficha.</p>
          </section>
        </div>}
        <nav aria-label="Secciones de la sala" className="fixed inset-x-0 bottom-0 z-30 border-t border-stone-200 bg-white/95 px-2 pt-2 pb-[max(8px,env(safe-area-inset-bottom))] shadow-[0_-8px_30px_#00000012] backdrop-blur-md">
          <div className={'mx-auto grid max-w-xl gap-1 '+(waiting?'grid-cols-3':'grid-cols-6')}>
            {navItems.filter(t=>!waiting||!['banco','negociar','cartas'].includes(t.id)).map(t=>
              <button key={t.id} type="button" aria-current={tab===t.id?'page':undefined}
                onClick={()=>setTab(t.id)}
                className={'flex min-h-[54px] flex-col items-center justify-center gap-0.5 rounded-xl px-1 text-[10px] font-bold '+
                  (tab===t.id?'bg-emerald-900 text-white':'text-emerald-950')}>
                <span aria-hidden="true" className="text-[22px] leading-none">{t.icon}</span><span>{t.name}</span>
              </button>)}
          </div>
        </nav>
        <div className="mt-7 flex justify-end gap-3">
          <button type="button" onClick={() => void refresh()} className="rounded-xl border border-emerald-700 px-4 py-2 text-sm font-bold text-emerald-900">Actualizar ahora</button>
          <button type="button" onClick={()=>window.location.assign('/')}
            className="rounded-xl border border-emerald-700 px-4 py-2 text-sm font-bold text-emerald-900">
            Salir temporalmente (conservar ficha)
          </button>
          {waiting && !host && <button disabled={busy} type="button" onClick={() => void actions.leave()} className="rounded-xl border border-red-200 px-4 py-2 text-sm font-bold text-red-800">Abandonar sala definitivamente</button>}
          {host && !finished && <button disabled={busy} type="button" onClick={() => void actions.finish()} className="rounded-xl border border-red-200 px-4 py-2 text-sm font-bold text-red-800">Finalizar sala</button>}
        </div>
      </div>}
      {error && !snapshot && <p role="alert" className="mx-auto mt-4 max-w-lg rounded-xl border border-red-200 bg-red-50 p-4 text-red-800">{error}</p>}
    </main>
  </div>;
}
