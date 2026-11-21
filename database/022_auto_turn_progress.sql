-- 022: Safely auto-advance after completed actions.
-- Never skip auctions, debts, unresolved cards, unpurchased land, or the extra throw for doubles.
BEGIN;
CREATE OR REPLACE FUNCTION game_private.advance_if_settled(p_code text,p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE rid uuid; pid uuid; rr public.rooms%rowtype;
BEGIN
 SELECT room_id,player_id INTO rid,pid FROM game_private.member(p_code,p_token);
 IF pid IS NULL THEN RETURN;END IF;
 SELECT * INTO rr FROM public.rooms WHERE id=rid;
 IF rr.status<>'active' OR rr.current_player_id IS DISTINCT FROM pid OR NOT rr.turn_rolled OR rr.pending_amount>0
 THEN RETURN;END IF;
 IF EXISTS(SELECT 1 FROM public.room_auctions WHERE room_id=rid AND status='open')
 OR EXISTS(SELECT 1 FROM public.room_card_challenges WHERE room_id=rid AND player_id=pid AND outcome='pending')
 THEN RETURN;END IF;
 IF EXISTS(
  SELECT 1 FROM public.room_players p JOIN public.room_spaces s
    ON s.room_id=p.room_id AND s.position=p.board_position
  WHERE p.id=pid AND NOT p.in_jail AND s.owner_id IS NULL
    AND s.space_type IN ('property','railroad','utility') AND coalesce(s.price,0)>0
    AND EXISTS(SELECT 1 FROM public.room_rolls d WHERE d.room_id=rid AND d.player_id=pid
               AND d.turn_number=rr.turn_number AND d.to_position=s.position)
    AND NOT EXISTS(
      SELECT 1 FROM public.room_auctions a WHERE a.room_id=rid AND a.position=s.position
      AND a.status IN ('closed','cancelled')
      AND a.created_at >= (
        SELECT min(d.created_at) FROM public.room_rolls d WHERE d.room_id=rid
        AND d.player_id=pid AND d.turn_number=rr.turn_number AND d.to_position=s.position))
 ) THEN RETURN; END IF;
 PERFORM public.game_action(p_code,p_token,'end_turn','{}'::jsonb);
END;$fn$;
REVOKE ALL ON FUNCTION game_private.advance_if_settled(text,text) FROM PUBLIC,anon,authenticated;

DO $patch$
DECLARE src text;
BEGIN
 -- End turn from completed dice/payments, not from unrelated bank transfers or corrections.
 src:=pg_get_functiondef('public.game_action(text,text,text,jsonb)'::regprocedure);
 IF position('perform game_private.notify(v_room.id);' in src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_action end';END IF;
 src:=replace(src,'perform game_private.notify(v_room.id);',
 'if p_action in (''roll'',''pay_due'') then
     perform game_private.advance_if_settled(p_code,p_token);
   end if;
   perform game_private.notify(v_room.id);');
 EXECUTE src;
 src:=pg_get_functiondef('public.game_property(text,text,text,smallint)'::regprocedure);
 IF position('perform game_private.notify(v_room.id);' in src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_property end';END IF;
 src:=replace(src,'perform game_private.notify(v_room.id);',
 'if p_action=''buy'' then perform game_private.advance_if_settled(p_code,p_token);end if;
   perform game_private.notify(v_room.id);');
 EXECUTE src;
 src:=pg_get_functiondef('public.game_auction(text,text,text,jsonb)'::regprocedure);
 IF position('perform game_private.notify(v_room);' in src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_auction end';END IF;
 src:=replace(src,'perform game_private.notify(v_room);',
 'if p_action in (''close'',''cancel'') then
     perform game_private.advance_if_settled(p_code,p_token);
   end if;
   perform game_private.notify(v_room);');
 EXECUTE src;
 src:=pg_get_functiondef('public.game_card_action(text,text,text,jsonb)'::regprocedure);
 IF position('perform game_private.notify(v_room.id);' in src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_card_action end';END IF;
 src:=replace(src,'perform game_private.notify(v_room.id);',
 'if p_action=''resolve'' then perform game_private.advance_if_settled(p_code,p_token);end if;
   perform game_private.notify(v_room.id);');
 EXECUTE src;
 src:=pg_get_functiondef('public.game_finish_virtual_card(text,text,bigint)'::regprocedure);
 IF position('PERFORM game_private.notify(v_room.id);' in src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_finish_virtual_card end';END IF;
 src:=replace(src,'PERFORM game_private.notify(v_room.id);',
 'PERFORM game_private.advance_if_settled(p_code,p_token);
   PERFORM game_private.notify(v_room.id);');
 EXECUTE src;
END $patch$;
COMMIT;