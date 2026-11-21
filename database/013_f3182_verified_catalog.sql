-- Monopoly Perú F3182 | SQL 013
-- Catálogo con evidencia comprobada. NO se inventan posiciones, precios o alquileres.
-- Edición F3182 (2022) distinta de Monopoly Perú 2010.
BEGIN;

CREATE TABLE public.monopoly_editions (
  sku text PRIMARY KEY,
  display_name text NOT NULL,
  board_spaces smallint NOT NULL CHECK (board_spaces BETWEEN 1 AND 100),
  title_cards smallint NOT NULL CHECK (title_cards BETWEEN 1 AND 100),
  landmarks smallint NOT NULL CHECK (landmarks BETWEEN 1 AND 100),
  min_players smallint NOT NULL,
  max_players smallint NOT NULL CHECK (max_players >= min_players),
  chance_deck_name text NOT NULL,
  community_deck_name text NOT NULL,
  chance_deck_size smallint NOT NULL CHECK (chance_deck_size >= 0),
  community_deck_size smallint NOT NULL CHECK (community_deck_size >= 0),
  verification_state text NOT NULL CHECK(verification_state IN ('partial','complete')),
  notes text NOT NULL
);

INSERT INTO public.monopoly_editions
 (sku,display_name,board_spaces,title_cards,landmarks,min_players,max_players,
 chance_deck_name,community_deck_name,chance_deck_size,community_deck_size,
 verification_state,notes)
VALUES
 ('F3182','Monopoly Perú · edición renovada 2022',40,28,22,2,6,
  'El Chamán','La Tómbola',16,16,'partial',
  'Nombres de destinos verificados en fuentes de 2022, pero sin casillas ni valores individuales comprobados. No importar datos de Monopoly Perú 2010.');

CREATE TABLE public.monopoly_edition_items (
  edition_sku text NOT NULL REFERENCES public.monopoly_editions(sku) ON DELETE RESTRICT,
  item_key text NOT NULL,
  display_name text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('landmark','chance_deck','community_deck')),
  board_position smallint CHECK(board_position BETWEEN 0 AND 39),
  purchase_price bigint CHECK(purchase_price >= 0),
  rent_schedule bigint[] CHECK(rent_schedule IS NULL OR (array_length(rent_schedule,1)=6 AND 0 <= ALL(rent_schedule))),
  building_cost bigint CHECK(building_cost >= 0),
  mortgage_value bigint CHECK(mortgage_value >= 0),
  evidence_url text NOT NULL,
  verified_scope text NOT NULL CHECK(verified_scope IN ('name_only','position','full_card')),
  PRIMARY KEY(edition_sku,item_key),
  CHECK ((verified_scope='name_only' AND board_position IS NULL
          AND purchase_price IS NULL AND rent_schedule IS NULL AND building_cost IS NULL AND mortgage_value IS NULL)
         OR verified_scope <> 'name_only')
);
CREATE UNIQUE INDEX monopoly_edition_items_unique_position
 ON public.monopoly_edition_items(edition_sku,board_position) WHERE board_position IS NOT NULL;

INSERT INTO public.monopoly_edition_items
 (edition_sku,item_key,display_name,kind,evidence_url,verified_scope)
VALUES
 ('F3182','laguna_choclococha','Laguna Choclococha','landmark',
   'https://peru.info/es-pe/turismo/blogperu/3/18/-recorre-el-pais-como-jugando--hasbro-lanza-monopoly-peru-con-los-mejores-destinos-a-nivel-nacional','name_only'),
 ('F3182','bosque_piedras_pampachiri','Bosque de Piedras de Pampachiri','landmark',
   'https://peru.info/es-pe/turismo/blogperu/3/18/-recorre-el-pais-como-jugando--hasbro-lanza-monopoly-peru-con-los-mejores-destinos-a-nivel-nacional','name_only'),
 ('F3182','nevado_huascaran','Nevado Huascarán','landmark',
   'https://peru.info/es-pe/turismo/blogperu/3/18/-recorre-el-pais-como-jugando--hasbro-lanza-monopoly-peru-con-los-mejores-destinos-a-nivel-nacional','name_only'),
 ('F3182','kuelap','Complejo Arqueológico de Kuélap','landmark',
   'https://peru.info/es-pe/turismo/blogperu/3/18/-recorre-el-pais-como-jugando--hasbro-lanza-monopoly-peru-con-los-mejores-destinos-a-nivel-nacional','name_only'),
 ('F3182','machu_picchu','Machu Picchu','landmark',
   'https://andina.pe/agencia/noticia-monopoly-lanzan-edicion-destinos-turisticos-peruanos-888208.aspx','name_only'),
 ('F3182','senor_sipan','Señor de Sipán','landmark',
   'https://andina.pe/agencia/noticia-monopoly-lanzan-edicion-destinos-turisticos-peruanos-888208.aspx','name_only'),
 ('F3182','isla_uros','Isla de los Uros','landmark',
   'https://diadejuegos.pe/familiares/8781-monopoly-peru.html','name_only'),
 ('F3182','el_chaman','El Chamán','chance_deck',
   'https://andina.pe/agencia/noticia-monopoly-lanzan-edicion-destinos-turisticos-peruanos-888208.aspx','name_only'),
 ('F3182','la_tombola','La Tómbola','community_deck',
   'https://andina.pe/agencia/noticia-monopoly-lanzan-edicion-destinos-turisticos-peruanos-888208.aspx','name_only');

ALTER TABLE public.rooms
 ADD COLUMN edition_sku text NOT NULL DEFAULT 'F3182'
 REFERENCES public.monopoly_editions(sku);

-- The F3182 uses 2-6 players. Keep game engine constraints aligned.
DO $do$
DECLARE src text; f regprocedure;
BEGIN
 f := 'public.game_create_room(text,text,smallint,text,bigint,bigint,bigint)'::regprocedure;
 src := pg_get_functiondef(f::oid);
 IF position('p_max_players not between 2 and 8' IN src)=0 THEN
   RAISE EXCEPTION 'Unexpected game_create_room body. Review manually.';
 END IF;
 EXECUTE replace(src,'p_max_players not between 2 and 8','p_max_players not between 2 and 6');

 f := 'public.game_settings(text,text,text,bigint,bigint,bigint,smallint)'::regprocedure;
 src := pg_get_functiondef(f::oid);
 IF position('greatest(2,v_count) and 8' IN src)=0 THEN
   RAISE EXCEPTION 'Unexpected game_settings body. Review manually.';
 END IF;
 EXECUTE replace(src,'greatest(2,v_count) and 8','greatest(2,v_count) and 6');
END;
$do$;

-- Names of the F3182 decks are confirmed; their position still uses the
-- existing 40-position standard board template, NOT a verified F3182 map.
CREATE OR REPLACE FUNCTION game_private.label_f3182_deck()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $body$
DECLARE sku text;
BEGIN
 SELECT r.edition_sku INTO sku FROM public.rooms r WHERE r.id=NEW.room_id;
 IF sku='F3182' AND NEW.name LIKE 'Casilla %' THEN
   IF NEW.space_type='chance' THEN NEW.name:='El Chamán'; END IF;
   IF NEW.space_type='community' THEN NEW.name:='La Tómbola'; END IF;
 END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION game_private.label_f3182_deck() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER room_spaces_f3182_deck
 BEFORE INSERT ON public.room_spaces
 FOR EACH ROW EXECUTE FUNCTION game_private.label_f3182_deck();

UPDATE public.room_spaces s
 SET name=CASE s.space_type WHEN 'chance' THEN 'El Chamán' ELSE 'La Tómbola' END
 FROM public.rooms r WHERE r.id=s.room_id AND r.edition_sku='F3182'
 AND s.space_type IN ('chance','community') AND s.name LIKE 'Casilla %';

ALTER TABLE public.monopoly_editions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monopoly_edition_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.monopoly_editions, public.monopoly_edition_items FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.monopoly_editions, public.monopoly_edition_items TO anon, authenticated;
CREATE POLICY f3182_public_edition_read ON public.monopoly_editions
 FOR SELECT TO anon,authenticated USING (true);
CREATE POLICY f3182_public_catalog_read ON public.monopoly_edition_items
 FOR SELECT TO anon,authenticated USING (true);

CREATE FUNCTION public.game_edition_reference(p_sku text DEFAULT 'F3182')
RETURNS jsonb LANGUAGE sql SECURITY INVOKER STABLE SET search_path = ''
AS $body$
SELECT jsonb_build_object(
  'sku',e.sku,'name',e.display_name,'boardSpaces',e.board_spaces,
  'titleCards',e.title_cards,'landmarks',e.landmarks,
  'minPlayers',e.min_players,'maxPlayers',e.max_players,
  'decks',jsonb_build_object('chance',e.chance_deck_name,'community',e.community_deck_name,
    'chanceCount',e.chance_deck_size,'communityCount',e.community_deck_size),
  'verificationState',e.verification_state,
  'notes',e.notes,
  'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
     'key',i.item_key,'name',i.display_name,'kind',i.kind,
     'position',i.board_position,'price',i.purchase_price,
     'rents',i.rent_schedule,'source',i.evidence_url,'scope',i.verified_scope)
     ORDER BY i.kind,i.display_name)
     FROM public.monopoly_edition_items i WHERE i.edition_sku=e.sku),'[]'::jsonb)
) FROM public.monopoly_editions e WHERE e.sku=p_sku;
$body$;
REVOKE ALL ON FUNCTION public.game_edition_reference(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_edition_reference(text) TO anon,authenticated;
COMMIT;