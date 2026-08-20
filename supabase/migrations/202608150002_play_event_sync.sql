-- Add an idempotency key so the same local play event can be uploaded safely
-- from Windows/Android more than once without inflating the ranking.
alter table public.play_events
  add column if not exists client_event_id text;

create unique index if not exists play_events_user_client_event_idx
  on public.play_events(user_id, client_event_id)
  where client_event_id is not null;
