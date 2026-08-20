-- Stage 1A: align the already-deployed sona-cloud schema with the Flutter
-- client. This migration is intentionally forward-only and repeatable.
-- It does not change RLS or Storage policies; those belong to stage 1B.

-- The production schema was created before username support. Keep it nullable
-- for existing Auth users whose metadata has no valid Sona username yet.
alter table public.profiles
  add column if not exists username text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_username_format'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_username_format
      check (username is null or username ~ '^[a-z][a-z0-9_]{2,23}$');
  end if;
end;
$$;

create unique index if not exists profiles_username_unique_idx
  on public.profiles (lower(username))
  where username is not null;

-- Recover valid usernames from Auth metadata without inventing values for old
-- accounts. Invalid, already claimed, or duplicate values remain null and can
-- be resolved later; this keeps the backfill from failing on historical data.
with candidates as (
  select
    p.id,
    lower(u.raw_user_meta_data ->> 'username') as username
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.username is null
    and lower(coalesce(u.raw_user_meta_data ->> 'username', ''))
        ~ '^[a-z][a-z0-9_]{2,23}$'
),
unclaimed as (
  select c.*
  from candidates c
  where not exists (
    select 1
    from public.profiles occupied
    where occupied.username is not null
      and lower(occupied.username) = c.username
  )
),
deduplicated as (
  select distinct on (username) id, username
  from unclaimed
  order by username, id
)
update public.profiles p
set username = d.username
from deduplicated d
where p.id = d.id;

-- Playlist membership is a synchronised relation too. Timestamps allow a later
-- incremental merge to distinguish a current row from a stale device copy.
alter table public.cloud_playlist_tracks
  add column if not exists updated_at timestamptz not null default now();

-- Cover the lookup and idempotency keys used by the client. Existing primary
-- keys/unique constraints may already provide equivalent protection; these are
-- named indexes so the migration remains safe on both fresh and old projects.
create index if not exists cloud_tracks_space_updated_at_idx
  on public.cloud_tracks (space_id, updated_at desc);
create index if not exists cloud_playlists_space_updated_at_idx
  on public.cloud_playlists (space_id, updated_at desc);
create index if not exists cloud_playlist_tracks_playlist_updated_at_idx
  on public.cloud_playlist_tracks (playlist_id, updated_at desc);
create index if not exists user_track_state_user_updated_at_idx
  on public.user_track_state (user_id, updated_at desc);
create index if not exists user_settings_updated_at_idx
  on public.user_settings (updated_at desc);

-- Do not rely on every mobile/desktop caller remembering to send updated_at.
create or replace function public.sona_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'profiles',
    'cloud_tracks',
    'user_track_state',
    'cloud_playlists',
    'cloud_playlist_tracks',
    'user_settings'
  ]
  loop
    execute format(
      'drop trigger if exists sona_%I_set_updated_at on public.%I',
      target_table,
      target_table
    );
    execute format(
      'create trigger sona_%I_set_updated_at before update on public.%I '
      || 'for each row execute function public.sona_set_updated_at()',
      target_table,
      target_table
    );
  end loop;
end;
$$;

-- New registrations must write the same profile shape as existing users.
create or replace function public.handle_new_sona_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  created_space uuid;
  requested_username text := lower(coalesce(new.raw_user_meta_data ->> 'username', ''));
begin
  if requested_username !~ '^[a-z][a-z0-9_]{2,23}$' then
    requested_username := null;
  end if;

  insert into public.profiles (id, display_name, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    requested_username
  );
  insert into public.music_spaces (owner_id, name)
  values (new.id, '我的音乐空间')
  returning id into created_space;
  insert into public.space_members (space_id, user_id, role)
  values (created_space, new.id, 'owner');
  return new;
end;
$$;
