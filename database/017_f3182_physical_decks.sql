-- 017 | Monopoly Perú F3182: 32 physical card catalogue, 16 per deck.
-- Source: user's photographs 458531,458530,458528,458529.
-- Card numbers here are INTERNAL catalogue sequence, not printed card identifiers.
-- Repeated "nearest refuge" cards remain two distinct copies.
-- Effect metadata describes rules; game_card_action remains host-confirmed.
BEGIN;
CREATE TABLE public.monopoly_f3182_cards (
  edition_sku text NOT NULL REFERENCES public.monopoly_editions(sku),
  deck text NOT NULL CHECK(deck IN ('chaman','tombola')),
  catalog_number smallint NOT NULL CHECK(catalog_number BETWEEN 1 AND 16),
  title text NOT NULL,
  instruction text NOT NULL,
  effect_code text NOT NULL CHECK(effect_code IN
    ('bank_receive','bank_pay','move','move_back','move_pass_go','move_collect',
     'nearest_refuge','nearest_utility','repairs','jail','jail_free','pay_each','collect_each')),
  effect_value bigint,
  secondary_value bigint,
  hold_until_used boolean NOT NULL DEFAULT false,
  photo_evidence text NOT NULL,
  PRIMARY KEY(edition_sku,deck,catalog_number),
  CHECK((effect_code='jail_free')=(hold_until_used)),
  CHECK(effect_value IS NULL OR effect_value>=0),
  CHECK(secondary_value IS NULL OR secondary_value>=0)
);
INSERT INTO public.monopoly_f3182_cards
  (edition_sku,deck,catalog_number,title,instruction,effect_code,effect_value,secondary_value,hold_until_used,photo_evidence)
VALUES
('F3182','chaman',1,'Retrocede tres casillas','Retrocede tres casillas desde tu posición actual.','move_back',3,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',2,'Avanza a Señor de Sipán','Dirígete a Señor de Sipán.','move',39,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',3,'Multa por ciclovía','Pagas M 15 por invadir la ciclovía.','bank_pay',15,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',4,'Refugio más próximo (A)','Avanza al refugio más cercano; si tiene dueño, paga el doble del alquiler normal.','nearest_refuge',NULL,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',5,'Área protegida próxima','Avanza al área natural protegida más cercana; si tiene dueño, lanza los dados y paga diez veces el resultado.','nearest_utility',10,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',6,'Avanza a Playa Los Órganos','Muévete a Playa Los Órganos; cobra M 200 si cruzas Salida.','move_pass_go',27,200,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',7,'Reparaciones generales','Paga M 25 por cada casa y M 100 por cada hotel que tengas.','repairs',25,100,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',8,'Gratificación','Recibe M 150 del banco.','bank_receive',150,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',9,'Baño de florecimiento','Avanza a Salida y recibe M 200.','move_collect',0,200,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',10,'Avanza al refugio del colibrí','Avanza al Refugio del Colibrí Cola de Espátula; si pasas por Salida, recibe M 200.','move_pass_go',15,200,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',11,'Directo a la cárcel','Ve directamente a la cárcel. No cobres por Salida.','jail',10,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',12,'Pollada bailable','Recibe M 50 de la banca.','bank_receive',50,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',13,'Padrino de la yunza','Paga M 50 a cada uno de los demás jugadores.','pay_each',50,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',14,'Viaje a Laguna Azul','Avanza a Laguna Azul y recibe M 200 si pasas por Salida.','move_pass_go',13,200,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',15,'Refugio más próximo (B)','Avanza al refugio más cercano; si tiene dueño, paga el doble del alquiler normal.','nearest_refuge',NULL,NULL,false,'458531.jpg / 458530.jpg'),
('F3182','chaman',16,'Salir de la cárcel gratis','Conserva esta tarjeta hasta usarla para salir de la cárcel o venderla.','jail_free',NULL,NULL,true,'458531.jpg / 458530.jpg'),
('F3182','tombola',1,'Concurso de baile','Recibe M 25 de la banca.','bank_receive',25,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',2,'Tour gastronómico','Paga M 50 al banco.','bank_pay',50,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',3,'Directo a la cárcel','Dirígete a la cárcel sin cobrar al pasar por Salida.','jail',10,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',4,'Concurso de fotografía','Recibe M 20 de la banca.','bank_receive',20,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',5,'Premio de lotería','Recibe M 200 de la banca.','bank_receive',200,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',6,'Rendimiento de ahorros','Recibe M 100 de la banca.','bank_receive',100,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',7,'Avanza a Salida','Avanza a Salida y recibe M 200.','move_collect',0,200,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',8,'Ingreso extra','Recibe M 100 de la banca.','bank_receive',100,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',9,'Tómbola del colegio','Recibe M 10 de la banca.','bank_receive',10,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',10,'Celebración de cumpleaños','Recibe M 10 de cada uno de los demás jugadores.','collect_each',10,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',11,'Emprendimiento','Recibe M 50 de la banca.','bank_receive',50,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',12,'Salir de la cárcel gratis','Conserva esta tarjeta hasta usarla para salir de la cárcel o venderla.','jail_free',NULL,NULL,true,'458528.jpg / 458529.jpg'),
('F3182','tombola',13,'Cobro de la junta','Recibe M 100 de la banca.','bank_receive',100,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',14,'Visita al médico','Paga M 50 al banco.','bank_pay',50,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',15,'Boleto para viajar','Paga M 100 al banco.','bank_pay',100,NULL,false,'458528.jpg / 458529.jpg'),
('F3182','tombola',16,'Reparaciones en el barrio','Paga M 40 por cada casa y M 115 por cada hotel que tengas.','repairs',40,115,false,'458528.jpg / 458529.jpg');
ALTER TABLE public.monopoly_f3182_cards ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.monopoly_f3182_cards FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.monopoly_f3182_cards TO anon,authenticated;
CREATE POLICY f3182_physical_deck_read ON public.monopoly_f3182_cards
FOR SELECT TO anon,authenticated USING(true);

CREATE FUNCTION public.game_f3182_cards(p_deck text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER STABLE SET search_path=''
AS $body$
SELECT coalesce(jsonb_agg(jsonb_build_object(
  'deck',deck,'number',catalog_number,'title',title,
  'instruction',instruction,'effect',effect_code,
  'value',effect_value,'secondary',secondary_value,
  'hold',hold_until_used
) ORDER BY deck,catalog_number),'[]'::jsonb)
FROM public.monopoly_f3182_cards
WHERE edition_sku='F3182' AND (p_deck IS NULL OR deck=p_deck);
$body$;
REVOKE ALL ON FUNCTION public.game_f3182_cards(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_f3182_cards(text) TO anon,authenticated;
COMMIT;
