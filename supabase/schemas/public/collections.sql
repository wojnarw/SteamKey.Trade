-- Create collection type enum
create type collection_type as enum (
  'app',
  'blacklist',
  'bundle',
  'custom',
  'giveaway',
  'library',
  'steambundle',
  'steampackage',
  'tradelist',
  'wishlist'
);

-- Create collections table
create table collections (
  id text primary key default gen_random_uuid(),
  private boolean default false,
  user_id uuid references users(id) on delete cascade,
  type collection_type not null default 'custom',
  master boolean default false check (
    not master or (
      type in ('tradelist', 'library', 'wishlist', 'blacklist')
      and not private
    )
  ),
  title text not null,
  description text default null,
  links jsonb default null,
  starts_at timestamptz default null,
  ends_at timestamptz default null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table collections is 'User collections for organizing apps and items';

-- Add indexes
create index collections_private_idx on public.collections using btree (private);
create index collections_title_idx on public.collections using btree (title);

-- Create trigger function to handle master collection inserts
create or replace function collections_handle_master_insert()
returns trigger
set search_path = ''
as $$
begin
  -- If master is being set to true, set all other collections of same type to false
  if new.master = true then
    update public.collections
    set master = false
    where user_id = new.user_id
    and type = new.type
    and id != new.id;
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger collections_handle_master_insert_trigger
before insert on collections
for each row
when (new.master = true)
execute function collections_handle_master_insert();

-- Create trigger function to handle master flag changes
create or replace function collections_handle_master_change()
returns trigger
set search_path = ''
as $$
begin
  -- If master is being set to true, set all other collections of same type to false and remove parents
  if new.master = true and old.master = false then
    -- First unset master for other collections of same type
    update public.collections
    set master = false
    where user_id = new.user_id
      and type = new.type
      and id != new.id;

    -- Then remove any parent relationships for this collection
    delete from public.collection_relations
    where collection_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger collections_master_change_trigger
after update of master on collections
for each row
when (new.master = true and old.master = false)
execute function collections_handle_master_change();

-- Create trigger function to prevent changing certain fields
create or replace function collections_prevent_key_changes()
returns trigger
set search_path = ''
as $$
begin
  -- Prevent changing id or user_id
  if new.id != old.id or new.user_id != old.user_id then
    raise exception 'Cannot change id or user_id';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger collections_prevent_key_changes_trigger
before update on collections
for each row
execute function collections_prevent_key_changes();

-- Add date management triggers
create trigger collections_update_dates
before update on collections
for each row
execute function update_dates();

create trigger collections_insert_dates
before insert on collections
for each row
execute function insert_dates();

-- Enable RLS
alter table collections enable row level security;

-- Allow read for public collections and own collections
create policy collections_select on collections
for select
to authenticated, anon
using (
  not private
  or user_id = (select auth.uid())
);

-- Allow creation for own collections only
create policy collections_insert on collections
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Allow update for own collections only
create policy collections_update on collections
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Allow deletion for own collections only
create policy collections_delete on collections
for delete
to authenticated
using ((select auth.uid()) = user_id);