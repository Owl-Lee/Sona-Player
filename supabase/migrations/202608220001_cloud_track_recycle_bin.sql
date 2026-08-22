-- Keep deleted cloud tracks recoverable for 30 days. Media objects remain in
-- Storage until the client permanently purges the matching row.
alter table public.cloud_tracks
  add column if not exists deleted_at timestamptz;

create index if not exists cloud_tracks_recycle_bin_idx
  on public.cloud_tracks(space_id, deleted_at desc)
  where deleted_at is not null;

comment on column public.cloud_tracks.deleted_at is
  'Soft-delete timestamp. NULL means active; clients purge rows after 30 days.';
