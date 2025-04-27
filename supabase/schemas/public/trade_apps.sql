-- Create trade_apps table
create table trade_apps (
  trade_id uuid not null references trades(id) on delete cascade,
  app_id integer not null references apps(id) on delete cascade,
  collection_id text references collections(id) on delete set null default null,
  vault_entry_id uuid references vault_entries(id) on delete set null default null,
  user_id uuid not null references users(id) on delete cascade,
  mandatory boolean default false,
  selected boolean default false,
  snapshot jsonb default null,
  updated_at timestamptz default null,
  created_at timestamptz default now(),
  primary key (trade_id, user_id, app_id)
);

-- Add table comment
comment on table trade_apps is 'Apps included in trades';

-- Create trigger function to handle mandatory selection
create or replace function trade_apps_handle_mandatory()
returns trigger
set search_path = ''
as $$
begin
  if new.mandatory = true then
    new.selected = true;
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to store app snapshot
create or replace function trade_apps_store_snapshot()
returns trigger
set search_path = ''
as $$
declare
  app_data jsonb;
  tag_data jsonb;
  filtered_app jsonb;
begin
  -- Initialize the snapshot JSON if null
  if new.snapshot is null then
    new.snapshot := jsonb_build_object();
  end if;

  -- Get the complete app data
  select row_to_json(a)::jsonb into app_data
  from public.apps a
  where a.id = new.app_id;

  -- Filter app data to only include relevant fields
  filtered_app := jsonb_build_object(
    'free', app_data->'free',
    'plus_one', app_data->'plus_one',
    'exfgls', app_data->'exfgls',
    'steamdeck', app_data->'steamdeck',
    'positive_reviews', app_data->'positive_reviews',
    'negative_reviews', app_data->'negative_reviews',
    'cards', app_data->'cards',
    'achievements', app_data->'achievements',
    'bundles', app_data->'bundles',
    'giveaways', app_data->'giveaways',
    'libraries', app_data->'libraries',
    'wishlists', app_data->'wishlists',
    'tradelists', app_data->'tradelists',
    'blacklists', app_data->'blacklists',
    'steam_packages', app_data->'steam_packages',
    'steam_bundles', app_data->'steam_bundles',
    'retail_price', app_data->'retail_price',
    'discounted_price', app_data->'discounted_price',
    'market_price', app_data->'market_price',
    'historical_low', app_data->'historical_low',
    'removed_as', app_data->'removed_as',
    'removed_at', app_data->'removed_at',
    'updated_at', app_data->'updated_at'
  );

  -- Store collection tag data if exists
  select row_to_json(t)::jsonb into tag_data
  from public.collection_tags t
  where t.collection_id = new.collection_id
  and t.app_id = new.app_id;

  -- Build the complete snapshot
  new.snapshot := jsonb_build_object(
    'app', filtered_app,
    'tags', tag_data
  );

  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to validate field updates
create or replace function trade_apps_validate_updates()
returns trigger
set search_path = ''
as $$
begin
  -- Prevent updating certain fields
  if new.trade_id != old.trade_id or 
    new.user_id != old.user_id or 
    new.app_id != old.app_id or 
    new.collection_id != old.collection_id or 
    new.snapshot != old.snapshot then
    raise exception 'Cannot update trade_id, user_id, app_id, collection_id, or snapshot';
  end if;

  -- Validate mandatory updates
  if new.mandatory != old.mandatory and (
    not exists (
      select 1 from public.trades
      where id = new.trade_id
      and status = 'pending'
      and sender_id = (select auth.uid())
    )
  ) then
    raise exception 'Only sender can update mandatory on pending trades';
  end if;

  -- Validate selected updates
  if new.selected != old.selected and (
    not exists (
      select 1 from public.trades
      where id = new.trade_id
      and status = 'pending'
      and receiver_id = (select auth.uid())
    )
  ) then
      raise exception 'Only receiver can update selected on pending trades';
  end if;

  -- Validate vault_entry_id updates
  if new.vault_entry_id != old.vault_entry_id and (
    exists (
      select 1 from public.trades
      where id = new.trade_id
      and status = 'completed'
    ) or
    new.user_id != (select auth.uid())
  ) then
    raise exception 'Invalid vault_entry_id update';
  end if;

  return new;
end;
$$ language plpgsql;

-- Create triggers
create trigger trade_apps_ensure_app_exists
before insert on trade_apps
for each row
execute function ensure_app_exists();

create trigger trade_apps_handle_mandatory_trigger
before insert or update of mandatory on trade_apps
for each row
execute function trade_apps_handle_mandatory();

create trigger trade_apps_store_snapshot_trigger
before insert on trade_apps
for each row
execute function trade_apps_store_snapshot();

create trigger trade_apps_validate_updates_trigger
before update on trade_apps
for each row
execute function trade_apps_validate_updates();

-- Add date management triggers
create trigger trade_apps_update_dates
before update on trade_apps
for each row
execute function update_dates();

create trigger trade_apps_insert_dates
before insert on trade_apps
for each row
execute function insert_dates();

-- Create policies
alter table trade_apps enable row level security;

-- Allow read for all users
create policy trade_apps_select on trade_apps
for select
to authenticated, anon
using (true);

-- Allow creation with multiple conditions
create policy trade_apps_insert on trade_apps
for insert
to authenticated
with check (
  exists (
    select 1 from trades
    where
      id = trade_id
      and sender_id = (select auth.uid())
      and status = 'pending'
  )
);

-- Allow update for your own trades
create policy trade_apps_update on trade_apps
for update
to authenticated
using (
  exists (
    select 1 from trades
    where
      id = trade_id
      and sender_id = (select auth.uid())
       or receiver_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from trades
    where
      id = trade_id
      and sender_id = (select auth.uid())
       or receiver_id = (select auth.uid())
  )
);

-- Allow deletion with multiple conditions
create policy trade_apps_delete on trade_apps
for delete
to authenticated
using (
  exists (
    select 1 from trades
    where
      id = trade_id
      and sender_id = (select auth.uid())
      and status = 'pending'
  )
);