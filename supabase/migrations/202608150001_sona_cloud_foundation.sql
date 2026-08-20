-- Sona cloud foundation: accounts, shared music spaces and per-user state.
-- Run with the Supabase CLI or paste into the Supabase SQL editor.

create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.music_spaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.space_members (
  space_id uuid not null references public.music_spaces(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'editor', 'member')),
  created_at timestamptz not null default now(),
  primary key (space_id, user_id)
);

create table public.cloud_tracks (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.music_spaces(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  content_hash text not null,
  title text not null,
  artist text not null default '未知歌手',
  album text not null default '未知专辑',
  duration_ms bigint not null default 0,
  file_size bigint not null default 0,
  media_type text not null default 'audio',
  media_object_path text,
  video_object_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (space_id, content_hash)
);

create table public.user_track_state (
  user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.cloud_tracks(id) on delete cascade,
  is_favorite boolean not null default false,
  play_count integer not null default 0,
  last_played_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, track_id)
);

create table public.cloud_playlists (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.music_spaces(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  description text not null default '',
  cover_path text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cloud_playlist_tracks (
  playlist_id uuid not null references public.cloud_playlists(id) on delete cascade,
  track_id uuid not null references public.cloud_tracks(id) on delete cascade,
  sort_order integer not null default 0,
  added_at timestamptz not null default now(),
  primary key (playlist_id, track_id)
);

create table public.play_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.cloud_tracks(id) on delete cascade,
  listened_seconds integer not null check (listened_seconds > 0),
  occurred_at timestamptz not null default now()
);

create table public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create or replace function public.is_space_member(target_space uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.space_members
    where space_id = target_space and user_id = (select auth.uid())
  );
$$;

create or replace function public.handle_new_sona_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  created_space uuid;
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  insert into public.music_spaces (owner_id, name)
  values (new.id, '我的音乐空间') returning id into created_space;
  insert into public.space_members (space_id, user_id, role)
  values (created_space, new.id, 'owner');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_sona_user();

alter table public.profiles enable row level security;
alter table public.music_spaces enable row level security;
alter table public.space_members enable row level security;
alter table public.cloud_tracks enable row level security;
alter table public.user_track_state enable row level security;
alter table public.cloud_playlists enable row level security;
alter table public.cloud_playlist_tracks enable row level security;
alter table public.play_events enable row level security;
alter table public.user_settings enable row level security;

create policy "profile owner access" on public.profiles
  for all to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
create policy "member reads spaces" on public.music_spaces
  for select to authenticated using (public.is_space_member(id));
create policy "owner manages spaces" on public.music_spaces
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
create policy "member reads memberships" on public.space_members
  for select to authenticated using (public.is_space_member(space_id));
create policy "owner manages memberships" on public.space_members
  for all to authenticated
  using (exists (select 1 from public.music_spaces s where s.id = space_id and s.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.music_spaces s where s.id = space_id and s.owner_id = (select auth.uid())));
create policy "members manage tracks" on public.cloud_tracks
  for all to authenticated using (public.is_space_member(space_id))
  with check (public.is_space_member(space_id));
create policy "users manage own track state" on public.user_track_state
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "members manage playlists" on public.cloud_playlists
  for all to authenticated using (public.is_space_member(space_id))
  with check (public.is_space_member(space_id));
create policy "members manage playlist tracks" on public.cloud_playlist_tracks
  for all to authenticated
  using (exists (select 1 from public.cloud_playlists p where p.id = playlist_id and public.is_space_member(p.space_id)))
  with check (exists (select 1 from public.cloud_playlists p where p.id = playlist_id and public.is_space_member(p.space_id)));
create policy "users manage own play events" on public.play_events
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "users manage own settings" on public.user_settings
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

insert into storage.buckets (id, name, public)
values ('sona-avatars', 'sona-avatars', false), ('sona-media', 'sona-media', false)
on conflict (id) do nothing;

create policy "avatar owner access" on storage.objects
  for all to authenticated
  using (bucket_id = 'sona-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text))
  with check (bucket_id = 'sona-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "space members access media" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'sona-media'
    and public.is_space_member(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'sona-media'
    and public.is_space_member(((storage.foldername(name))[1])::uuid)
  );

create index cloud_tracks_space_id_idx on public.cloud_tracks(space_id);
create index cloud_tracks_hash_idx on public.cloud_tracks(content_hash);
create index play_events_user_time_idx on public.play_events(user_id, occurred_at desc);
