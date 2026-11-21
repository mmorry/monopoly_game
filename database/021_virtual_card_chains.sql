-- 021 | Chain card draws on card-landed chance/community squares; use jail passes only on your turn
BEGIN;
DO $patch$
DECLARE src text;
BEGIN
 src:=pg_get_functiondef('public.game_finish_virtual_card(text,text,bigint)'::regprocedure);
 IF position('PERFORM game_private.notify(v_room.id);' IN src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_finish_virtual_card function';END IF;
 src:=replace(src,
 'PERFORM game_private.notify(v_room.id);',
 'IF v_has_move AND v_effect<>''jail'' AND EXISTS(
    SELECT 1 FROM public.room_spaces
    WHERE room_id=v_room.id AND position=v_target AND space_type IN (''chance'',''community'')
  ) THEN
    INSERT INTO public.room_card_challenges(room_id,player_id,turn_number,position,deck,source_type)
    SELECT v_room.id,v_challenge.player_id,v_room.turn_number,v_target,
      CASE WHEN space_type=''chance'' THEN ''chaman'' ELSE ''tombola'' END,''dice''
    FROM public.room_spaces WHERE room_id=v_room.id AND position=v_target;
  END IF;
  PERFORM game_private.notify(v_room.id);');
 EXECUTE src;

 src:=pg_get_functiondef('public.game_use_jail_pass(text,text,text)'::regprocedure);
 IF position('PERFORM 1 FROM public.rooms WHERE id=v_room AND status=''active'' FOR UPDATE;' IN src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_use_jail_pass';END IF;
 src:=replace(src,
 'PERFORM 1 FROM public.rooms WHERE id=v_room AND status=''active'' FOR UPDATE;',
 'PERFORM 1 FROM public.rooms WHERE id=v_room AND status=''active''
   AND current_player_id=v_me FOR UPDATE;');
 src:=replace(src,
 'IF NOT FOUND THEN RAISE EXCEPTION ''La partida no está activa'';END IF;',
 'IF NOT FOUND THEN RAISE EXCEPTION ''Solo puedes usar tu tarjeta en tu turno activo'';END IF;');
 EXECUTE src;
END $patch$;
COMMIT;