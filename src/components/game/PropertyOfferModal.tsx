import { money, type GameSnapshot } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';

interface Props {state:GameSnapshot; actions:GameActions; disabled:boolean}
const colors:Record<string,string>={
  marrón:'#92400e',celeste:'#0284c7',rosa:'#be185d',naranja:'#ea580c',
  rojo:'#b91c1c',amarillo:'#ca8a04',verde:'#15803d',azul:'#1d4ed8'
};

export default function PropertyOfferModal({state,actions,disabled}:Props) {
  const room=state.room;
  if(room.status!=='active' || !room.turnRolled || room.currentPlayerId!==state.me.id ||
    room.pendingAmount>0 || state.cards.some(c=>c.outcome==='pending'))return null;
  const player=state.players.find(p=>p.id===state.me.id);
  const space=state.spaces.find(s=>s.position===player?.position);
  if(!space || !['property','railroad','utility'].includes(space.type) ||
    space.ownerId || space.price===null || space.price<=0 || player?.inJail ||
    state.auctions.some(a=>a.position===space.position && a.status==='open'))return null;
  const related=space.group ? state.spaces.filter(s=>s.group===space.group && s.type==='property') : [];
  return <div className="fixed inset-0 z-40 flex items-center justify-center bg-stone-950/75 p-4 backdrop-blur-sm">
    <section role="dialog" aria-modal="true" aria-labelledby="buy-property-title"
      className="w-full max-w-md overflow-hidden rounded-3xl bg-[#fffaf0] shadow-2xl">
      <div className="h-3" style={{backgroundColor:colors[space.group||'']||'#475569'}}/>
      <div className="p-5 sm:p-7">
        <p className="text-xs font-extrabold uppercase tracking-[.16em] text-emerald-800">
          Casilla {space.position} · Propiedad sin dueño
        </p>
        <h2 id="buy-property-title" className="mt-2 text-2xl font-black leading-tight text-emerald-950">{space.name}</h2>
        <p className="mt-1 text-sm text-stone-600">
          {space.group ? 'Grupo '+space.group : space.type==='railroad'?'Refugio':'Área natural protegida'}
        </p>
        <div className="mt-5 rounded-2xl bg-emerald-950 p-5 text-center text-white">
          <p className="text-xs font-bold uppercase tracking-widest text-emerald-200">Precio de compra</p>
          <p className="mt-2 text-4xl font-black">{money(space.price)}</p>
          <p className="mt-2 text-xs text-emerald-100">Tu saldo: {money(player?.balance||0)}</p>
        </div>
        {space.rents && <p className="mt-3 rounded-lg bg-stone-100 p-3 text-sm font-semibold text-stone-700">
          Alquiler base: {money(space.rents[0]||0)}
          {space.mortgage!==null?' · Hipoteca: '+money(space.mortgage):''}
        </p>}
        {related.length>1 && <div className="mt-4">
          <p className="mb-2 text-xs font-bold text-stone-500">Propiedades del mismo color</p>
          <div className="flex flex-wrap gap-2">
            {related.map(s=><span key={s.position} className="rounded-full border border-stone-200 bg-white px-3 py-1 text-xs font-bold text-stone-700">{s.name}</span>)}
          </div>
        </div>}
        <p className="mt-5 text-sm text-stone-600">¿Qué deseas hacer con esta propiedad?</p>
        <div className="mt-3 grid grid-cols-2 gap-3">
          <button type="button" disabled={disabled||(player?.balance||0)<space.price}
            onClick={()=>void actions.property('buy',space.position)}
            className="min-h-14 rounded-xl bg-emerald-800 px-3 py-3 text-sm font-extrabold text-white disabled:opacity-40">
            Comprar
          </button>
          <button type="button" disabled={disabled} onClick={()=>void actions.declineProperty()}
            className="min-h-14 rounded-xl border-2 border-amber-500 bg-amber-100 px-3 py-3 text-sm font-extrabold text-amber-950 disabled:opacity-40">
            Subastar
          </button>
        </div>
        <p className="mt-3 text-center text-xs text-stone-500">
          Comprar concluye la acción y avanza el turno. Subastar abre pujas desde M 10.
        </p>
      </div>
    </section>
  </div>;
}
