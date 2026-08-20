-- Sona username accounts.
-- A username is the public login handle. Supabase Auth still owns password hashes.

alter table public.profiles
  add column if not exists username text;

alter table public.profiles
  add constraint profiles_username_format
  check (username is null or username ~ '^[a-z][a-z0-9_]{2,23}$');

create unique index if not exists profiles_username_unique_idx
  on public.profiles (lower(username))
  where username is not null;

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
  if requested_username = '' then
    requested_username := null;
  end if;

  insert into public.profiles (id, display_name, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    requested_username
  );
  insert into public.music_spaces (owner_id, name)
  values (new.id, '我的音乐空间') returning id into created_space;
  insert into public.space_members (space_id, user_id, role)
  values (created_space, new.id, 'owner');
  return new;
end;
$$;
