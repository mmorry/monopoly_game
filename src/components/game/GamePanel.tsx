import { useState, type FormEvent } from 'react';
import { money, type GameSnapshot, type GamePlayer } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';
import CardChallengesPanel from './CardChallengesPanel';
interface Props { state: GameSnapshot; actions: GameActions; disabled: boolean; mode?: 'bank' }
const field='min-h-11 w-full rounded-xl border-2 border-stone-300 bg-white px-3 py-2 text-base text-stone-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700';
const btn='rounded-xl bg-emerald-700 px-4 py-3 text-sm font-black text-white hover:bg-emerald-800 disabled:cursor-not-allowed disabled:opacity-40';
const card='rounded-2xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6';
function sortedPlayers(state: GameSnapshot) {
  return [...state.players].sort((a,b) => (a.order??99)-(b.order??99) || (a.role==='host'?-1:1));
}
export default function GamePanel({ state, actions, disabled, mode }: Props) {
  const players=sortedPlayers(state);
  const me=players.find(p=>p.id===state.me.id);
  const host=state.me.role==='host';
  const canAct=state.room.status==='active';
  const turn=state.room.currentPlayerId===state.me.id;
  const current=players.find(p=>p.id===state.room.currentPlayerId);
  const landing=state.spaces.find(s=>s.position===me?.position);
  const lastRoll=state.rolls[0];
  const [rolling,setRolling]=useState(false);
  const dieFaces=['','⚀','⚁','⚂','⚃','⚄','⚅'];
  async function rollDice(data:Record<string,unknown> = {}){
    setRolling(true);
    try { await actions.act('roll',data); }
    finally { window.setTimeout(()=>setRolling(false),650); }
  }
  const lastLanding=lastRoll ? state.spaces.find(s=>s.position===lastRoll.to) : null;
  const lastOwner=state.players.find(p=>p.id===lastLanding?.ownerId);
  const rolledBy=state.players.find(p=>p.id===lastRoll?.playerId);
  const colorGroups:Record<string,string>={
    marrón:'#8b4513',celeste:'#38bdf8',rosa:'#ec4899',naranja:'#f97316',
    rojo:'#dc2626',amarillo:'#eab308',verde:'#15803d',azul:'#1d4ed8'
  };
  const myProperties=state.spaces.filter(s=>s.ownerId===state.me.id);
  const groupedProperties=Object.entries(myProperties.reduce<Record<string,typeof myProperties>>((groups,s)=>{
    const group=s.group||'Especial';
    (groups[group]??=[]).push(s);
    return groups;
  },{}));
  const [die1,setDie1]=useState(1);
  const [die2,setDie2]=useState(1);
  const [transferTo,setTransferTo]=useState('');
  const [bankTo,setBankTo]=useState('');
  const [moveTo,setMoveTo]=useState('');
  const others=players.filter(p=>p.id!==state.me.id && !p.bankrupt);
  const paymentRecipient=players.find(p=>p.id===state.room.pendingToId);

  function submitTransfer(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data=new FormData(event.currentTarget);
    void actions.act('transfer',{to:String(data.get('to')),amount:Number(data.get('amount'))});
  }
  function submitBank(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data=new FormData(event.currentTarget);
    void actions.act('bank',{playerId:String(data.get('playerId')),amount:Number(data.get('amount')),
      reason:String(data.get('reason')||'').trim()});
  }
  function submitMove(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data=new FormData(event.currentTarget);
    void actions.act('move',{playerId:String(data.get('playerId')),position:Number(data.get('position')),
      jail:data.has('jail')});
  }

  const bankPanel=<div className="grid gap-5 lg:grid-cols-2">
    <section className={card}>
      <h2 className="text-xl font-black text-emerald-950">Transferir a otro jugador</h2>
      <p className="mt-1 text-sm text-stone-600">Cada pago queda registrado y los dos saldos cambian de forma atómica.</p>
      <form onSubmit={submitTransfer} className="mt-4 grid gap-3">
        <label className="grid gap-1 text-sm font-semibold">Destinatario
          <select required className={field} name="to" value={transferTo} onChange={event=>setTransferTo(event.target.value)}>
            <option value="">Selecciona jugador</option>
            {others.map(p=><option key={p.id} value={p.id}>{p.alias} · {money(p.balance)}</option>)}
          </select></label>
        <label className="grid gap-1 text-sm font-semibold">Importe
          <input required className={field} type="number" name="amount" min="1" step="1" max="1000000000" placeholder="100"/></label>
        <button type="submit" className={btn} disabled={disabled || !canAct || !me || me.bankrupt || others.length===0}>Transferir</button>
      </form>
    </section>
    {host && <section className={card}>
      <h2 className="text-xl font-black text-emerald-950">Banco del anfitrión</h2>
      <p className="mt-1 text-sm text-stone-600">Para cartas físicas, premios, impuestos especiales o correcciones. Usa importes negativos para cobrar.</p>
      <form onSubmit={submitBank} className="mt-4 grid gap-3">
        <label className="grid gap-1 text-sm font-semibold">Jugador
          <select required className={field} name="playerId" value={bankTo} onChange={event=>setBankTo(event.target.value)}>
            <option value="">Selecciona jugador</option>
            {players.filter(p=>!p.bankrupt).map(p=><option key={p.id} value={p.id}>{p.alias}</option>)}
          </select></label>
        <label className="grid gap-1 text-sm font-semibold">Importe (+ abono / − cobro)
          <input required className={field} type="number" name="amount" step="1" min="-1000000000" max="1000000000" placeholder="200"/></label>
        <label className="grid gap-1 text-sm font-semibold">Motivo
          <input required className={field} name="reason" minLength={3} maxLength={200} placeholder="Ej. Carta El Chamán"/></label>
        <button type="submit" className={btn} disabled={disabled || !canAct}>Registrar movimiento</button>
      </form>
    </section>}
  </div>;

  if(mode==='bank') return <div className="space-y-5">{bankPanel}</div>;

  return <div className="grid gap-5">
    {state.cards.some(challenge=>challenge.outcome==='pending') &&
      <CardChallengesPanel state={state} actions={actions} disabled={disabled} compact/>}
    <section className={card}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-xs font-black uppercase tracking-widest text-red-700">Turno {state.room.turnNumber}</p>
          <h2 className="mt-1 text-2xl font-black text-emerald-950">{current?.alias || 'Partida finalizada'}</h2>
          <p className="mt-1 text-sm text-stone-600">{turn ? 'Es tu turno.' : 'Espera tu turno para lanzar los dados.'}</p>
        </div>
        {(lastRoll||rolling) && <div className="rounded-xl bg-amber-100 px-4 py-3 text-center" aria-live="polite">
          <p className="text-xs font-bold uppercase text-amber-900">{rolling?'Lanzando dados…':'Última tirada'}</p>
          <div className="my-1 flex justify-center gap-2">
            {[lastRoll?.d1||1,lastRoll?.d2||1].map((value,i)=>
              <span key={i} className={'text-5xl leading-none text-amber-950 '+(rolling?'animate-bounce':'')}
                style={{animationDelay:i?'120ms':'0ms'}} aria-label={'Dado '+(i+1)+': '+value}>
                {rolling?'⚄':dieFaces[value]}
              </span>)}
          </div>
          {lastRoll && <p className="text-xl font-black text-amber-950">{lastRoll.d1} + {lastRoll.d2} = {lastRoll.d1+lastRoll.d2}</p>}
          {lastRoll && <p className="text-xs font-bold text-amber-950">
            Ficha {lastRoll.from} → {lastRoll.to} · Avanza {lastRoll.d1+lastRoll.d2} casillas
            {lastRoll.d1===lastRoll.d2?' · Dobles':''}
          </p>}
        </div>}
      </div>
      {turn && !state.room.turnRolled && <div className="mt-6 rounded-xl border border-emerald-200 bg-emerald-50 p-4">
        {state.room.diceMode==='physical' ? <div>
          <p className="mb-3 text-sm font-bold text-emerald-950">Lanza tus dados físicos y registra el resultado</p>
          <div className="flex flex-wrap items-end gap-3">
            {[{v:die1,set:setDie1,label:'Dado 1'},{v:die2,set:setDie2,label:'Dado 2'}].map((item)=>
              <label key={item.label} className="grid gap-1 text-sm font-bold">{item.label}
                <select className={field} value={item.v} onChange={e=>item.set(Number(e.target.value))}>
                  {[1,2,3,4,5,6].map(n=><option key={n} value={n}>{n}</option>)}
                </select>
              </label>)}
            <button type="button" className={btn} disabled={disabled || !canAct}
              onClick={()=>void rollDice({d1:die1,d2:die2})}>Registrar dados</button>
          </div>
        </div> : <button type="button" className={btn+' w-full'} disabled={disabled || !canAct}
          onClick={()=>void rollDice()}>Lanzar dos dados virtuales</button>}
      </div>}
      {turn && state.room.turnRolled && <div className="mt-5 flex flex-wrap items-center gap-3">
        {state.room.pendingAmount>0 && state.room.pendingPlayerId===state.me.id && <div className="w-full rounded-xl border border-red-200 bg-red-50 p-4">
          <p className="font-bold text-red-900">{state.room.pendingReason || 'Pago pendiente'}</p>
          <p className="mt-1 text-lg font-black text-red-800">{money(state.room.pendingAmount)} {paymentRecipient ? '→ '+paymentRecipient.alias : '→ Banco'}</p>
          <button className={btn+' mt-3'} disabled={disabled || !canAct || !me || me.balance<state.room.pendingAmount}
            onClick={()=>void actions.act('pay_due')}>Pagar deuda</button>
          {me && me.balance<state.room.pendingAmount && <p className="mt-2 text-xs text-red-800">Saldo insuficiente. Puedes hipotecar propiedades, vender casas o negociar.</p>}
        </div>}
        {landing && <p className="text-sm font-semibold text-emerald-950">Casilla actual: {landing.position} · {landing.name}</p>}
        {landing && !landing.ownerId && landing.price!==null && landing.price>0 &&
          ['property','railroad','utility'].includes(landing.type) && state.room.pendingAmount===0 &&
          <button className={btn} disabled={disabled || !canAct || !me || me.balance<landing.price}
            onClick={()=>void actions.property('buy',landing.position)}>Comprar · {money(landing.price)}</button>}
        {landing && !landing.ownerId && landing.price!==null && landing.price>0 &&
          ['property','railroad','utility'].includes(landing.type) && state.room.pendingAmount===0 &&
          !state.auctions.some(a=>a.position===landing.position) &&
          <button type="button" className="rounded-xl border-2 border-amber-700 px-4 py-3 text-sm font-bold text-amber-900 disabled:opacity-40"
            disabled={disabled||!canAct}
            onClick={()=>void actions.declineProperty()}>
            No comprar · subastar desde M 10
          </button>}
        {landing && !landing.ownerId && ['property','railroad','utility'].includes(landing.type) && !landing.price &&
          <p className="text-sm text-amber-900">El precio de esta casilla aún no está configurado por el anfitrión.</p>}
        {state.room.pendingAmount===0 &&
          <button type="button" disabled={disabled || !canAct} className={btn} onClick={()=>void actions.act('end_turn')}>
            {state.room.lastRollDouble && !me?.inJail ? 'Continuar: dados dobles' : 'Finalizar turno'}
          </button>}
      </div>}
      {turn && me?.inJail && !state.room.turnRolled && <div className="mt-4 rounded-xl bg-amber-50 p-4">
        <p className="text-sm font-semibold text-amber-950">Estás en la cárcel. Puedes intentar dobles o pagar la fianza.</p>
        <button className={btn+' mt-2'} disabled={disabled || me.balance<state.room.bailAmount}
          onClick={()=>void actions.act('bail')}>Pagar fianza · {money(state.room.bailAmount)}</button>
      </div>}
    </section>

    {lastRoll && lastLanding && <section role="status" aria-live="polite"
       className="rounded-xl border-2 border-sky-200 bg-sky-50 p-4 text-sm text-sky-950">
      <strong>{rolledBy?.alias||'Un jugador'}</strong> cayó en <strong>{lastLanding.name}</strong>
      {lastOwner ? <> · Propiedad de <strong>{lastOwner.alias}</strong>{lastLanding.mortgaged?' (hipotecada, sin alquiler)':''}.
        {lastLanding.ownerId!==lastRoll.playerId && !lastLanding.mortgaged
          ? ' Hay que pagar el alquiler correspondiente.' : ''}</>
        : ' · Sin propietario.'}
    </section>}
    <section className={card}>
      <h2 className="mb-4 text-xl font-black text-emerald-950">Jugadores y saldos</h2>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {players.map(p=><div key={p.id} className={'rounded-xl border p-4 ' +
          (p.id===state.room.currentPlayerId?'border-emerald-600 bg-emerald-50':'border-stone-200 bg-stone-50')}>
          <div className="flex items-center justify-between gap-2">
            <h3 className="font-bold text-stone-900">{p.alias}{p.id===state.me.id?' (tú)':''}</h3>
            <span className="text-xs font-semibold text-stone-500">#{(p.order??0)+1}</span>
          </div>
          <p className="mt-2 text-2xl font-black text-emerald-900">{money(p.balance)}</p>
          <p className="mt-1 text-xs text-stone-600">Casilla {p.position}{p.inJail?' · Cárcel':''}{p.bankrupt?' · Bancarrota':''}</p>
        </div>)}
      </div>
    </section>
    {host && <section className={card}>
      <h2 className="text-xl font-black text-emerald-950">Control del anfitrión</h2>
      <p className="mt-1 text-sm text-stone-600">Registra movimientos que indican las cartas físicas o corrige una posición.</p>
      <form className="mt-4 flex flex-wrap items-end gap-3" onSubmit={submitMove}>
        <label className="grid grow gap-1 text-sm font-semibold">Ficha
          <select className={field} name="playerId" required value={moveTo} onChange={e=>setMoveTo(e.target.value)}>
            <option value="">Seleccionar</option>
            {players.filter(p=>!p.bankrupt).map(p=><option key={p.id} value={p.id}>{p.alias}</option>)}
          </select></label>
        <label className="grid w-28 gap-1 text-sm font-semibold">Casilla
          <input className={field} type="number" min="0" max="39" name="position" required/></label>
        <label className="flex items-center gap-2 text-sm font-semibold"><input type="checkbox" name="jail"/> Encarcelar</label>
        <button disabled={disabled || !canAct} className={btn}>Mover ficha</button>
      </form>
    </section>}
    <section className={card}>
      <h2 className="text-xl font-black text-emerald-950">Tus propiedades</h2>
      <p className="mt-1 text-sm text-stone-600">Para comprar, hipotecar o construir, consulta la pestaña Tablero.</p>
      <div className="mt-3 grid gap-3">
        {groupedProperties.map(([group,spaces])=><section key={group} className="rounded-xl border border-stone-200 p-3">
          <h3 className="mb-2 flex items-center gap-2 text-sm font-black text-stone-900">
            <span className="size-4 rounded-sm" style={{backgroundColor:colorGroups[group]||'#a8a29e'}}/>
            {group.toUpperCase()} · {spaces.length} propiedades
          </h3>
          <div className="flex flex-wrap gap-2">
            {spaces.map(s=><span key={s.position} className="rounded-full bg-stone-100 px-3 py-1.5 text-xs font-semibold">
              {s.name}{s.mortgaged?' · hipotecada':''}{s.level?' · '+s.level+' mejoras':''}
            </span>)}
          </div>
        </section>)}
      </div>
      {state.spaces.every(s=>s.ownerId!==state.me.id) && <p className="mt-3 text-sm text-stone-500">Todavía no tienes propiedades.</p>}
      {canAct && me && !me.bankrupt && <button type="button" disabled={disabled} className="mt-4 text-sm font-semibold text-red-700 underline"
        onClick={()=>{if(window.confirm('¿Declararte en bancarrota? Perderás tu dinero y tus propiedades.')) void actions.act('bankrupt');}}>
        Declararme en bancarrota</button>}
    </section>
    {bankPanel}
  </div>;
}
