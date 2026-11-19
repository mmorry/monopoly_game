-- Monopoly Perú database schema
-- Version: 001
-- Execute manually in Supabase SQL Editor.
-- This script does not create client access policies. Server-side operations will be
-- introduced later with their own authorization model.

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  invite_code text not null,
  room_name text,
  status text not null default 'waiting',
  max_players smallint not null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,

  constraint rooms_invite_code_format_check
    check (invite_code ~ '^[A-Z0-9]{6,16}$'),
  constraint rooms_invite_code_uppercase_check
    check (invite_code = upper(invite_code)),
  constraint rooms_invite_code_key unique (invite_code),
  constraint rooms_name_length_check
    check (room_name is null or char_length(btrim(room_name)) between 1 and 48),
  constraint rooms_status_check
    check (status in ('waiting', 'active', 'finished')),
  constraint rooms_max_players_check
    check (max_players between 2 and 8),
  constraint rooms_status_timestamps_check
    check (
      (status = 'waiting' and started_at is null and finished_at is null)
      or (status = 'active' and started_at is not null and finished_at is null)
      or (status = 'finished' and started_at is not null and finished_at is not null and finished_at >= started_at)
    )
);

create table public.room_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null,
  alias text not null,
  participant_role text not null default 'player',
  participant_status text not null default 'connected',
  token text,
  joined_at timestamptz not null default now(),
  left_at timestamptz,

  constraint room_players_room_id_fkey
    foreign key (room_id)
    references public.rooms (id)
    on delete cascade,
  constraint room_players_alias_length_check
    check (char_length(btrim(alias)) between 2 and 24),
  constraint room_players_role_check
    check (participant_role in ('host', 'player')),
  constraint room_players_status_check
    check (participant_status in ('connected', 'disconnected', 'left')),
  constraint room_players_token_length_check
    check (token is null or char_length(btrim(token)) between 1 and 32),
  constraint room_players_left_status_check
    check (
      (participant_status = 'left' and left_at is not null)
      or (participant_status in ('connected', 'disconnected') and left_at is null)
    )
);

-- Supports room lifecycle listings and cleanup queries.
create index rooms_status_created_at_idx
  on public.rooms (status, created_at);

-- Supports loading all participants of a room and their presence state.
create index room_players_room_status_idx
  on public.room_players (room_id, participant_status);

-- One alias and one selected token per room. Names and tokens can be reused in other rooms.
create unique index room_players_room_alias_key
  on public.room_players (room_id, lower(alias));

create unique index room_players_room_token_key
  on public.room_players (room_id, token)
  where token is not null;

-- Exactly one host can be recorded for a room. The room creation flow must insert
-- the host participant in the same transaction as the room.
create unique index room_players_one_host_per_room_key
  on public.room_players (room_id)
  where participant_role = 'host';

-- RLS and grants are set together. No browser role receives data access yet:
-- future server-side operations must add narrowly scoped grants and policies.
alter table public.rooms enable row level security;
alter table public.room_players enable row level security;

revoke all on table public.rooms from anon, authenticated;
revoke all on table public.room_players from anon, authenticated;
