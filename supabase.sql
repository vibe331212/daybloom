-- Daybloom database setup
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run.
-- Safe to run more than once.

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'Me' check (char_length(name) between 1 and 30),
  shirt text not null default '#7c5cff' check (shirt ~ '^#[0-9a-fA-F]{6}$'),
  style text not null default 'classic' check (style in ('classic','stripes','pocket','star','bolt')),
  code text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table if not exists public.events (
  id uuid primary key,
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  date date not null,
  time text not null check (time ~ '^[0-2][0-9]:[0-5][0-9]$'),
  notes text not null default '' check (char_length(notes) <= 2000),
  repeat text not null default 'none' check (repeat in ('none','daily','weekly','monthly','yearly')),
  remind text not null default '0',
  color text not null default '#7c5cff' check (color ~ '^#[0-9a-fA-F]{6}$'),
  private boolean not null default false,
  updated_at timestamptz not null default now()
);
create index if not exists events_owner_idx on public.events(owner);

-- Usernames (people sign up with a username and password)
alter table public.profiles add column if not exists username text unique
  check (username ~ '^[a-z0-9_]{3,20}$');

alter table public.profiles    enable row level security;
alter table public.friendships enable row level security;
alter table public.events      enable row level security;

-- ---------- Who can touch what ----------
-- Friend codes are only ever handed out through functions below, so the code column is not readable directly.
revoke all on public.profiles    from anon, authenticated;
revoke all on public.friendships from anon, authenticated;
revoke all on public.events      from anon, authenticated;
grant select (id, name, username, shirt, style, created_at) on public.profiles to authenticated;
grant update (name, shirt, style)                 on public.profiles to authenticated;
grant select                                      on public.friendships to authenticated;
grant select, insert, update, delete              on public.events to authenticated;

create or replace function public.is_friend(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships where user_id = auth.uid() and friend_id = other);
$$;

drop policy if exists "profiles: me and my friends" on public.profiles;
create policy "profiles: me and my friends" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_friend(id));

drop policy if exists "profiles: edit my own" on public.profiles;
create policy "profiles: edit my own" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "friendships: my own" on public.friendships;
create policy "friendships: my own" on public.friendships for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "events: my own" on public.events;
create policy "events: my own" on public.events for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

drop policy if exists "events: friends see shared ones" on public.events;
create policy "events: friends see shared ones" on public.events for select to authenticated
  using (not private and public.is_friend(owner));

-- ---------- Friend codes ----------
-- 8 characters, no look-alike letters (no I, L, O, 0, 1). About 850 billion possibilities, so codes can't be guessed.
create or replace function public.new_friend_code()
returns text language plpgsql security definer set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := '';
    for i in 1..8 loop
      c := c || substr(alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(alphabet)), 1);
    end loop;
    exit when not exists (select 1 from public.profiles where code = c);
  end loop;
  return c;
end $$;

create or replace function public.ensure_profile(p_name text, p_shirt text, p_style text)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uname text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  -- The username comes from the signed-in account itself (username@users.daybloom.app), so it can't be faked
  if email !~ '^[a-z0-9_]{3,20}@users\.daybloom\.app$' then raise exception 'Sign in with a Daybloom username'; end if;
  uname := split_part(email, '@', 1);
  select * into me from public.profiles where id = auth.uid();
  if not found then
    insert into public.profiles (id, name, username, shirt, style, code)
    values (auth.uid(), coalesce(nullif(left(trim(p_name), 30), ''), uname), uname,
            coalesce(p_shirt, '#7c5cff'), coalesce(p_style, 'classic'), public.new_friend_code())
    returning * into me;
  elsif me.username is null then
    update public.profiles set username = uname where id = auth.uid() returning * into me;
  end if;
  return me;
end $$;

create or replace function public.add_friend(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare f public.profiles;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into f from public.profiles
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if not found then raise exception 'No one has that code'; end if;
  if f.id = auth.uid() then raise exception 'That is your own code'; end if;
  insert into public.friendships (user_id, friend_id)
  values (auth.uid(), f.id), (f.id, auth.uid())
  on conflict do nothing;
  return json_build_object('id', f.id, 'name', f.name, 'username', f.username, 'shirt', f.shirt, 'style', f.style);
end $$;

create or replace function public.remove_friend(p_friend uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.friendships
   where (user_id = auth.uid() and friend_id = p_friend)
      or (user_id = p_friend and friend_id = auth.uid());
$$;

create or replace function public.new_code()
returns text language sql security definer set search_path = public as $$
  update public.profiles set code = public.new_friend_code() where id = auth.uid() returning code;
$$;

revoke execute on function public.is_friend(uuid)                   from public, anon;
revoke execute on function public.new_friend_code()                 from public, anon, authenticated;
revoke execute on function public.ensure_profile(text, text, text)  from public, anon;
revoke execute on function public.add_friend(text)                  from public, anon;
revoke execute on function public.remove_friend(uuid)               from public, anon;
revoke execute on function public.new_code()                        from public, anon;
grant  execute on function public.is_friend(uuid)                   to authenticated;
grant  execute on function public.ensure_profile(text, text, text)  to authenticated;
grant  execute on function public.add_friend(text)                  to authenticated;
grant  execute on function public.remove_friend(uuid)               to authenticated;
grant  execute on function public.new_code()                        to authenticated;
