-- Monopoly Perú | Version 011 | Ensure room cascade removes complete game history
-- Original player FKs in 005 had implicit NO ACTION and blocked room cleanup.
begin;
alter table public.room_ledger
 drop constraint room_ledger_from_player_fkey,
 add constraint room_ledger_from_player_fkey foreign key(from_player) references public.room_players(id) on delete cascade,
 drop constraint room_ledger_to_player_fkey,
 add constraint room_ledger_to_player_fkey foreign key(to_player) references public.room_players(id) on delete cascade;
alter table public.room_rolls
 drop constraint room_rolls_player_id_fkey,
 add constraint room_rolls_player_id_fkey foreign key(player_id) references public.room_players(id) on delete cascade;
alter table public.room_trades
 drop constraint room_trades_from_player_fkey,
 add constraint room_trades_from_player_fkey foreign key(from_player) references public.room_players(id) on delete cascade,
 drop constraint room_trades_to_player_fkey,
 add constraint room_trades_to_player_fkey foreign key(to_player) references public.room_players(id) on delete cascade;
alter table public.room_auctions
 drop constraint room_auctions_winner_id_fkey,
 add constraint room_auctions_winner_id_fkey foreign key(winner_id) references public.room_players(id) on delete set null;
alter table public.room_bids
 drop constraint room_bids_bidder_id_fkey,
 add constraint room_bids_bidder_id_fkey foreign key(bidder_id) references public.room_players(id) on delete cascade;
commit;