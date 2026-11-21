-- Monopoly Perú: game state, configurable board, ledger, sessions and events
-- Version 005. Applied to Supabase monopoly_game on 2026-11-18.
-- This script is non-idempotent; do not re-run after successful execution.
begin;
alter table public.rooms
  add column dice_mode text not null default 'virtual' check (dice_mode in ('virtual','physical')),
  add column initial_balance bigint not null default 1500 check (initial_balance between 1 and 1000000),
  add column go_bonus bigint not null default 200 check (go_bonus between 0 and 100000),
  add column bail_amount bigint not null default 50 check (bail_amount between 0 and 100000),
  add column realtime_topic text not null default ('room_' || encode(gen_random_bytes(24),'hex')),
  add column current_player_id uuid,
  add column turn_number integer not null default 0 check (turn_number >= 0),
  add column turn_rolled boolean not null default false,
  add column last_roll_double boolean not null default false,
  add column doubles_streak smallint not null default 0 check (doubles_streak between 0 and 3),
  add column revision bigint not null default 0 check (revision >= 0);
create unique index rooms_realtime_topic_key on public.rooms(realtime_topic);

alter table public.room_players
  add column session_hash bytea not null check (octet_length(session_hash)=32),
  add column balance bigint not null default 0 check (balance >= 0),
  add column board_position smallint not null default 0 check (board_position between 0 and 39),
  add column turn_order smallint check (turn_order between 0 and 7),
  add column in_jail boolean not null default false,
  add column jail_attempts smallint not null default 0 check (jail_attempts between 0 and 3),
  add column bankrupt boolean not null default false,
  add column session_expires_at timestamptz not null default (now()+interval '30 days');
create unique index room_players_session_hash_key on public.room_players(session_hash);
create unique index room_players_turn_order_key on public.room_players(room_id,turn_order) where turn_order is not null;
alter table public.rooms add constraint rooms_current_player_fkey
  foreign key(current_player_id) references public.room_players(id) on delete set null;

create table public.room_spaces (
  room_id uuid not null references public.rooms(id) on delete cascade,
  position smallint not null check (position between 0 and 39),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  space_type text not null default 'other'
    check(space_type in ('start','property','railroad','utility','tax','chance','community','jail','go_to_jail','parking','other')),
  color_group text check (color_group is null or char_length(color_group) between 1 and 32),
  price bigint check(price is null or price between 0 and 10000000),
  rent_schedule bigint[] check (rent_schedule is null or (array_length(rent_schedule,1)=6 and 0 <= all(rent_schedule))),
  build_cost bigint check(build_cost is null or build_cost between 0 and 10000000),
  mortgage_value bigint check(mortgage_value is null or mortgage_value between 0 and 10000000),
  owner_id uuid references public.room_players(id) on delete set null,
  mortgaged boolean not null default false,
  building_level smallint not null default 0 check(building_level between 0 and 5),
  primary key(room_id,position),
  check (not mortgaged or building_level=0)
);
create index room_spaces_owners_idx on public.room_spaces(room_id,owner_id);
create index room_spaces_groups_idx on public.room_spaces(room_id,color_group);

create table public.room_events (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  actor_id uuid references public.room_players(id) on delete set null,
  event_type text not null check(char_length(event_type) between 2 and 60),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index room_events_room_id_idx on public.room_events(room_id,id desc);

create table public.room_ledger (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  from_player uuid references public.room_players(id),
  to_player uuid references public.room_players(id),
  amount bigint not null check(amount > 0 and amount <= 1000000000),
  description text not null check(char_length(btrim(description)) between 1 and 200),
  created_at timestamptz not null default now(),
  check(from_player is distinct from to_player)
);
create index room_ledger_room_id_idx on public.room_ledger(room_id,id desc);

create table public.room_rolls (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  player_id uuid not null references public.room_players(id),
  turn_number integer not null,
  die_1 smallint not null check(die_1 between 1 and 6),
  die_2 smallint not null check(die_2 between 1 and 6),
  mode text not null check(mode in ('virtual','physical')),
  from_position smallint not null check(from_position between 0 and 39),
  to_position smallint not null check(to_position between 0 and 39),
  created_at timestamptz not null default now()
);
create index room_rolls_room_id_idx on public.room_rolls(room_id,id desc);

create table public.room_trades (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  from_player uuid not null references public.room_players(id),
  to_player uuid not null references public.room_players(id),
  offered_cash bigint not null default 0 check(offered_cash between 0 and 1000000000),
  requested_cash bigint not null default 0 check(requested_cash between 0 and 1000000000),
  offered_positions smallint[] not null default '{}',
  requested_positions smallint[] not null default '{}',
  status text not null default 'pending' check(status in ('pending','accepted','rejected','cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (from_player <> to_player)
);
create index room_trades_room_status_idx on public.room_trades(room_id,status);

create table public.room_auctions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  position smallint not null check(position between 0 and 39),
  status text not null default 'open' check(status in ('open','closed','cancelled')),
  minimum_bid bigint not null default 1 check(minimum_bid > 0),
  winner_id uuid references public.room_players(id),
  winning_bid bigint,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create unique index room_auctions_one_open_idx on public.room_auctions(room_id) where status='open';

create table public.room_bids (
  id bigint generated always as identity primary key,
  auction_id uuid not null references public.room_auctions(id) on delete cascade,
  bidder_id uuid not null references public.room_players(id),
  amount bigint not null check(amount > 0),
  created_at timestamptz not null default now()
);
create index room_bids_auction_idx on public.room_bids(auction_id,id desc);

alter table public.room_spaces enable row level security;
alter table public.room_events enable row level security;
alter table public.room_ledger enable row level security;
alter table public.room_rolls enable row level security;
alter table public.room_trades enable row level security;
alter table public.room_auctions enable row level security;
alter table public.room_bids enable row level security;
revoke all on public.room_spaces,public.room_events,public.room_ledger,public.room_rolls,public.room_trades,public.room_auctions,public.room_bids from public,anon,authenticated;
revoke all on public.room_ledger_id_seq,public.room_events_id_seq,public.room_rolls_id_seq,public.room_bids_id_seq from public,anon,authenticated;
commit;
