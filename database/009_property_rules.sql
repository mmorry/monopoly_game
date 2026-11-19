-- Monopoly Perú | Version 009 | Property ownership, mortgage and building inventory
begin;
create or replace function public.game_property(p_code text,p_token text,p_action text,p_position smallint)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room public.rooms%rowtype; v_me uuid; v_role text; v_p public.room_players%rowtype;
 v_s public.room_spaces%rowtype; v_group_size int; v_owned int; v_min int; v_max int;
 v_any_mortgaged int; v_houses int; v_hotels int; v_amount bigint; v_new_level int;
begin
 select room_id,player_id,player_role into v_room.id,v_me,v_role from game_private.member(p_code,p_token);
 if v_me is null then raise exception 'Sesión inválida';end if;
 select * into v_room from public.rooms where id=v_room.id for update;
 if v_room.status<>'active' then raise exception 'Partida no activa';end if;
 select * into v_p from public.room_players where id=v_me for update;
 if v_p.bankrupt then raise exception 'Jugador en bancarrota';end if;
 select * into v_s from public.room_spaces where room_id=v_room.id and position=p_position for update;
 if not found or v_s.space_type not in ('property','railroad','utility') then raise exception 'Casilla no comprable';end if;

 if p_action='buy' then
   if v_room.current_player_id<>v_me or not v_room.turn_rolled or v_p.board_position<>p_position
     then raise exception 'Solo puedes comprar la casilla donde acabas de caer';end if;
   if v_room.pending_amount>0 then raise exception 'Primero paga la deuda';end if;
   if v_s.owner_id is not null then raise exception 'La propiedad ya tiene dueño';end if;
   if v_s.price is null or v_s.price<=0 then raise exception 'Configura el precio de esta propiedad';end if;
   if v_p.balance<v_s.price then raise exception 'No tienes saldo suficiente';end if;
   update public.room_players set balance=balance-v_s.price where id=v_me;
   update public.room_spaces set owner_id=v_me where room_id=v_room.id and position=p_position;
   insert into public.room_ledger(room_id,from_player,amount,description)
     values(v_room.id,v_me,v_s.price,'Compra: '||v_s.name);
   v_amount:=v_s.price;
 elsif p_action='mortgage' then
   if v_s.owner_id is distinct from v_me or v_s.mortgaged then raise exception 'No puedes hipotecar esta propiedad';end if;
   if v_s.building_level<>0 then raise exception 'Primero vende los edificios';end if;
   if v_s.space_type='property' and v_s.color_group is not null and exists (
     select 1 from public.room_spaces where room_id=v_room.id and color_group=v_s.color_group
       and building_level>0
   ) then raise exception 'Vende todas las construcciones del grupo';end if;
   v_amount:=coalesce(v_s.mortgage_value,v_s.price/2);
   if v_amount is null or v_amount<=0 then raise exception 'No hay valor de hipoteca configurado';end if;
   update public.room_spaces set mortgaged=true where room_id=v_room.id and position=p_position;
   update public.room_players set balance=balance+v_amount where id=v_me;
   insert into public.room_ledger(room_id,to_player,amount,description)
     values(v_room.id,v_me,v_amount,'Hipoteca: '||v_s.name);
 elsif p_action='unmortgage' then
   if v_s.owner_id is distinct from v_me or not v_s.mortgaged then raise exception 'Esta propiedad no está hipotecada a tu nombre';end if;
   v_amount:=((coalesce(v_s.mortgage_value,v_s.price/2)*11)+9)/10;
   if v_amount is null or v_amount<=0 then raise exception 'Valor de hipoteca no configurado';end if;
   if v_p.balance<v_amount then raise exception 'Saldo insuficiente para levantar hipoteca';end if;
   update public.room_spaces set mortgaged=false where room_id=v_room.id and position=p_position;
   update public.room_players set balance=balance-v_amount where id=v_me;
   insert into public.room_ledger(room_id,from_player,amount,description)
     values(v_room.id,v_me,v_amount,'Levantamiento de hipoteca: '||v_s.name);
 elsif p_action in ('build','sell_building') then
   if v_s.space_type<>'property' or v_s.owner_id is distinct from v_me then
     raise exception 'No eres dueño de este terreno';end if;
   if v_s.color_group is null or v_s.build_cost is null or v_s.build_cost<=0 then
     raise exception 'Configura el grupo de color y el precio de construcción';end if;
   select count(*),count(*) filter(where owner_id=v_me),min(building_level),max(building_level),
      count(*) filter(where mortgaged)
     into v_group_size,v_owned,v_min,v_max,v_any_mortgaged
     from public.room_spaces where room_id=v_room.id and color_group=v_s.color_group
       and space_type='property';
   if v_group_size<2 or v_group_size<>v_owned then raise exception 'Debes poseer todo el grupo de color';end if;
   if v_any_mortgaged>0 then raise exception 'No puedes construir con propiedades hipotecadas';end if;
   select coalesce(sum(case when building_level<5 then building_level else 0 end),0),
     count(*) filter(where building_level=5)
     into v_houses,v_hotels from public.room_spaces where room_id=v_room.id;
   if p_action='build' then
     if v_s.building_level>=5 then raise exception 'Ya hay un hotel';end if;
     if v_s.building_level<>v_min then raise exception 'Debes construir uniformemente en todo el color';end if;
     if v_s.building_level=4 and v_hotels>=12 then raise exception 'No quedan hoteles en el banco';end if;
     if v_s.building_level<4 and v_houses>=32 then raise exception 'No quedan casas en el banco';end if;
     v_amount:=v_s.build_cost;
     if v_p.balance<v_amount then raise exception 'Saldo insuficiente para construir';end if;
     v_new_level:=v_s.building_level+1;
     update public.room_players set balance=balance-v_amount where id=v_me;
     insert into public.room_ledger(room_id,from_player,amount,description)
       values(v_room.id,v_me,v_amount,'Construcción: '||v_s.name);
   else
     if v_s.building_level<=0 then raise exception 'No hay construcciones que vender';end if;
     if v_s.building_level<>v_max then raise exception 'Debes vender uniformemente en el grupo';end if;
     if v_s.building_level=5 and v_houses+4>32 then raise exception 'No hay cuatro casas disponibles para sustituir el hotel';end if;
     v_amount:=v_s.build_cost/2;
     v_new_level:=v_s.building_level-1;
     update public.room_players set balance=balance+v_amount where id=v_me;
     if v_amount>0 then
       insert into public.room_ledger(room_id,to_player,amount,description)
         values(v_room.id,v_me,v_amount,'Venta de construcción: '||v_s.name);
     end if;
   end if;
   update public.room_spaces set building_level=v_new_level where room_id=v_room.id and position=p_position;
 else
   raise exception 'Acción patrimonial inválida';
 end if;
 insert into public.room_events(room_id,actor_id,event_type,payload)
   values(v_room.id,v_me,p_action,jsonb_build_object('position',p_position,'amount',v_amount));
 perform game_private.notify(v_room.id);
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.game_property(text,text,text,smallint) from public;
grant execute on function public.game_property(text,text,text,smallint) to anon,authenticated;
commit;