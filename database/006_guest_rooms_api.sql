-- Monopoly Perú | Version 006 | Guest room APIs
-- Server-generated 256-bit capabilities; only SHA-256 hashes are persisted.
-- All public RPCs validate their own capability; no table access is granted.
begin;
create schema if not exists game_private;
revoke all on schema game_private from public, anon, authenticated;

create or replace function game_private.member(p_code text, p_token text)
returns table(room_id uuid, player_id uuid, player_role text)
language plpgsql security definer set search_path = ''
as $$
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then
    return;
  end if;
  return query
    select r.id, p.id, p.participant_role
    from public.rooms r
    join public.room_players p on p.room_id = r.id
    where r.invite_code=upper(btrim(p_code))
      and p.session_hash=sha256(decode(p_token,'hex'))
      and p.session_expires_at>now()
      and p.participant_status <> 'left'
    limit 1;
end;
$$;
revoke all on function game_private.member(text,text) from public,anon,authenticated;

create or replace function game_private.notify(p_room_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_topic text; v_rev bigint;
begin
  update public.rooms set revision=revision+1 where id=p_room_id
  returning realtime_topic,revision into v_topic,v_rev;
  perform realtime.send(jsonb_build_object('revision',v_rev),'changed',v_topic,false);
end;$$;
revoke all on function game_private.notify(uuid) from public,anon,authenticated;

create or replace function public.game_create_room(
 p_alias text, p_room_name text default null, p_max_players smallint default 6,
 p_dice_mode text default 'virtual', p_initial_balance bigint default 1500,
 p_go_bonus bigint default 200, p_bail_amount bigint default 50
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_room uuid; v_host uuid; v_code text;
 v_token text:=encode(gen_random_bytes(32),'hex');
 v_recovery text:=encode(gen_random_bytes(32),'hex');
 v_topic text;
begin
  if char_length(btrim(coalesce(p_alias,''))) not between 2 and 24 then raise exception 'El alias debe contener entre 2 y 24 caracteres'; end if;
  if p_room_name is not null and char_length(btrim(p_room_name)) not between 1 and 48 then raise exception 'Nombre de sala inválido'; end if;
  if p_max_players not between 2 and 8 then raise exception 'El límite debe estar entre 2 y 8 jugadores'; end if;
  if p_dice_mode not in ('virtual','physical') then raise exception 'Modo de dados inválido'; end if;
  if p_initial_balance not between 1 and 1000000 or p_go_bonus not between 0 and 100000 or p_bail_amount not between 0 and 100000 then raise exception 'Configuración económica inválida'; end if;
  v_code := upper(encode(gen_random_bytes(6),'hex'));
  insert into public.rooms (invite_code,room_name,max_players,dice_mode,initial_balance,go_bonus,bail_amount,host_credential_hash,host_credential_expires_at)
    values (v_code,nullif(btrim(p_room_name),''),p_max_players,p_dice_mode,p_initial_balance,p_go_bonus,p_bail_amount,sha256(decode(v_recovery,'hex')),now()+interval '7 days')
    returning id,realtime_topic into v_room,v_topic;
  insert into public.room_players(room_id,alias,participant_role,session_hash,session_expires_at)
    values(v_room,btrim(p_alias),'host',sha256(decode(v_token,'hex')),now()+interval '30 days')
    returning id into v_host;
  insert into public.room_host_sessions(room_id,session_token_hash,expires_at)
    values(v_room,sha256(decode(v_token,'hex')),now()+interval '30 days');
  insert into public.room_spaces(room_id,position,name,space_type,color_group)
    select v_room,n,
      case n when 0 then 'Salida' when 10 then 'Cárcel / visita'
      when 20 then 'Estacionamiento libre' when 30 then 'Ve a la cárcel'
      else 'Casilla '||n end,
      case when n=0 then 'start' when n=10 then 'jail' when n=20 then 'parking'
      when n=30 then 'go_to_jail' when n in (2,17,33) then 'community'
      when n in (7,22,36) then 'chance' when n in (4,38) then 'tax'
      when n in (5,15,25,35) then 'railroad' when n in (12,28) then 'utility'
      else 'property' end,
      case
      when n in (1,3) then 'marrón'
      when n in (6,8,9) then 'celeste'
      when n in (11,13,14) then 'rosa'
      when n in (16,18,19) then 'naranja'
      when n in (21,23,24) then 'rojo'
      when n in (26,27,29) then 'amarillo'
      when n in (31,32,34) then 'verde'
      when n in (37,39) then 'azul'
      else null end
    from generate_series(0,39) as n;
  return jsonb_build_object('code',v_code,'token',v_token,'recovery',v_recovery,'topic',v_topic);
end;$$;

create or replace function public.game_join_room(p_code text,p_alias text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room public.rooms%rowtype; v_token text:=encode(gen_random_bytes(32),'hex'); v_player uuid; v_n integer;
begin
  if char_length(btrim(coalesce(p_alias,''))) not between 2 and 24 then raise exception 'Alias inválido (2 a 24 caracteres)'; end if;
  select * into v_room from public.rooms where invite_code=upper(btrim(p_code)) for update;
  if not found then raise exception 'Sala no encontrada'; end if;
  if v_room.status<>'waiting' then raise exception 'La partida ya ha comenzado'; end if;
  select count(*) into v_n from public.room_players where room_id=v_room.id and participant_status<>'left';
  if v_n>=v_room.max_players then raise exception 'Sala llena'; end if;
  insert into public.room_players(room_id,alias,session_hash,session_expires_at)
    values(v_room.id,btrim(p_alias),sha256(decode(v_token,'hex')),now()+interval '30 days')
    returning id into v_player;
  insert into public.room_events(room_id,actor_id,event_type,payload)
    values(v_room.id,v_player,'joined',jsonb_build_object('alias',btrim(p_alias)));
  perform game_private.notify(v_room.id);
  return jsonb_build_object('code',v_room.invite_code,'token',v_token,'topic',v_room.realtime_topic);
end;$$;

create or replace function public.game_get_room(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room public.rooms%rowtype; v_me uuid; v_role text;
begin
  select m.room_id,m.player_id,m.player_role into v_room.id,v_me,v_role
    from game_private.member(p_code,p_token) m;
  if v_me is null then raise exception 'Sesión inválida o expirada'; end if;
  select * into v_room from public.rooms where id=v_room.id;
  return jsonb_build_object(
    'room',jsonb_build_object('code',v_room.invite_code,'name',v_room.room_name,'status',v_room.status,
      'maxPlayers',v_room.max_players,'diceMode',v_room.dice_mode,'initialBalance',v_room.initial_balance,
      'goBonus',v_room.go_bonus,'bailAmount',v_room.bail_amount,'turnNumber',v_room.turn_number,
      'turnRolled',v_room.turn_rolled,'lastRollDouble',v_room.last_roll_double,'doublesStreak',v_room.doubles_streak,
      'currentPlayerId',v_room.current_player_id,'revision',v_room.revision,'topic',v_room.realtime_topic),
    'me',jsonb_build_object('id',v_me,'role',v_role),
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'alias',p.alias,
      'role',p.participant_role,'status',p.participant_status,'balance',p.balance,
      'position',p.board_position,'order',p.turn_order,'inJail',p.in_jail,
      'jailAttempts',p.jail_attempts,'bankrupt',p.bankrupt) order by p.joined_at,p.id)
      from public.room_players p where p.room_id=v_room.id and p.participant_status<>'left'),'[]'::jsonb),
    'spaces',coalesce((select jsonb_agg(jsonb_build_object('position',s.position,'name',s.name,
      'type',s.space_type,'group',s.color_group,'price',s.price,'rents',s.rent_schedule,
      'buildCost',s.build_cost,'mortgage',s.mortgage_value,'ownerId',s.owner_id,
      'mortgaged',s.mortgaged,'level',s.building_level) order by s.position)
      from public.room_spaces s where s.room_id=v_room.id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(e.details order by e.id desc) from (
      select x.id, jsonb_build_object('id',x.id,'type',x.event_type,'actorId',x.actor_id,
      'data',x.payload,'at',x.created_at) details
      from public.room_events x where x.room_id=v_room.id order by x.id desc limit 40
      ) e),'[]'::jsonb),
    'ledger',coalesce((select jsonb_agg(l.details order by l.id desc) from (
      select x.id,jsonb_build_object('id',x.id,'from',x.from_player,'to',x.to_player,
        'amount',x.amount,'description',x.description,'at',x.created_at) details
      from public.room_ledger x where x.room_id=v_room.id order by x.id desc limit 40
      ) l),'[]'::jsonb),
    'rolls',coalesce((select jsonb_agg(d.details order by d.id desc) from (
      select x.id,jsonb_build_object('id',x.id,'playerId',x.player_id,'d1',x.die_1,'d2',x.die_2,'from',x.from_position,'to',x.to_position,'turn',x.turn_number,'mode',x.mode) details
      from public.room_rolls x where x.room_id=v_room.id order by x.id desc limit 20
      ) d),'[]'::jsonb),
    'trades',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'from',t.from_player,
      'to',t.to_player,'giveCash',t.offered_cash,'takeCash',t.requested_cash,
      'giveSpaces',t.offered_positions,'takeSpaces',t.requested_positions,'status',t.status)
      order by t.created_at desc) from public.room_trades t where t.room_id=v_room.id and t.status='pending'),'[]'::jsonb),
    'auctions',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'position',a.position,
      'status',a.status,'minimum',a.minimum_bid,'highBid',coalesce((select max(b.amount) from public.room_bids b where b.auction_id=a.id),0),
      'highBidder',(select b.bidder_id from public.room_bids b where b.auction_id=a.id order by b.amount desc,b.id asc limit 1))
      order by a.created_at desc) from public.room_auctions a where a.room_id=v_room.id and a.status='open'),'[]'::jsonb)
  );
end;$$;

create or replace function public.game_set_space(
 p_code text,p_token text,p_position smallint,p_name text,p_type text,
 p_group text default null,p_price bigint default null,p_rents bigint[] default null,
 p_build_cost bigint default null,p_mortgage bigint default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room uuid; v_player uuid; v_role text; v_status text;
begin
  select room_id,player_id,player_role into v_room,v_player,v_role from game_private.member(p_code,p_token);
  if v_player is null or v_role<>'host' then raise exception 'Solo el anfitrión puede configurar el tablero'; end if;
  select status into v_status from public.rooms where id=v_room for update;
  if v_status<>'waiting' then raise exception 'Configura el tablero antes de comenzar'; end if;
  if p_position not between 0 and 39 then raise exception 'Posición inválida'; end if;
  if char_length(btrim(coalesce(p_name,''))) not between 1 and 80 then raise exception 'Nombre inválido'; end if;
  if p_type not in ('start','property','railroad','utility','tax','chance','community','jail','go_to_jail','parking','other') then raise exception 'Tipo de casilla inválido'; end if;
  if p_price is not null and p_price not between 0 and 10000000 then raise exception 'Precio inválido'; end if;
  if p_rents is not null and (array_length(p_rents,1) <> 6 or 0 > any(p_rents)) then raise exception 'Alquiler: se requieren seis valores no negativos'; end if;
  if p_build_cost is not null and p_build_cost not between 0 and 10000000 then raise exception 'Costo de construcción inválido'; end if;
  if p_mortgage is not null and p_mortgage not between 0 and 10000000 then raise exception 'Hipoteca inválida'; end if;
  update public.room_spaces set name=btrim(p_name),space_type=p_type,color_group=nullif(btrim(p_group),''),
    price=p_price,rent_schedule=p_rents,build_cost=p_build_cost,mortgage_value=p_mortgage
    where room_id=v_room and position=p_position;
  insert into public.room_events(room_id,actor_id,event_type,payload)
    values(v_room,v_player,'board_updated',jsonb_build_object('position',p_position));
  perform game_private.notify(v_room);
  return jsonb_build_object('ok',true);
end;$$;

create or replace function public.game_start_room(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room public.rooms%rowtype; v_player uuid; v_role text; v_n integer; v_first uuid;
begin
  select room_id,player_id,player_role into v_room.id,v_player,v_role from game_private.member(p_code,p_token);
  if v_player is null or v_role<>'host' then raise exception 'Solo el anfitrión inicia la partida'; end if;
  select * into v_room from public.rooms where id=v_room.id for update;
  if v_room.status<>'waiting' then raise exception 'La sala no está en espera'; end if;
  select count(*) into v_n from public.room_players where room_id=v_room.id and participant_status<>'left';
  if v_n<2 then raise exception 'Se necesitan al menos dos jugadores'; end if;
  with ordered as (
   select id, (row_number() over(order by (participant_role='host') desc, joined_at,id)-1)::smallint as ord
   from public.room_players where room_id=v_room.id and participant_status<>'left'
  ) update public.room_players p set turn_order=o.ord,balance=v_room.initial_balance,
     board_position=0,bankrupt=false,in_jail=false,jail_attempts=0
    from ordered o where p.id=o.id;
  select id into v_first from public.room_players where room_id=v_room.id and turn_order=0;
  update public.rooms set status='active',started_at=now(),current_player_id=v_first,
    turn_number=1,turn_rolled=false,doubles_streak=0,last_roll_double=false where id=v_room.id;
  insert into public.room_events(room_id,actor_id,event_type,payload)
    values(v_room.id,v_player,'started',jsonb_build_object('players',v_n));
  perform game_private.notify(v_room.id);
  return jsonb_build_object('ok',true);
end;$$;

create or replace function public.game_recover_host(p_code text,p_recovery text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room public.rooms%rowtype; v_host uuid; v_token text:=encode(gen_random_bytes(32),'hex');
begin
  if p_recovery is null or p_recovery !~ '^[a-f0-9]{64}$' then raise exception 'Credencial inválida'; end if;
  select * into v_room from public.rooms where invite_code=upper(btrim(p_code)) for update;
  if not found or v_room.status='finished'
     or v_room.host_credential_revoked_at is not null
     or v_room.host_credential_expires_at<=now()
     or v_room.host_credential_hash<>sha256(decode(p_recovery,'hex'))
   then raise exception 'No es posible recuperar la sesión'; end if;
  select id into v_host from public.room_players where room_id=v_room.id and participant_role='host';
  update public.room_host_sessions set revoked_at=now() where room_id=v_room.id and revoked_at is null;
  update public.room_players set session_hash=sha256(decode(v_token,'hex')),
    session_expires_at=now()+interval '30 days' where id=v_host;
  insert into public.room_host_sessions(room_id,session_token_hash,expires_at)
    values(v_room.id,sha256(decode(v_token,'hex')),now()+interval '30 days');
  return jsonb_build_object('code',v_room.invite_code,'token',v_token,'topic',v_room.realtime_topic);
end;$$;

create or replace function public.game_finish_room(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room uuid; v_player uuid; v_role text; v_status text;
begin
  select room_id,player_id,player_role into v_room,v_player,v_role from game_private.member(p_code,p_token);
  if v_player is null or v_role<>'host' then raise exception 'Solo el anfitrión finaliza la sala'; end if;
  select status into v_status from public.rooms where id=v_room for update;
  if v_status='finished' then raise exception 'Partida ya finalizada'; end if;
  if v_status='waiting' then
    update public.rooms set status='active',started_at=now(),turn_number=1 where id=v_room;
  end if;
  update public.rooms set status='finished',finished_at=now(),host_credential_revoked_at=now()
    where id=v_room;
  update public.room_host_sessions set revoked_at=now() where room_id=v_room and revoked_at is null;
  insert into public.room_events(room_id,actor_id,event_type,payload)
    values(v_room,v_player,'finished','{}');
  perform game_private.notify(v_room);
  return jsonb_build_object('ok',true);
end;$$;

create or replace function public.game_leave_room(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room uuid; v_player uuid; v_role text; v_status text;
begin
  select room_id,player_id,player_role into v_room,v_player,v_role from game_private.member(p_code,p_token);
  if v_player is null then raise exception 'Sesión inválida'; end if;
  select status into v_status from public.rooms where id=v_room for update;
  if v_status<>'waiting' or v_role='host' then raise exception 'No se puede abandonar la partida iniciada'; end if;
  update public.room_players set participant_status='left',left_at=now() where id=v_player;
  insert into public.room_events(room_id,actor_id,event_type,payload) values(v_room,v_player,'left','{}');
  perform game_private.notify(v_room);
  return jsonb_build_object('ok',true);
end;$$;

create or replace function public.game_settings(p_code text,p_token text,p_dice_mode text,p_initial_balance bigint,
 p_go_bonus bigint,p_bail_amount bigint,p_max_players smallint)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room uuid; v_player uuid; v_role text; v_count int;
begin
  select room_id,player_id,player_role into v_room,v_player,v_role from game_private.member(p_code,p_token);
  if v_player is null or v_role<>'host' then raise exception 'Solo el anfitrión puede cambiar las reglas'; end if;
  perform 1 from public.rooms where id=v_room and status='waiting' for update;
  if not found then raise exception 'La partida ya comenzó'; end if;
  select count(*) into v_count from public.room_players where room_id=v_room and participant_status<>'left';
  if p_max_players not between greatest(2,v_count) and 8 then raise exception 'Límite de jugadores inválido'; end if;
  update public.rooms set dice_mode=p_dice_mode,initial_balance=p_initial_balance,
    go_bonus=p_go_bonus,bail_amount=p_bail_amount,max_players=p_max_players
    where id=v_room;
  perform game_private.notify(v_room);
  return jsonb_build_object('ok',true);
end;$$;

revoke all on function public.game_create_room(text,text,smallint,text,bigint,bigint,bigint) from public;
revoke all on function public.game_join_room(text,text) from public;
revoke all on function public.game_get_room(text,text) from public;
revoke all on function public.game_set_space(text,text,smallint,text,text,text,bigint,bigint[],bigint,bigint) from public;
revoke all on function public.game_start_room(text,text) from public;
revoke all on function public.game_recover_host(text,text) from public;
revoke all on function public.game_finish_room(text,text) from public;
revoke all on function public.game_leave_room(text,text) from public;
revoke all on function public.game_settings(text,text,text,bigint,bigint,bigint,smallint) from public;
grant execute on function public.game_create_room(text,text,smallint,text,bigint,bigint,bigint),
 public.game_join_room(text,text),public.game_get_room(text,text),
 public.game_set_space(text,text,smallint,text,text,text,bigint,bigint[],bigint,bigint),
 public.game_start_room(text,text),public.game_recover_host(text,text),
 public.game_finish_room(text,text),public.game_leave_room(text,text),
 public.game_settings(text,text,text,bigint,bigint,bigint,smallint) to anon,authenticated;
commit;