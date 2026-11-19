-- Monopoly Perú | Version 012 | Runtime board configuration for unowned spaces
-- An existing owner freezes the purchased property terms.
begin;
CREATE OR REPLACE FUNCTION public.game_set_space(p_code text, p_token text, p_position smallint, p_name text, p_type text, p_group text DEFAULT NULL::text, p_price bigint DEFAULT NULL::bigint, p_rents bigint[] DEFAULT NULL::bigint[], p_build_cost bigint DEFAULT NULL::bigint, p_mortgage bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_room uuid; v_player uuid; v_role text; v_status text;
begin
  select room_id,player_id,player_role into v_room,v_player,v_role from game_private.member(p_code,p_token);
  if v_player is null or v_role<>'host' then raise exception 'Solo el anfitrión puede configurar el tablero'; end if;
  select status into v_status from public.rooms where id=v_room for update;
  if v_status not in ('waiting','active') then raise exception 'Solo puedes editar salas abiertas o partidas activas'; end if;
  if p_position not between 0 and 39 then raise exception 'Posición inválida'; end if;
  if char_length(btrim(coalesce(p_name,''))) not between 1 and 80 then raise exception 'Nombre inválido'; end if;
  if p_type not in ('start','property','railroad','utility','tax','chance','community','jail','go_to_jail','parking','other') then raise exception 'Tipo de casilla inválido'; end if;
  if p_price is not null and p_price not between 0 and 10000000 then raise exception 'Precio inválido'; end if;
  if p_rents is not null and (array_length(p_rents,1) <> 6 or 0 > any(p_rents)) then raise exception 'Alquiler: se requieren seis valores no negativos'; end if;
  if p_build_cost is not null and p_build_cost not between 0 and 10000000 then raise exception 'Costo de construcción inválido'; end if;
  if p_mortgage is not null and p_mortgage not between 0 and 10000000 then raise exception 'Hipoteca inválida'; end if;
  update public.room_spaces set name=btrim(p_name),space_type=p_type,color_group=nullif(btrim(p_group),''),
    price=p_price,rent_schedule=p_rents,build_cost=p_build_cost,mortgage_value=p_mortgage
    where room_id=v_room and position=p_position
      and (v_status='waiting' or owner_id is null);
  if not found then raise exception 'No puedes modificar una propiedad que ya tiene dueño'; end if;
  insert into public.room_events(room_id,actor_id,event_type,payload)
    values(v_room,v_player,'board_updated',jsonb_build_object('position',p_position));
  perform game_private.notify(v_room);
  return jsonb_build_object('ok',true);
end;$function$
;
revoke all on function public.game_set_space(text,text,smallint,text,text,text,bigint,bigint[],bigint,bigint) from public;
grant execute on function public.game_set_space(text,text,smallint,text,text,text,bigint,bigint[],bigint,bigint) to anon, authenticated;
commit;
