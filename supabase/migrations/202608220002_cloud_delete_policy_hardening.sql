-- Keep normal sync and recycle-bin UPDATE operations compatible while making
-- permanent deletion an explicit, owner-only operation.

drop policy if exists "members manage tracks" on public.cloud_tracks;

drop policy if exists "members read tracks" on public.cloud_tracks;
create policy "members read tracks" on public.cloud_tracks
  for select to authenticated
  using (public.is_space_member(space_id));

drop policy if exists "members insert tracks" on public.cloud_tracks;
create policy "members insert tracks" on public.cloud_tracks
  for insert to authenticated
  with check (public.is_space_member(space_id));

drop policy if exists "members update tracks" on public.cloud_tracks;
create policy "members update tracks" on public.cloud_tracks
  for update to authenticated
  using (public.is_space_member(space_id))
  with check (public.is_space_member(space_id));

-- There is deliberately no DELETE policy on cloud_tracks. The SECURITY
-- DEFINER function below is the only client-callable hard-delete path. It
-- checks both ownership and recycle-bin state before bypassing RLS.
create or replace function public.permanently_delete_cloud_track(
  target_track uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  removed_rows integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  delete from public.cloud_tracks as track
  using public.music_spaces as space
  where track.id = target_track
    and track.deleted_at is not null
    and space.id = track.space_id
    and space.owner_id = auth.uid();

  get diagnostics removed_rows = row_count;
  if removed_rows <> 1 then
    raise exception 'Only a recycled track owned by the caller can be permanently deleted.'
      using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all on function public.permanently_delete_cloud_track(uuid)
  from public, anon;
grant execute on function public.permanently_delete_cloud_track(uuid)
  to authenticated;

-- Replacing a playlist with client-side DELETE followed by INSERT has a data
-- loss window: an interrupted request publishes an empty playlist to every
-- other device. Keep validation and replacement in one database transaction.
-- Remove the legacy write policy as well: authenticated clients may read the
-- ordered rows, but all replacement writes must pass through the owner-only
-- transactional function below.
drop policy if exists "members manage playlist tracks"
  on public.cloud_playlist_tracks;
drop policy if exists "members read playlist tracks"
  on public.cloud_playlist_tracks;
create policy "members read playlist tracks"
  on public.cloud_playlist_tracks
  for select to authenticated
  using (
    exists (
      select 1
      from public.cloud_playlists as playlist
      where playlist.id = playlist_id
        and public.is_space_member(playlist.space_id)
    )
  );

create or replace function public.replace_cloud_playlist_tracks(
  target_playlist uuid,
  target_space uuid,
  requested_track_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  playlist_space uuid;
  requested_count integer;
  validated_track_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if requested_track_ids is null
     or array_position(requested_track_ids, null) is not null then
    raise exception 'Playlist track IDs must be a non-null UUID array.'
      using errcode = '22023';
  end if;

  requested_count := cardinality(requested_track_ids);
  if requested_count > 10000 then
    raise exception 'A playlist cannot contain more than 10000 tracks.'
      using errcode = '54000';
  end if;
  if exists (
    select 1
    from unnest(requested_track_ids) as requested(track_id)
    group by requested.track_id
    having count(*) > 1
  ) then
    raise exception 'Playlist track IDs must be unique.'
      using errcode = '22023';
  end if;

  select playlist.space_id
    into playlist_space
  from public.cloud_playlists as playlist
  where playlist.id = target_playlist
    and playlist.space_id = target_space
    and playlist.owner_id = auth.uid()
    and public.is_space_member(playlist.space_id)
  for update;

  if playlist_space is null then
    raise exception 'Only the playlist owner can replace its tracks.'
      using errcode = '42501';
  end if;

  -- Hold matching rows through replacement so a concurrent recycle/delete
  -- cannot invalidate validation between the check and INSERT.
  perform 1
  from public.cloud_tracks as track
  where track.id = any(requested_track_ids)
    and track.space_id = playlist_space
    and track.deleted_at is null
  for share;
  get diagnostics validated_track_count = row_count;
  if validated_track_count <> requested_count then
    raise exception 'Every playlist track must be active and belong to the playlist space.'
      using errcode = '23503';
  end if;

  delete from public.cloud_playlist_tracks
  where playlist_id = target_playlist;

  insert into public.cloud_playlist_tracks (playlist_id, track_id, sort_order)
  select
    target_playlist,
    requested.track_id,
    (requested.position - 1)::integer
  from unnest(requested_track_ids) with ordinality
    as requested(track_id, position);

  update public.cloud_playlists
  set updated_at = now()
  where id = target_playlist;

  return requested_count;
end;
$$;

revoke all on function public.replace_cloud_playlist_tracks(uuid, uuid, uuid[])
  from public, anon;
grant execute on function public.replace_cloud_playlist_tracks(uuid, uuid, uuid[])
  to authenticated;

comment on function public.replace_cloud_playlist_tracks(uuid, uuid, uuid[]) is
  'Atomically validates and replaces one owner playlist ordered track list.';

drop policy if exists "space members access media" on storage.objects;

drop policy if exists "space members read media" on storage.objects;
create policy "space members read media" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'sona-media'
    and public.is_space_member(
      case
        when coalesce((storage.foldername(name))[1], '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then ((storage.foldername(name))[1])::uuid
        else null
      end
    )
  );

drop policy if exists "space members insert media" on storage.objects;
create policy "space members insert media" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'sona-media'
    and public.is_space_member(
      case
        when coalesce((storage.foldername(name))[1], '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then ((storage.foldername(name))[1])::uuid
        else null
      end
    )
  );

drop policy if exists "space members update media" on storage.objects;
create policy "space members update media" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'sona-media'
    and public.is_space_member(
      case
        when coalesce((storage.foldername(name))[1], '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then ((storage.foldername(name))[1])::uuid
        else null
      end
    )
  )
  with check (
    bucket_id = 'sona-media'
    and public.is_space_member(
      case
        when coalesce((storage.foldername(name))[1], '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then ((storage.foldername(name))[1])::uuid
        else null
      end
    )
  );

-- Storage deletion is owner-only and only allowed after the corresponding
-- database record no longer references the object. The client therefore calls
-- permanently_delete_cloud_track first, then removes the resulting orphan.
drop policy if exists "space owners delete orphaned media" on storage.objects;
create policy "space owners delete orphaned media" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'sona-media'
    and exists (
      select 1
      from public.music_spaces as space
      where space.id::text = (storage.foldername(name))[1]
        and space.owner_id = auth.uid()
    )
    and not exists (
      select 1
      from public.cloud_tracks as track
      where track.space_id::text = (storage.foldername(name))[1]
        and (track.media_object_path = name or track.video_object_path = name)
    )
    and not exists (
      select 1
      from public.cloud_playlists as playlist
      where playlist.space_id::text = (storage.foldername(name))[1]
        and playlist.cover_path = name
    )
  );

comment on function public.permanently_delete_cloud_track(uuid) is
  'Owner-only hard delete for tracks already in the cloud recycle bin.';
