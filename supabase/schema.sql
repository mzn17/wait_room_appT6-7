-- =====================================================================
-- Waiting Room - Workshop 6 + multi-user + multi-tenant upgrade
-- Run this whole file in Supabase > SQL Editor.
-- It is idempotent and can be re-run on an existing workshop database.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Rooms (tenants) and memberships
-- ---------------------------------------------------------------------
create table if not exists public.tenants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(trim(name)) between 1 and 100),
  invite_code text not null unique,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.tenant_members (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  role      text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);

create index if not exists tenant_members_user_idx
  on public.tenant_members(user_id);

-- ---------------------------------------------------------------------
-- 1. Queue data. One queue per room.
-- ---------------------------------------------------------------------
create table if not exists public.clients (
  id            uuid primary key,
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  queue_number  bigint,
  name          text not null check (char_length(trim(name)) between 1 and 100),
  has_location  boolean not null default false,
  requested_at  timestamptz,
  registered_by uuid,
  created_at    timestamptz not null default now()
);

-- Upgrade an existing workshop table in place.
alter table public.clients add column if not exists tenant_id uuid;
alter table public.clients add column if not exists registered_by uuid;

-- A legacy room keeps the rows created before multi-tenant existed.
insert into public.tenants (id, name, invite_code)
values ('00000000-0000-0000-0000-000000000001', 'Legacy Room', 'LEGACY01')
on conflict (id) do nothing;

update public.clients
set tenant_id = '00000000-0000-0000-0000-000000000001'
where tenant_id is null;

alter table public.clients alter column tenant_id set not null;

-- Queue numbers become per-room instead of one global sequence.
alter table public.clients alter column queue_number drop identity if exists;
alter table public.clients alter column queue_number drop default;
alter table public.clients drop constraint if exists clients_queue_number_key;
create unique index if not exists clients_tenant_queue_number_key
  on public.clients(tenant_id, queue_number)
  where queue_number is not null;

create index if not exists clients_tenant_queue_idx
  on public.clients(tenant_id, queue_number);

-- Add the room foreign key only when it is missing.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clients_tenant_id_fkey'
  ) then
    alter table public.clients
      add constraint clients_tenant_id_fkey
      foreign key (tenant_id) references public.tenants(id) on delete cascade;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Private precise coordinates (nobody can read them from the app)
-- ---------------------------------------------------------------------
create table if not exists public.client_locations (
  client_id            uuid primary key references public.clients(id) on delete cascade,
  lat                  double precision check (lat between -90 and 90),
  lng                  double precision check (lng between -180 and 180),
  location_accuracy_m  double precision,
  location_captured_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. Security helpers. SECURITY DEFINER avoids recursive RLS checks.
-- ---------------------------------------------------------------------
create or replace function public.is_tenant_member(
  p_tenant_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.tenant_members
    where tenant_id = p_tenant_id and user_id = p_user_id
  );
$$;

create or replace function public.is_tenant_owner(
  p_tenant_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.tenant_members
    where tenant_id = p_tenant_id
      and user_id = p_user_id
      and role = 'owner'
  );
$$;

revoke execute on function public.is_tenant_member(uuid, uuid) from public, anon;
revoke execute on function public.is_tenant_owner(uuid, uuid) from public, anon;
grant execute on function public.is_tenant_member(uuid, uuid) to authenticated;
grant execute on function public.is_tenant_owner(uuid, uuid) to authenticated;

-- Public health probe used by the connectivity service (works signed out).
create or replace function public.health_check()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select 1; $$;

revoke execute on function public.health_check() from public;
grant execute on function public.health_check() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Row Level Security
-- ---------------------------------------------------------------------
alter table public.tenants enable row level security;
alter table public.tenant_members enable row level security;
alter table public.clients enable row level security;
alter table public.client_locations enable row level security;

drop policy if exists "anyone can read queue" on public.clients;
drop policy if exists "members can read their rooms" on public.tenants;
drop policy if exists "members can read the roster" on public.tenant_members;
drop policy if exists "members can read their queue" on public.clients;

create policy "members can read their rooms"
  on public.tenants for select to authenticated
  using (public.is_tenant_member(id, auth.uid()));

create policy "members can read the roster"
  on public.tenant_members for select to authenticated
  using (public.is_tenant_member(tenant_id, auth.uid()));

create policy "members can read their queue"
  on public.clients for select to authenticated
  using (public.is_tenant_member(tenant_id, auth.uid()));

-- Writes only go through the RPCs below.
revoke insert, update, delete on public.clients from anon, authenticated;
revoke insert, update, delete on public.tenants from anon, authenticated;
revoke insert, update, delete on public.tenant_members from anon, authenticated;
revoke all on public.client_locations from anon, authenticated;

grant select on public.clients to anon, authenticated;
grant select on public.tenants to authenticated;
grant select on public.tenant_members to authenticated;

-- ---------------------------------------------------------------------
-- 5. Create / join rooms
-- ---------------------------------------------------------------------
create or replace function public.create_tenant(p_name text)
returns table (
  id uuid,
  name text,
  invite_code text,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid := gen_random_uuid();
  v_name text := trim(coalesce(p_name, ''));
  v_code text;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;
  if char_length(v_name) not between 1 and 100 then
    raise exception 'Room name must be between 1 and 100 characters';
  end if;

  loop
    v_code := upper(substr(
      md5(random()::text || clock_timestamp()::text || v_id::text), 1, 8
    ));
    exit when not exists (
      select 1 from public.tenants t where t.invite_code = v_code
    );
  end loop;

  insert into public.tenants (id, name, invite_code, created_by)
  values (v_id, v_name, v_code, v_user);

  insert into public.tenant_members (tenant_id, user_id, role)
  values (v_id, v_user, 'owner');

  return query
    select t.id, t.name, t.invite_code, 'owner'::text, t.created_at
    from public.tenants t
    where t.id = v_id;
end;
$$;

create or replace function public.join_tenant(p_invite_code text)
returns table (
  id uuid,
  name text,
  invite_code text,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select t.id into v_tenant
  from public.tenants t
  where upper(t.invite_code) = upper(trim(coalesce(p_invite_code, '')));

  if v_tenant is null then
    raise exception 'Invalid invite code';
  end if;

  insert into public.tenant_members (tenant_id, user_id, role)
  values (v_tenant, v_user, 'member')
  on conflict (tenant_id, user_id) do nothing;

  return query
    select t.id, t.name, t.invite_code, tm.role, t.created_at
    from public.tenants t
    join public.tenant_members tm on tm.tenant_id = t.id
    where t.id = v_tenant and tm.user_id = v_user;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. Multi-user roster management
-- ---------------------------------------------------------------------
create or replace function public.list_tenant_members(p_tenant_id uuid)
returns table (
  user_id uuid,
  email text,
  display_name text,
  role text,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_tenant_member(p_tenant_id, auth.uid()) then
    raise exception 'Not a member of this room';
  end if;

  return query
    select
      tm.user_id,
      coalesce(u.email, '')::text,
      coalesce(
        nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
        split_part(coalesce(u.email, ''), '@', 1)
      )::text,
      tm.role,
      tm.joined_at
    from public.tenant_members tm
    join auth.users u on u.id = tm.user_id
    where tm.tenant_id = p_tenant_id
    order by (tm.role = 'owner') desc, tm.joined_at asc;
end;
$$;

create or replace function public.add_tenant_member(
  p_tenant_id uuid,
  p_email text,
  p_role text default 'member'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_target uuid;
  v_role text := coalesce(nullif(trim(p_role), ''), 'member');
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_tenant_owner(p_tenant_id, v_user) then
    raise exception 'Only the room owner can add members';
  end if;
  if v_role <> 'member' then
    raise exception 'New members can only be added with the member role';
  end if;

  select u.id into v_target
  from auth.users u
  where lower(u.email) = lower(trim(coalesce(p_email, '')));

  if v_target is null then
    raise exception 'No account found for this email';
  end if;

  insert into public.tenant_members (tenant_id, user_id, role)
  values (p_tenant_id, v_target, v_role)
  on conflict (tenant_id, user_id) do update set role = excluded.role;
end;
$$;

create or replace function public.remove_tenant_member(
  p_tenant_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;
  if not (public.is_tenant_owner(p_tenant_id, v_user) or p_user_id = v_user) then
    raise exception 'Only the room owner can remove members';
  end if;
  if exists (
    select 1 from public.tenant_members
    where tenant_id = p_tenant_id and user_id = p_user_id and role = 'owner'
  ) then
    raise exception 'The room owner cannot be removed';
  end if;

  delete from public.tenant_members
  where tenant_id = p_tenant_id and user_id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. Idempotent queue registration. Server assigns the room queue number.
-- ---------------------------------------------------------------------
drop function if exists public.register_queue_client(
  uuid, text, double precision, double precision, double precision, timestamptz
);

create or replace function public.register_queue_client(
  p_tenant_id uuid,
  p_id uuid,
  p_name text,
  p_lat double precision,
  p_lng double precision,
  p_accuracy double precision,
  p_requested_at timestamptz
)
returns setof public.clients
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_has_loc boolean := (p_lat is not null and p_lng is not null);
  v_number bigint;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_tenant_member(p_tenant_id, v_user) then
    raise exception 'Not a member of this room';
  end if;

  if not exists (select 1 from public.clients where id = p_id) then
    -- Serialize registrations for this room so queue numbers cannot collide.
    perform 1 from public.tenants where id = p_tenant_id for update;

    select coalesce(max(queue_number), 0) + 1 into v_number
    from public.clients
    where tenant_id = p_tenant_id;

    insert into public.clients (
      id, tenant_id, queue_number, name, has_location, requested_at, registered_by
    )
    values (
      p_id, p_tenant_id, v_number, trim(p_name), v_has_loc, p_requested_at, v_user
    )
    on conflict (id) do nothing;

    if v_has_loc then
      insert into public.client_locations (
        client_id, lat, lng, location_accuracy_m
      )
      values (p_id, p_lat, p_lng, p_accuracy)
      on conflict (client_id) do nothing;
    end if;
  end if;

  return query select * from public.clients where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. Function permissions
-- ---------------------------------------------------------------------
revoke execute on function public.create_tenant(text) from public, anon;
revoke execute on function public.join_tenant(text) from public, anon;
revoke execute on function public.list_tenant_members(uuid) from public, anon;
revoke execute on function public.add_tenant_member(uuid, text, text) from public, anon;
revoke execute on function public.remove_tenant_member(uuid, uuid) from public, anon;
revoke execute on function public.register_queue_client(
  uuid, uuid, text, double precision, double precision, double precision, timestamptz
) from public, anon;

grant execute on function public.create_tenant(text) to authenticated;
grant execute on function public.join_tenant(text) to authenticated;
grant execute on function public.list_tenant_members(uuid) to authenticated;
grant execute on function public.add_tenant_member(uuid, text, text) to authenticated;
grant execute on function public.remove_tenant_member(uuid, uuid) to authenticated;
grant execute on function public.register_queue_client(
  uuid, uuid, text, double precision, double precision, double precision, timestamptz
) to authenticated;

-- ---------------------------------------------------------------------
-- 9. Realtime on the queue table
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'clients'
  ) then
    alter publication supabase_realtime add table public.clients;
  end if;
end $$;
