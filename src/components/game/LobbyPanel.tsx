import { type FormEvent } from 'react';
import { money, type GameSnapshot } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';
interface Props { state: GameSnapshot; actions: GameActions; disabled: boolean }
const card='rounded-2xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6';
const field='min-h-11 w-full rounded-xl border-2 border-stone-300 bg-white px-3 py-2 text-base focus-visible:outline-2 focus-visible:outline-emerald-700';
const button='rounded-xl bg-emerald-700 px-5 py-3 font-bold text-white hover:bg-emerald-800 disabled:opacity-40';
export default function LobbyPanel({state,actions,disabled}:Props) {
  const isHost=state.me.role==='host';
  const players=[...state.players].sort((a,b)=>(a.role==='host'?-1:1)-(b.role==='host'?-1:1));
  const incomplete=state.spaces.filter(s=>['property','railroad','utility'].includes(s.type) && (!s.price || s.price<=0)).length;
  function settings(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data=new FormData(event.currentTarget);
    void actions.settings({
      p_dice_mode:String(data.get('dice')),
      p_max_players:Number(data.get('maxPlayers')),
      p_initial_balance:Number(data.get('initialBalance')),
      p_go_bonus:Number(data.get('goBonus')),
      p_bail_amount:Number(data.get('bail'))
    });
  }
  return <div className="grid gap-5 lg:grid-cols-[1fr_.9fr]">
    <section className={card}>
      <p className="text-xs font-bold uppercase tracking-widest text-red-700">Sala privada</p>
      <h2 className="mt-1 text-2xl font-black text-emerald-950">
        {state.players.length} / {state.room.maxPlayers} jugadores
      </h2>
      <p className="mt-2 text-sm text-stone-600">Comparte el código con tus amigos. La sala se cerrará automáticamente cuando comience la partida.</p>
      <ol className="mt-5 space-y-2">
        {players.map((player)=><li key={player.id} className="flex items-center justify-between rounded-xl border border-stone-200 bg-stone-50 p-3">
          <span className="flex items-center gap-2">
            <span className="grid size-9 place-items-center rounded-full bg-emerald-800 font-black text-white">
              {player.alias.slice(0,1).toUpperCase()}
            </span>
            <span className="font-bold">{player.alias} {player.id===state.me.id?'(tú)':''}</span>
          </span>
          {player.role==='host' && <span className="rounded-full bg-amber-100 px-2 py-1 text-xs font-bold text-amber-900">Anfitrión</span>}
        </li>)}
      </ol>
      {isHost ? <div className="mt-6 space-y-3">
        <button type="button" className={button+' w-full'} disabled={disabled || players.length<2}
          onClick={() => {
            if (incomplete>0 && !window.confirm('Hay '+incomplete+' propiedades sin precio. Podrás administrar la banca, pero no comprarlas hasta configurar el tablero. ¿Comenzar igualmente?')) return;
            void actions.start();
          }}>Iniciar partida</button>
        {players.length<2 && <p className="text-center text-xs text-stone-500">Espera al menos a un segundo jugador.</p>}
        {incomplete>0 && <p className="text-center text-xs font-medium text-amber-900">
          Faltan {incomplete} precios del tablero. Puedes editarlos en la pestaña «Tablero».</p>}
      </div> : <div className="mt-6 rounded-xl bg-amber-50 p-4 text-center text-sm font-semibold text-amber-950">
        Esperando a que el anfitrión inicie la partida...
      </div>}
    </section>
    <section className={card}>
      <h2 className="text-xl font-black text-emerald-950">Reglas de la mesa</h2>
      {!isHost && <p className="mt-3 text-sm text-stone-600">Solo el anfitrión puede modificar la configuración antes de iniciar.</p>}
      <form key={state.room.revision} className="mt-5 grid gap-4" onSubmit={settings}>
        <label className="grid gap-1 text-sm font-semibold">Dados
          <select className={field} name="dice" defaultValue={state.room.diceMode} disabled={!isHost}>
            <option value="virtual">Virtuales (servidor)</option>
            <option value="physical">Físicos (registro manual)</option>
          </select>
        </label>
        <label className="grid gap-1 text-sm font-semibold">Máximo de jugadores
          <select className={field} name="maxPlayers" defaultValue={state.room.maxPlayers} disabled={!isHost}>
            {[2,3,4,5,6,7,8].map(n=><option key={n} value={n} disabled={n<state.players.length}>{n}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-sm font-semibold">Saldo inicial
          <input className={field} name="initialBalance" type="number" required min="1" max="1000000"
            defaultValue={state.room.initialBalance} disabled={!isHost}/>
        </label>
        <label className="grid gap-1 text-sm font-semibold">Cobro por pasar Salida
          <input className={field} name="goBonus" type="number" required min="0" max="100000"
            defaultValue={state.room.goBonus} disabled={!isHost}/>
        </label>
        <label className="grid gap-1 text-sm font-semibold">Fianza de cárcel
          <input className={field} name="bail" type="number" required min="0" max="100000"
            defaultValue={state.room.bailAmount} disabled={!isHost}/>
        </label>
        {isHost && <button type="submit" className={button} disabled={disabled}>Guardar configuración</button>}
      </form>
      <p className="mt-4 text-xs text-stone-500">Saldo inicial: {money(state.room.initialBalance)}. Se usan los valores de tu edición física; los precios de propiedades se configuran aparte.</p>
    </section>
  </div>;
}
