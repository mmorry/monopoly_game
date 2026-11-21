import { useState, type FormEvent } from 'react';
import { money, type GameSnapshot, type GameTrade } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';
interface Props { state:GameSnapshot; actions:GameActions; disabled:boolean }
const field='min-h-11 w-full rounded-xl border-2 border-stone-300 bg-white px-3 py-2 text-base focus-visible:outline-emerald-700';
const btn='rounded-xl bg-emerald-700 px-4 py-3 text-sm font-bold text-white disabled:opacity-40';
const btnSecondary='rounded-xl border-2 border-emerald-700 px-4 py-2 text-sm font-bold text-emerald-800 disabled:opacity-40';
const card='rounded-2xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6';
export default function MarketPanel({state,actions,disabled}:Props) {
  const [recipient,setRecipient]=useState('');
  const others=state.players.filter(p=>p.id!==state.me.id && !p.bankrupt);
  const offered=state.spaces.filter(s=>s.ownerId===state.me.id && s.level===0);
  const requested=state.spaces.filter(s=>s.ownerId===recipient && s.level===0);
  const sale=state.spaces.filter(s=>!s.ownerId && s.price!==null && s.price>0 &&
    ['property','railroad','utility'].includes(s.type));
  const isHost=state.me.role==='host';
  const isActive=state.room.status==='active';
  function name(id:string|null) { return state.players.find(p=>p.id===id)?.alias || 'Jugador'; }
  function describe(t:GameTrade) {
    const give=t.giveSpaces.map(n=>state.spaces[n]?.name||('#'+n));
    const take=t.takeSpaces.map(n=>state.spaces[n]?.name||('#'+n));
    return 'Entrega: '+(give.join(', ')||'ninguna propiedad')+' + '+money(t.giveCash)+
      ' · Recibe: '+(take.join(', ')||'ninguna propiedad')+' + '+money(t.takeCash);
  }
  function offer(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data=new FormData(event.currentTarget);
    void actions.trade('offer',{
      to:String(data.get('to')),
      giveCash:Number(data.get('giveCash')||0),
      takeCash:Number(data.get('takeCash')||0),
      giveSpaces:data.getAll('giveSpaces').map(v=>Number(v)),
      takeSpaces:data.getAll('takeSpaces').map(v=>Number(v))
    });
  }
  function startAuction(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data=new FormData(event.currentTarget);
    void actions.auction('start',{position:Number(data.get('position')),minimum:Number(data.get('minimum'))});
  }
  return <div className="grid gap-5">
    <div className="grid gap-5 lg:grid-cols-2">
      <section className={card}>
        <h2 className="text-xl font-black text-emerald-950">Negociar propiedades</h2>
        <p className="mt-2 text-sm text-stone-600">Propón un intercambio de dinero y terrenos. Los cambios solo se realizan cuando la otra persona acepta.</p>
        <form onSubmit={offer} className="mt-4 grid gap-4">
          <label className="grid gap-1 text-sm font-semibold">Negociar con
            <select className={field} name="to" required value={recipient} onChange={e=>setRecipient(e.target.value)}>
              <option value="">Seleccionar jugador</option>
              {others.map(p=><option value={p.id} key={p.id}>{p.alias}</option>)}
            </select></label>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="grid gap-1 text-sm font-semibold">Dinero que ofreces
              <input className={field} type="number" name="giveCash" min="0" max="1000000000" step="1" defaultValue="0"/></label>
            <label className="grid gap-1 text-sm font-semibold">Dinero que solicitas
              <input className={field} type="number" name="takeCash" min="0" max="1000000000" step="1" defaultValue="0"/></label>
          </div>
          <label className="grid gap-1 text-sm font-semibold">Propiedades que entregas (selección múltiple)
            <select className={field+' min-h-28'} name="giveSpaces" multiple size={Math.min(Math.max(offered.length,2),5)}>
              {offered.map(s=><option value={s.position} key={s.position}>{s.position} · {s.name}</option>)}
            </select></label>
          <label className="grid gap-1 text-sm font-semibold">Propiedades que solicitas
            <select className={field+' min-h-28'} name="takeSpaces" multiple size={Math.min(Math.max(requested.length,2),5)}>
              {requested.map(s=><option value={s.position} key={s.position}>{s.position} · {s.name}</option>)}
            </select></label>
          <p className="text-xs text-stone-500">En móvil, mantén pulsado para seleccionar varias propiedades. No se intercambian terrenos con construcciones.</p>
          <button type="submit" className={btn} disabled={disabled || !isActive || !recipient}>Enviar propuesta</button>
        </form>
      </section>
      <section className={card}>
        <h2 className="text-xl font-black text-emerald-950">Propuestas pendientes</h2>
        {state.trades.length===0 && <p className="mt-4 text-sm text-stone-500">No hay intercambios pendientes.</p>}
        <div className="mt-4 grid gap-3">
          {state.trades.map(t=><article key={t.id} className="rounded-xl border border-stone-200 bg-stone-50 p-4">
            <p className="font-bold">{name(t.from)} → {name(t.to)}</p>
            <p className="mt-2 text-sm leading-6 text-stone-700">{describe(t)}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              {t.to===state.me.id && <>
                <button className={btn} disabled={disabled || !isActive} onClick={()=>void actions.trade('accept',{id:t.id})}>Aceptar</button>
                <button className={btnSecondary} disabled={disabled || !isActive} onClick={()=>void actions.trade('reject',{id:t.id})}>Rechazar</button>
              </>}
              {t.from===state.me.id && <button className={btnSecondary} disabled={disabled || !isActive}
                onClick={()=>void actions.trade('cancel',{id:t.id})}>Cancelar propuesta</button>}
            </div>
          </article>)}
        </div>
      </section>
    </div>
    <section className={card}>
      <h2 className="text-xl font-black text-emerald-950">Subastas</h2>
      <p className="mt-1 text-sm text-stone-600">Cuando se rechaza una propiedad, el sistema inicia la subasta en M 10. Cada puja aumenta como mínimo M 1; puedes ofrecer cantidades mayores. Cualquier jugador con saldo suficiente puede participar.</p>
      {isHost && <form className="mt-4 flex flex-wrap items-end gap-3" onSubmit={startAuction}>
        <label className="grid min-w-44 grow gap-1 text-sm font-semibold">Propiedad sin dueño
          <select required className={field} name="position">
            <option value="">Seleccionar propiedad</option>
            {sale.map(s=><option value={s.position} key={s.position}>{s.position} · {s.name}</option>)}
          </select>
        </label>
        <label className="grid w-32 gap-1 text-sm font-semibold">Puja inicial
          <input className={field} required name="minimum" type="number" min="1" step="1" defaultValue="10"/></label>
        <button disabled={disabled || !isActive || sale.length===0} className={btn}>Abrir subasta</button>
      </form>}
      {state.auctions.length===0 && <p className="mt-4 text-sm text-stone-500">No hay subastas abiertas.</p>}
      <div className="mt-4 grid gap-4 md:grid-cols-2">
        {state.auctions.map(a=><article key={a.id} className="rounded-xl border border-amber-200 bg-amber-50 p-4">
          <h3 className="font-bold text-amber-950">{state.spaces[a.position]?.name || 'Casilla '+a.position}</h3>
          <p className="mt-1 text-sm">Puja más alta: <strong>{money(a.highBid)}</strong> {a.highBidder?'· '+name(a.highBidder):''}</p>
          <form onSubmit={e=>{e.preventDefault();const d=new FormData(e.currentTarget);
            void actions.auction('bid',{id:a.id,amount:Number(d.get('amount'))});}} className="mt-3 flex flex-wrap gap-2">
            <label className="grow text-sm font-semibold">Tu puja
              <input className={field+' mt-1'} type="number" required name="amount"
                min={Math.max(a.minimum,a.highBid+1)} step="1" defaultValue={Math.max(a.minimum,a.highBid+1)}/>
            </label>
            <button className={btn+' self-end'} disabled={disabled || !isActive}>Pujar</button>
          </form>
          {isHost && <div className="mt-3 flex gap-2">
            <button className={btn} disabled={disabled || !isActive || a.highBid===0}
              onClick={()=>void actions.auction('close',{id:a.id})}>Cerrar y adjudicar</button>
            <button className={btnSecondary} disabled={disabled || !isActive}
              onClick={()=>void actions.auction('cancel',{id:a.id})}>Cancelar</button>
          </div>}
        </article>)}
      </div>
    </section>
  </div>;
}
