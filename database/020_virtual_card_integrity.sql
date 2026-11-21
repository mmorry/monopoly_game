-- 020 | Force virtual-card resolution through the trusted server and settle tax/property landings
BEGIN;
DO $patch$
DECLARE src text; act text;
BEGIN
 act:=pg_get_functiondef('public.game_card_action(text,text,text,jsonb)'::regprocedure);
 IF position('if v_room.status<>''active'' then raise exception ''La partida no está activa'';end if;' IN act)=0 THEN
   RAISE EXCEPTION 'Unexpected game_card_action signature';END IF;
 act:=replace(act,
  'if v_room.status<>''active'' then raise exception ''La partida no está activa'';end if;',
  'if v_room.status<>''active'' then raise exception ''La partida no está activa'';end if;
   if v_room.card_mode=''virtual'' then
     raise exception ''Las cartas virtuales solo pueden finalizarse con su efecto oficial automático'';
   end if;');
 EXECUTE act;

 src:=pg_get_functiondef('public.game_finish_virtual_card(text,text,bigint)'::regprocedure);
 IF position('IF v_owner IS NOT NULL AND v_owner<>v_player.id THEN' IN src)=0 THEN
   RAISE EXCEPTION 'Unexpected virtual finish function';END IF;
 src:=replace(src,
   'IF v_owner IS NOT NULL AND v_owner<>v_player.id THEN',
   'IF EXISTS(SELECT 1 FROM public.room_spaces s WHERE s.room_id=v_room.id
       AND s.position=v_target AND s.space_type=''tax'' AND coalesce(s.price,0)>0) THEN
      SELECT price INTO v_rent FROM public.room_spaces
       WHERE room_id=v_room.id AND position=v_target;
      UPDATE public.rooms SET pending_amount=v_rent,pending_player_id=v_player.id,
       pending_to_id=null,pending_reason=''Impuesto por carta: ''||v_card.title
       WHERE id=v_room.id;
    END IF;
    IF v_owner IS NOT NULL AND v_owner<>v_player.id THEN');
 src:=replace(src,
    'ELSIF v_effect NOT IN (''move_back'') THEN',
    'ELSE');
 -- For direct card movements, use the same base rent rules as dice landings
 src:=replace(src,
   'IF EXISTS(SELECT 1 FROM public.room_spaces
           WHERE room_id=v_room.id AND position=v_target AND space_type=''railroad'') THEN',
   'IF EXISTS(SELECT 1 FROM public.room_spaces
           WHERE room_id=v_room.id AND position=v_target AND space_type=''railroad'') THEN');
 -- Accurately double undeveloped color monopoly rent when a card moves onto owned property.
 src:=replace(src,
   'END IF;
       END IF;
       IF coalesce(v_rent,0)>0 THEN',
   'END IF;
         IF EXISTS(SELECT 1 FROM public.room_spaces
           WHERE room_id=v_room.id AND position=v_target
             AND space_type=''property'' AND building_level=0 AND color_group IS NOT NULL) THEN
           SELECT count(*),count(*) FILTER(WHERE owner_id=v_owner)
             INTO v_group_size,v_owned
           FROM public.room_spaces s WHERE s.room_id=v_room.id
             AND s.space_type=''property'' AND s.color_group=(
               SELECT color_group FROM public.room_spaces WHERE room_id=v_room.id AND position=v_target);
           IF v_group_size>1 AND v_owned=v_group_size THEN v_rent:=v_rent*2;END IF;
         END IF;
       END IF;
       IF coalesce(v_rent,0)>0 THEN');
 EXECUTE src;
END $patch$;
COMMIT;