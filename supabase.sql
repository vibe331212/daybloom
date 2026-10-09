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

-- Animal avatars (the old shirt styles are still accepted so older accounts keep working)
alter table public.profiles drop constraint if exists profiles_style_check;
alter table public.profiles add constraint profiles_style_check check (style in
  ('fox','wolf','bear','mouse','cat','rabbit','panda','owl','raccoon','lion',
   'classic','stripes','pocket','star','bolt'));
alter table public.profiles alter column style set default 'fox';

-- All-day events
alter table public.events add column if not exists all_day boolean not null default false;

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
            coalesce(p_shirt, '#7c5cff'), coalesce(p_style, 'fox'), public.new_friend_code())
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

-- ---------- Private chats between friends ----------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  name text check (name is null or char_length(name) between 1 and 40),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index if not exists conversation_members_user_idx on public.conversation_members(user_id);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists messages_conversation_idx on public.messages(conversation_id, created_at);

alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;

revoke all on public.conversations        from anon, authenticated;
revoke all on public.conversation_members from anon, authenticated;
revoke all on public.messages             from anon, authenticated;
grant select on public.conversations        to authenticated;
grant select on public.conversation_members to authenticated;
grant select on public.messages             to authenticated;
grant insert (conversation_id, body) on public.messages to authenticated;   -- sender and time are filled in by the database

create or replace function public.is_member(conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_members where conversation_id = conv and user_id = auth.uid());
$$;

create or replace function public.shares_chat(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_members a join public.conversation_members b using (conversation_id)
                 where a.user_id = auth.uid() and b.user_id = other);
$$;

-- In a one-on-one chat you can only post while you're still friends
create or replace function public.can_post(conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member(conv) and (
    (select is_group from public.conversations where id = conv)
    or exists (select 1 from public.conversation_members m where m.conversation_id = conv and m.user_id <> auth.uid() and public.is_friend(m.user_id))
  );
$$;

drop policy if exists "conversations: members" on public.conversations;
create policy "conversations: members" on public.conversations for select to authenticated using (public.is_member(id));
drop policy if exists "conversation_members: members" on public.conversation_members;
create policy "conversation_members: members" on public.conversation_members for select to authenticated using (public.is_member(conversation_id));
drop policy if exists "messages: members read" on public.messages;
create policy "messages: members read" on public.messages for select to authenticated using (public.is_member(conversation_id));
drop policy if exists "messages: members post" on public.messages;
create policy "messages: members post" on public.messages for insert to authenticated
  with check (sender = auth.uid() and public.can_post(conversation_id));

-- People in a group chat can see each other's name and animal even if they aren't friends
drop policy if exists "profiles: me and my friends" on public.profiles;
create policy "profiles: me and my friends" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_friend(id) or public.shares_chat(id));

create or replace function public.touch_conversation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.conversations set last_message_at = new.created_at where id = new.conversation_id;
  return new;
end $$;
drop trigger if exists messages_touch on public.messages;
create trigger messages_touch after insert on public.messages for each row execute function public.touch_conversation();

create or replace function public.start_chat(p_friend uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if not public.is_friend(p_friend) then raise exception 'You can only chat with friends'; end if;
  select c.id into conv from public.conversations c
   where not c.is_group
     and exists (select 1 from public.conversation_members where conversation_id = c.id and user_id = auth.uid())
     and exists (select 1 from public.conversation_members where conversation_id = c.id and user_id = p_friend)
   limit 1;
  if conv is null then
    insert into public.conversations (is_group) values (false) returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, auth.uid()), (conv, p_friend);
  end if;
  return conv;
end $$;

create or replace function public.create_group(p_name text, p_members uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid; m uuid;
begin
  if coalesce(array_length(p_members, 1), 0) < 1 then raise exception 'Pick at least one friend'; end if;
  if array_length(p_members, 1) > 20 then raise exception 'Groups can have up to 20 friends'; end if;
  foreach m in array p_members loop
    if not public.is_friend(m) then raise exception 'Everyone in a group has to be your friend'; end if;
  end loop;
  insert into public.conversations (is_group, name) values (true, nullif(left(btrim(p_name), 40), '')) returning id into conv;
  insert into public.conversation_members (conversation_id, user_id)
    select conv, u from unnest(array_append(p_members, auth.uid())) as u on conflict do nothing;
  return conv;
end $$;

create or replace function public.leave_chat(p_conv uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.conversation_members where conversation_id = p_conv and user_id = auth.uid();
  delete from public.conversations c where c.id = p_conv
    and not exists (select 1 from public.conversation_members where conversation_id = c.id);
end $$;

revoke execute on function public.is_member(uuid)               from public, anon;
revoke execute on function public.shares_chat(uuid)             from public, anon;
revoke execute on function public.can_post(uuid)                from public, anon;
revoke execute on function public.touch_conversation()          from public, anon, authenticated;
revoke execute on function public.start_chat(uuid)              from public, anon;
revoke execute on function public.create_group(text, uuid[])    from public, anon;
revoke execute on function public.leave_chat(uuid)              from public, anon;
grant  execute on function public.is_member(uuid)               to authenticated;
grant  execute on function public.shares_chat(uuid)             to authenticated;
grant  execute on function public.can_post(uuid)                to authenticated;
grant  execute on function public.start_chat(uuid)              to authenticated;
grant  execute on function public.create_group(text, uuid[])    to authenticated;
grant  execute on function public.leave_chat(uuid)              to authenticated;

-- Live delivery of new messages (each person still only receives chats they're in)
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;

-- ---------- Group chat photo and name ----------
alter table public.conversations add column if not exists photo_kind text check (photo_kind in ('icon','animal','photo'));
alter table public.conversations add column if not exists photo_value text check (char_length(photo_value) <= 200);
alter table public.conversations add column if not exists photo_color text check (photo_color ~ '^#[0-9a-fA-F]{6}$');

create or replace function public.update_chat(p_conv uuid, p_name text, p_kind text, p_value text, p_color text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_conv) then raise exception 'You are not in this chat'; end if;
  if not (select is_group from public.conversations where id = p_conv) then raise exception 'Only group chats have their own photo and name'; end if;
  if p_kind = 'photo' and split_part(coalesce(p_value, ''), '/', 1) <> p_conv::text then raise exception 'That photo belongs to a different chat'; end if;
  update public.conversations
     set name = nullif(left(btrim(coalesce(p_name, '')), 40), ''),
         photo_kind = p_kind, photo_value = p_value, photo_color = p_color
   where id = p_conv;
end $$;
revoke execute on function public.update_chat(uuid, text, text, text, text) from public, anon;
grant  execute on function public.update_chat(uuid, text, text, text, text) to authenticated;

-- Photos live in a private bucket, in a folder named after the chat. Only people in that chat can see or change them.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-photos', 'chat-photos', false, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.in_chat_folder(obj_name text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare folder text := split_part(obj_name, '/', 1);
begin
  if folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  return public.is_member(folder::uuid) and (select is_group from public.conversations where id = folder::uuid);
end $$;
revoke execute on function public.in_chat_folder(text) from public, anon;
grant  execute on function public.in_chat_folder(text) to authenticated;

drop policy if exists "chat photos: members see" on storage.objects;
create policy "chat photos: members see" on storage.objects for select to authenticated
  using (bucket_id = 'chat-photos' and public.in_chat_folder(name));
drop policy if exists "chat photos: members add" on storage.objects;
create policy "chat photos: members add" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-photos' and public.in_chat_folder(name));
drop policy if exists "chat photos: members remove" on storage.objects;
create policy "chat photos: members remove" on storage.objects for delete to authenticated
  using (bucket_id = 'chat-photos' and public.in_chat_folder(name));

-- ---------- Photos in chats ----------
alter table public.messages add column if not exists image_path text check (char_length(image_path) <= 200);
alter table public.messages alter column body set default '';
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check
  check (char_length(body) <= 1000 and (char_length(btrim(body)) >= 1 or image_path is not null));
grant insert (conversation_id, body, image_path) on public.messages to authenticated;

drop policy if exists "messages: members post" on public.messages;
create policy "messages: members post" on public.messages for insert to authenticated
  with check (sender = auth.uid() and public.can_post(conversation_id)
              and (image_path is null or split_part(image_path, '/', 1) = conversation_id::text));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Photos sit in a folder named after the chat: members can see them, and only people allowed to post can add them
create or replace function public.chat_media_ok(obj_name text, for_write boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare folder text := split_part(obj_name, '/', 1);
begin
  if folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  if for_write then return public.can_post(folder::uuid); end if;
  return public.is_member(folder::uuid);
end $$;
revoke execute on function public.chat_media_ok(text, boolean) from public, anon;
grant  execute on function public.chat_media_ok(text, boolean) to authenticated;

drop policy if exists "chat media: members see" on storage.objects;
create policy "chat media: members see" on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and public.chat_media_ok(name, false));
drop policy if exists "chat media: members send" on storage.objects;
create policy "chat media: members send" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media' and public.chat_media_ok(name, true));
drop policy if exists "chat media: sender removes" on storage.objects;
create policy "chat media: sender removes" on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media' and owner_id = auth.uid()::text);
