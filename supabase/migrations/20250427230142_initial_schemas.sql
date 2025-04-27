-- Initial schema migration created on 2025-04-27T21:01:42.438Z
set check_function_bodies=off;

-- ============================================================================
-- Schema file: ./schemas/public/common.sql
-- ============================================================================

-- Enable cron extension
create extension pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- Function to bulk upsert records into a table
create or replace function bulk_upsert(
  p_table text,
  p_records jsonb,
  p_update_fields text[],
  p_conflict_fields text[]
)
returns integer
set search_path = ''
as $$
declare
  v_row_count integer;
  v_sql text;
  v_update_clause text := '';
  v_columns_list text := '';
  v_columns_def text := '';
  v_all_fields text[];
  v_upd_only text[];
  v_schema_name text;
  v_table_name text;
  v_conflict_target text;
  r_column_type text;
begin
  -- 1) validate input arrays
  if array_length(p_conflict_fields,1) is null or array_length(p_conflict_fields,1) = 0 then
    raise exception 'bulk_upsert: p_conflict_fields cannot be empty';
  end if;
  if array_length(p_update_fields,1) is null or array_length(p_update_fields,1) = 0 then
    raise exception 'bulk_upsert: p_update_fields cannot be empty';
  end if;

  -- 2) split schema and table
  if p_table like '%.%' then
    v_schema_name := split_part(p_table, '.', 1);
    v_table_name := split_part(p_table, '.', 2);
  else
    v_schema_name := 'public';
    v_table_name := p_table;
  end if;

  -- 3) combine and dedupe fields
  v_all_fields := (
    select array_agg(distinct f)
    from unnest(p_update_fields || p_conflict_fields) as f
  );

  -- 4) build columns_list and definitions with data types from pg_catalog
  for i in 1..array_length(v_all_fields, 1) loop
    select format_type(a.atttypid, null) into r_column_type
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid = a.attrelid
    join pg_catalog.pg_namespace n on c.relnamespace = n.oid
    where n.nspname = v_schema_name
      and c.relname = v_table_name
      and a.attname = v_all_fields[i]
      and a.attnum > 0
      and not a.attisdropped;

    if r_column_type is null then
      raise exception 'bulk_upsert: column "%" not found in table "%.%": variant or typo?', 
        v_all_fields[i], v_schema_name, v_table_name;
    end if;

    if i > 1 then
      v_columns_list := v_columns_list || ', ';
      v_columns_def := v_columns_def || ', ';
    end if;

    v_columns_list := v_columns_list || quote_ident(v_all_fields[i]);
    v_columns_def := v_columns_def || quote_ident(v_all_fields[i]) || ' ' || r_column_type;
  end loop;

  -- 5) build conflict_target
  v_conflict_target := array_to_string(
    array(
      select quote_ident(c)
      from unnest(p_conflict_fields) as c
    ), ', ');
  if v_conflict_target = '' then
    raise exception 'bulk_upsert: conflict_target ended up empty; inputs: %', 
      array_to_string(p_conflict_fields, ', ');
  end if;
  raise notice 'bulk_upsert: conflict_target = %', v_conflict_target;

  -- 6) filter update_fields to exclude conflict_fields
  v_upd_only := (
    select array_agg(f)
    from unnest(p_update_fields) as f
    where not (f = any(p_conflict_fields))
  );

  -- 7) build update_clause if applicable
  if array_length(v_upd_only, 1) is not null then
    for i in 1..array_length(v_upd_only, 1) loop
      if i > 1 then
        v_update_clause := v_update_clause || ', ';
      end if;
      v_update_clause := v_update_clause || quote_ident(v_upd_only[i]) || ' = excluded.' || quote_ident(v_upd_only[i]);
    end loop;
  end if;

  -- 8) assemble final sql
  if v_update_clause <> '' then
    v_sql := format('
      insert into %I.%I (%s)
      select %s
      from jsonb_array_elements($1) with ordinality as items(elem, ordinality)
      left join lateral jsonb_to_record(items.elem) as x(%s) on true
      order by items.ordinality
      on conflict (%s) do update set %s',
      v_schema_name,
      v_table_name,
      v_columns_list,
      v_columns_list,
      v_columns_def,
      v_conflict_target,
      v_update_clause
    );
  else
    v_sql := format('
      insert into %I.%I (%s)
      select %s
      from jsonb_array_elements($1) with ordinality as items(elem, ordinality)
      left join lateral jsonb_to_record(items.elem) as x(%s) on true
      order by items.ordinality
      on conflict (%s) do nothing',
      v_schema_name,
      v_table_name,
      v_columns_list,
      v_columns_list,
      v_columns_def,
      v_conflict_target
    );
  end if;

  -- 9) execute and return affected row count
  execute v_sql using p_records;
  get diagnostics v_row_count = row_count;
  return v_row_count;
end;
$$ language plpgsql security invoker
set statement_timeout TO '300s';

-- Function to bulk insert records into a table
create or replace function bulk_insert(p_table text, p_records jsonb)
returns void
set search_path = ''
as $$
declare
  v_schema_name text;
  v_table_name text;
begin
  -- Split schema and table name
  if p_table like '%.%' then
    v_schema_name := split_part(p_table, '.', 1);
    v_table_name := split_part(p_table, '.', 2);
  else
    v_schema_name := 'public';
    v_table_name := p_table;
  end if;

  -- Execute dynamic SQL for bulk insert
  execute format(
    'insert into %I.%I select * from jsonb_populate_recordset(null::%I.%I, %L)',
    v_schema_name, v_table_name, v_schema_name, v_table_name, p_records
  );
end;
$$ language plpgsql security invoker
set statement_timeout TO '300s';

-- Function to automatically update timestamps on row updates
create or replace function update_dates()
returns trigger
set search_path = ''
as $$
declare
  column_exists boolean;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_name = tg_table_name
      and column_name = 'updated_at'
  ) into column_exists;

  if column_exists then
    new.updated_at = now();
  end if;
  new.created_at = old.created_at;

  return new;
end;
$$ language plpgsql security invoker;

-- Function to set initial timestamps on row inserts
create or replace function insert_dates()
returns trigger
set search_path = ''
as $$
declare
  column_exists boolean;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_name = tg_table_name
      and column_name = 'updated_at'
  ) into column_exists;

  if current_user != 'service_role' then
    new.created_at = now();
  end if;

  if column_exists then
    new.updated_at = null;
  end if;

  return new;
end;
$$ language plpgsql security invoker; 

-- Create the 'avatars' bucket
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true);

-- Allow read access for all users
create policy avatars_select on storage.objects
for select
to authenticated, anon
using (bucket_id = 'avatars');

-- Allow creation for authenticated users (upload their own avatars)
create policy avatars_insert on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
);

-- Allow update for own avatars only
create policy avatars_update on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
)
with check (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
);

-- Allow deletion for own avatars only
create policy avatars_delete on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
);

-- Create the 'backgrounds' bucket
insert into storage.buckets (id, name, public)
values ('backgrounds', 'backgrounds', true);

-- Allow read access for all users
create policy backgrounds_select on storage.objects
for select
to authenticated, anon
using (bucket_id = 'backgrounds');

-- Allow creation for authenticated users (upload their own backgrounds)
create policy backgrounds_insert on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
);

-- Allow update for own backgrounds only
create policy backgrounds_update on storage.objects
for update
to authenticated
using (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
)
with check (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
);

-- Allow deletion for own backgrounds only
create policy backgrounds_delete on storage.objects
for delete
to authenticated
using (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
);

-- Create the 'assets' bucket
insert into storage.buckets (id, name, public)
values ('assets', 'assets', true);

-- Allow read access for all users
create policy assets_select on storage.objects
for select
to authenticated, anon
using (bucket_id = 'assets');

-- Disallow creation for all users
-- Disallow updates for all users
-- Disallow deletion for all users

-- Function to add collection app
create or replace function add_collection_app(p_collection_id text, p_app_id integer, p_title text)
returns void
set search_path = ''
as $$
begin
  -- Check if collection_id exists in collections, if not insert it
  if not exists (select 1 from public.collections where id = p_collection_id) then
    insert into public.collections (id, private, user_id, type, title, description)
    values (p_collection_id, false, null, 'app', p_title, 'Auto-generated');
  end if;

  -- Insert into collection_apps
  insert into public.collection_apps (collection_id, app_id, source)
  values (p_collection_id, p_app_id, 'sync')
  on conflict do nothing;
end;
$$ language plpgsql security invoker;

-- Function to remove collection app
create or replace function remove_collection_app(p_collection_id text, p_app_id integer)
returns void
set search_path = ''
as $$
begin
  delete from public.collection_apps
  where app_id = p_app_id
  and collection_id = p_collection_id;
end;
$$ language plpgsql security invoker;

-- Enable unaccent extension
create extension unaccent with schema extensions;

-- Function to slugify a string
create or replace function slugify(v text)
returns text
set search_path = ''
as $$
begin
  return regexp_replace(
    regexp_replace(
      -- Lowercase and remove accents in one step
      lower(extensions.unaccent(v)),
      -- Replace non-alphanumeric characters with hyphens
      '[^a-z0-9\\-_]+', '-', 'gi'
    ),
    -- Remove leading and trailing hyphens
    '(^-+|-+$)', '', 'g'
  );
end
$$ language plpgsql strict immutable security invoker;

-- Function to call a Supabase Edge Function (JWT verification disabled)
create or replace function call_edge_function(
  p_name text,
  p_body jsonb default '{}'::jsonb
)
returns void
set search_path = ''
as $$
declare
  project_id text;
  function_url text;
begin
  select decrypted_secret 
  into project_id
  from vault.decrypted_secrets
  where name = 'project_id'
  limit 1;
  
  if project_id is null then
    function_url := 'http://host.docker.internal:54321/functions/v1/' || p_name;
  else
    function_url := 'https://' || project_id || '.supabase.co/functions/v1/' || p_name;
  end if;
  
  perform net.http_post(
    url := function_url,
    body := p_body,
    headers := '{"content-type":"application/json"}'::jsonb,
    timeout_milliseconds := 100000
  );
  
  return;
end;
$$ language plpgsql security invoker;

-- ============================================================================
-- Schema file: ./schemas/public/updater_queue.sql
-- ============================================================================

-- Create updater queue type enum
create type updater_queue_type as enum (
  'app_names_check',
  'app_types_check',
  'app_cards_check',
  'app_removals_check',
  'app_list_check',
  'change_number',
  'ggdeals_deals_check',
  'ggdeals_bundles_check',
  'app_update'
);

-- Create updater_queue table
create table updater_queue (
  id uuid primary key default gen_random_uuid(),
  type updater_queue_type not null,
  value text default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table updater_queue is 'Queue for background update tasks';

-- Enable RLS
alter table updater_queue enable row level security;

-- Add date management triggers
create trigger updater_queue_update_dates
before update on updater_queue
for each row
execute function update_dates();

create trigger updater_queue_insert_dates
before insert on updater_queue
for each row
execute function insert_dates();

-- Function to add new apps to the updater queue
create or replace function updater_enqueue(p_appids int[])
returns void
set search_path = ''
as $$
begin
  insert into public.updater_queue (type, value)
  select 'app_update', unnest(p_appids)::text;
end;
$$ language plpgsql security invoker
set statement_timeout to '300s';

-- Function to extract apps from the updater queue
create or replace function updater_dequeue(p_count int)
returns int[]
set search_path = ''
as $$
with to_delete as (
  select id, value
  from public.updater_queue
  where type = 'app_update'
  order by created_at asc
  limit p_count
),
deleted as (
  delete from public.updater_queue
  where id in (select id from to_delete)
  returning value
)
select coalesce(array_agg(value::int), array[]::int[])
from deleted;
$$ language sql security invoker;

-- ============================================================================
-- Schema file: ./schemas/public/apps.sql
-- ============================================================================

-- Create app type enum
create type app_type as enum (
  'unknown',
  'advertising',
  'application',
  'beta',
  'comic',
  'config',
  'demo',
  'depotonly',
  'dlc',
  'driver',
  'episode',
  'franchise',
  'game',
  'guide',
  'hardware',
  'media',
  'mod',
  'movie',
  'music',
  'plugin',
  'series',
  'shortcut',
  'software',
  'tool',
  'video'
);

-- Create apps table
create table apps (
  id integer primary key,
  change_number integer default null,
  parent_id integer references apps(id) on delete set null default null,
  title text default null,
  alt_titles text[] default null,
  type app_type default 'unknown' not null,
  description text default null,
  developers text[] default null,
  publishers text[] default null,
  tags text[] default null,
  languages text[] default null,
  platforms text[] default null,
  website text default null,
  free boolean default null,
  plus_one boolean default null,
  exfgls boolean default null,
  steamdeck text default null,
  header text default null,
  screenshots text[] default null,
  videos text[] default null,
  positive_reviews integer default null,
  negative_reviews integer default null,
  cards integer default null,
  achievements integer default null,
  bundles integer default null,
  giveaways integer default null,
  libraries integer default null,
  wishlists integer default null,
  tradelists integer default null,
  blacklists integer default null,
  steam_packages integer default null,
  steam_bundles integer default null,
  retail_price numeric default null,
  discounted_price numeric default null,
  market_price numeric default null,
  historical_low numeric default null,
  removed_as text default null,
  removed_at timestamptz default null,
  released_at timestamptz default null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table apps is 'Steam applications with metadata and statistics';

-- Create trigger function to ensure app exists
create or replace function ensure_app_exists()
returns trigger
set search_path = ''
as $$
declare
  key_value text;
  v_app_id integer;
begin
  -- Convert NEW record to JSONB and pick the first available key.
  key_value := coalesce(to_jsonb(new)->>'app_id', to_jsonb(new)->>'parent_id');

  if key_value is null then
    return new;
  end if;

  v_app_id := key_value::integer;

  -- If the app record does not exist in public.apps, insert a stub record
  if not exists (select 1 from public.apps where id = v_app_id) then
    insert into public.apps (id) values (v_app_id);
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- Create trigger function to handle title changes
create or replace function apps_handle_title_change()
returns trigger
set search_path = ''
as $$
begin
  -- If title changed, append old title to alt_titles
  if new.title != old.title then
    new.alt_titles = array_remove(
      array(
        select distinct unnest(
          array_prepend(
            old.title,
            coalesce(old.alt_titles, array[]::text[])
          )
        )
      ),
      new.title
    );
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to manage collections
create or replace function apps_manage_collections()
returns trigger
set search_path = ''
as $$
declare
  item text;
begin
  -- Remove old collections if values changed
  if tg_op = 'UPDATE' then
    -- Type collection
    if old.type is not null and (new.type is null or new.type != old.type) then
      perform public.remove_collection_app('type-' || public.slugify(old.type::text), new.id);
    end if;

    -- Developer collections
    if old.developers is not null then
      foreach item in array old.developers loop
        perform public.remove_collection_app('developer-' || public.slugify(item), new.id);
      end loop;
    end if;

    -- Publisher collections
    if old.publishers is not null then
      foreach item in array old.publishers loop
        perform public.remove_collection_app('publisher-' || public.slugify(item), new.id);
      end loop;
    end if;

    -- Tag collections
    if old.tags is not null then
      foreach item in array old.tags loop
        perform public.remove_collection_app('tag-' || public.slugify(item), new.id);
      end loop;
    end if;

    -- Language collections
    if old.languages is not null then
      foreach item in array old.languages loop
        perform public.remove_collection_app('language-' || public.slugify(item), new.id);
      end loop;
    end if;

    -- Platform collections
    if old.platforms is not null then
      foreach item in array old.platforms loop
        perform public.remove_collection_app('platform-' || public.slugify(item), new.id);
      end loop;
    end if;

    -- Other collections
    if (old.free is true or old.retail_price = 0) and
       (new.free is false and new.retail_price != 0) then
      perform public.remove_collection_app('free', new.id);
    end if;

    if old.plus_one is true and new.plus_one is false then
      perform public.remove_collection_app('plus-one', new.id);
    end if;

    if old.exfgls is true and new.exfgls is false then
      perform public.remove_collection_app('exfgls', new.id);
    end if;

    if old.steamdeck is not null and
       (new.steamdeck is null or new.steamdeck not in ('Playable', 'Verified')) then
      perform public.remove_collection_app('steamdeck', new.id);
    end if;

    if old.cards > 0 and (new.cards is null or new.cards = 0) then
      perform public.remove_collection_app('with-cards', new.id);
    end if;

    if old.achievements > 0 and (new.achievements is null or new.achievements = 0) then
      perform public.remove_collection_app('with-achievements', new.id);
    end if;

    if old.bundles > 0 and (new.bundles is null or new.bundles = 0) then
      perform public.remove_collection_app('bundled', new.id);
    end if;

    if old.giveaways > 0 and (new.giveaways is null or new.giveaways = 0) then
      perform public.remove_collection_app('givenaway', new.id);
    end if;

    if old.removed_at is not null and new.removed_at is null then
      perform public.remove_collection_app('removed', new.id);
    end if;

    if old.removed_as is not null and
       (new.removed_as is null or new.removed_as != old.removed_as) then
      perform public.remove_collection_app('removed-' || public.slugify(old.removed_as), new.id);
    end if;
  end if;

  -- Add new collections
  -- Type collection
  if new.type is not null then
    perform public.add_collection_app('type-' || public.slugify(new.type::text), new.id, initcap(new.type::text) || ' (type)');
  end if;

  -- Developer collections
  if new.developers is not null then
    foreach item in array new.developers loop
      perform public.add_collection_app('developer-' || public.slugify(item), new.id, initcap(item) || ' (developer)');
    end loop;
  end if;

  -- Publisher collections
  if new.publishers is not null then
    foreach item in array new.publishers loop
      perform public.add_collection_app('publisher-' || public.slugify(item), new.id, initcap(item) || ' (publisher)');
    end loop;
  end if;

  -- Tag collections
  if new.tags is not null then
    foreach item in array new.tags loop
      perform public.add_collection_app('tag-' || public.slugify(item), new.id, initcap(item) || ' (tag)');
    end loop;
  end if;

  -- Language collections
  if new.languages is not null then
    foreach item in array new.languages loop
      perform public.add_collection_app('language-' || public.slugify(item), new.id, initcap(item) || ' (language)');
    end loop;
  end if;

  -- Platform collections
  if new.platforms is not null then
    foreach item in array new.platforms loop
      perform public.add_collection_app('platform-' || public.slugify(item), new.id, initcap(item) || ' (platform)');
    end loop;
  end if;

  -- Other collections
  if new.free is true or new.retail_price = 0 then
    perform public.add_collection_app('free', new.id, 'Free');
  end if;

  if new.plus_one is true then
    perform public.add_collection_app('plus-one', new.id, 'Plus One');
  end if;

  if new.exfgls is true then
    perform public.add_collection_app('exfgls', new.id, 'Excluded from Library Sharing');
  end if;

  if new.steamdeck in ('Playable', 'Verified') then
    perform public.add_collection_app('steamdeck', new.id, 'SteamDeck Compatible');
  end if;

  if new.cards > 0 then
    perform public.add_collection_app('with-cards', new.id, 'With Cards');
  end if;

  if new.achievements > 0 then
    perform public.add_collection_app('with-achievements', new.id, 'With Achievements');
  end if;

  if new.bundles > 0 then
    perform public.add_collection_app('bundled', new.id, 'Bundled');
  end if;

  if new.giveaways > 0 then
    perform public.add_collection_app('givenaway', new.id, 'Givenaway');
  end if;

  if new.removed_at is not null then
    perform public.add_collection_app('removed', new.id, 'Removed');
  end if;

  if new.removed_as is not null then
    perform public.add_collection_app('removed-' || public.slugify(new.removed_as), new.id, initcap(new.removed_as));
  end if;

  return new;
end;
$$ language plpgsql security invoker;

-- Cron job to call app update Superbase Edge function
select cron.schedule('call_app_update', '*/5 * * * *', $$
  select public.call_edge_function('app-update');
$$);

-- Create function to return app metadata dump
create or replace function get_apps_metadata()
returns jsonb
set search_path = ''
as $$
declare
  result jsonb;
begin
  if current_user != 'service_role' then
    raise exception 'access denied: service_role required';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'id', a.id,
      'header', a.header,
      'title', a.title,
      'alt_titles', a.alt_titles
    )
    order by a.id
  )
  into result
  from public.apps a
  where a.title is not null;

  return result;
end;
$$ language plpgsql security invoker;

-- Cron job to call app metadata dump Supabase Edge function
select cron.schedule('call_app_metadata_dump', '0 0 * * *', $$
  select public.call_edge_function('app-metadata-dump');
$$);

-- Create triggers
create trigger apps_ensure_parent_exists
before insert on apps
for each row
execute function ensure_app_exists();

create trigger apps_handle_title_change_trigger
before update of title on apps
for each row
execute function apps_handle_title_change();

create trigger apps_manage_collections_trigger
after insert or update on apps
for each row
execute function apps_manage_collections();

-- Add date management triggers
create trigger apps_update_dates
before update on apps
for each row
execute function update_dates();

create trigger apps_insert_dates
before insert on apps
for each row
execute function insert_dates();

-- Enable RLS
alter table apps enable row level security;

-- Allow read access for all users
create policy apps_select on apps
for select
to authenticated, anon
using (true);

-- Disallow creation for all users
-- Disallow update for all users
-- Disallow deletion for all users

-- ============================================================================
-- Schema file: ./schemas/public/tags.sql
-- ============================================================================

-- Create tag type enum
create type tag_type as enum (
  'vault',
  'blacklist',
  'bundle',
  'custom',
  'giveaway',
  'library',
  'steam_bundle',
  'steam_package',
  'tradelist',
  'wishlist'
);

-- Create tags table
create table tags (
  id integer generated by default as identity primary key,
  title text not null unique,
  type tag_type,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table tags is 'Tags for categorizing items in collections and vaults';

-- Add date management triggers
create trigger tags_update_dates
before update on tags
for each row
execute function update_dates();

create trigger tags_insert_dates
before insert on tags
for each row
execute function insert_dates();

-- Enable RLS
alter table tags enable row level security;

-- Allow read access for all users
create policy tags_select on tags
for select
to authenticated, anon
using (true);

-- Disallow creation for all users
-- Disallow updates for all users
-- Disallow deletions for all users

-- ============================================================================
-- Schema file: ./schemas/public/users.sql
-- ============================================================================

-- Create region enum
create type country_code as enum (
  'AF', 'AL', 'DZ', 'AS', 'AD', 'AO', 'AI', 'AQ', 'AG', 'AR', 'AM', 'AW', 'AU', 'AT', 'AZ',
  'BS', 'BH', 'BD', 'BB', 'BY', 'BE', 'BZ', 'BJ', 'BM', 'BT', 'BO', 'BQ', 'BA', 'BW', 'BV',
  'BR', 'IO', 'BN', 'BG', 'BF', 'BI', 'CV', 'KH', 'CM', 'CA', 'KY', 'CF', 'TD', 'CL', 'CN',
  'CX', 'CC', 'CO', 'KM', 'CD', 'CG', 'CK', 'CR', 'HR', 'CU', 'CW', 'CY', 'CZ', 'CI', 'DK',
  'DJ', 'DM', 'DO', 'EC', 'EG', 'SV', 'GQ', 'ER', 'EE', 'SZ', 'ET', 'FK', 'FO', 'FJ', 'FI',
  'FR', 'GF', 'PF', 'TF', 'GA', 'GM', 'GE', 'DE', 'GH', 'GI', 'GR', 'GL', 'GD', 'GP', 'GU',
  'GT', 'GG', 'GN', 'GW', 'GY', 'HT', 'HM', 'VA', 'HN', 'HK', 'HU', 'IS', 'IN', 'ID', 'IR',
  'IQ', 'IE', 'IM', 'IL', 'IT', 'JM', 'JP', 'JE', 'JO', 'KZ', 'KE', 'KI', 'KP', 'KR', 'KW',
  'KG', 'LA', 'LV', 'LB', 'LS', 'LR', 'LY', 'LI', 'LT', 'LU', 'MO', 'MG', 'MW', 'MY', 'MV',
  'ML', 'MT', 'MH', 'MQ', 'MR', 'MU', 'YT', 'MX', 'FM', 'MD', 'MC', 'MN', 'ME', 'MS', 'MA',
  'MZ', 'MM', 'NA', 'NR', 'NP', 'NL', 'NC', 'NZ', 'NI', 'NE', 'NG', 'NU', 'NF', 'MP', 'NO',
  'OM', 'PK', 'PW', 'PS', 'PA', 'PG', 'PY', 'PE', 'PH', 'PN', 'PL', 'PT', 'PR', 'QA', 'MK',
  'RO', 'RU', 'RW', 'RE', 'BL', 'SH', 'KN', 'LC', 'MF', 'PM', 'VC', 'WS', 'SM', 'ST', 'SA',
  'SN', 'RS', 'SC', 'SL', 'SG', 'SX', 'SK', 'SI', 'SB', 'SO', 'ZA', 'GS', 'SS', 'ES', 'LK',
  'SD', 'SR', 'SJ', 'SE', 'CH', 'SY', 'TW', 'TJ', 'TZ', 'TH', 'TL', 'TG', 'TK', 'TO', 'TT',
  'TN', 'TR', 'TM', 'TC', 'TV', 'UG', 'UA', 'AE', 'GB', 'UM', 'US', 'UY', 'UZ', 'VU', 'VE',
  'VN', 'VG', 'VI', 'WF', 'EH', 'YE', 'ZM', 'ZW', 'AX'
);

-- Create users table
create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  steam_id text not null unique,
  custom_url text default null unique check (
    -- Custom URL must be alphanumeric
    (custom_url ~ '^[a-zA-Z0-9]+$')
    -- Custom URL must be between 1 and 32 characters
    and (custom_url is null or length(custom_url) between 1 and 32)
    -- Custom URL must not be a Steam ID
    and (custom_url !~ '^76561\d{12}$')
  ),
  display_name text default null,
  avatar text default null,
  background text default null,
  bio text default null,
  region country_code default null,
  public_key text default null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table users is 'User profiles';

-- Enable realtime for this table
alter publication supabase_realtime add table users;

-- Create trigger function to prevent changing certain fields
create or replace function users_prevent_key_changes()
returns trigger
set search_path = ''
as $$
begin
  -- Prevent changing id or steam_id
  if new.id != old.id or new.steam_id != old.steam_id then
    raise exception 'Cannot change id or steam_id';
  end if;

  -- Prevent changing public_key if already set
  if old.public_key is not null and new.public_key != old.public_key then
    raise exception 'Cannot change public_key once set';
  end if;

  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger users_prevent_key_changes_trigger
before update on users
for each row
execute function users_prevent_key_changes();

-- Add date management triggers
create trigger users_update_dates
before update on users
for each row
execute function update_dates();

create trigger users_insert_dates
before insert on users
for each row
execute function insert_dates();

-- Enable RLS
alter table users enable row level security;

-- Allow read access for all users
create policy users_select on users
for select
to authenticated, anon
using (true);

-- Allow update for own profile only
create policy users_update on users
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- Disallow deletion for all users

-- ============================================================================
-- Schema file: ./schemas/public/collections.sql
-- ============================================================================

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

-- ============================================================================
-- Schema file: ./schemas/public/credentials.sql
-- ============================================================================

-- Create credentials table
create table credentials (
  user_id uuid primary key references users(id) on delete cascade,
  encrypted_data text not null,
  iv text not null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table credentials is 'Encrypted user credentials';

-- Add date management triggers
create trigger credentials_update_dates
before update on credentials
for each row
execute function update_dates();

create trigger credentials_insert_dates
before insert on credentials
for each row
execute function insert_dates();

-- Enable RLS
alter table credentials enable row level security;

-- Allow read access for own credentials only
create policy credentials_select on credentials
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Allow creation of own credentials only
create policy credentials_insert on credentials
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Disallow updates for all users
-- Disallow deletion for all users

-- ============================================================================
-- Schema file: ./schemas/public/notifications.sql
-- ============================================================================

-- Create notification enum
create type notification as enum (
  'new_trade', 'accepted_trade', 'new_vault_entry', 'unread_messages'
);

-- Create notifications table
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type notification not null,
  link text default null check (
    -- Link must be a valid web URL or relative path
    link ~ '^(https?:\/\/[^\s/$.?#].[^\s]*)|(^\/[^\s]*)$'
  ),
  read boolean not null default false,
  created_at timestamptz default now()
);

-- Add table comment
comment on table notifications is 'User notifications for various events';

-- Enable realtime for this table
alter publication supabase_realtime add table notifications;

-- Add date management triggers
create trigger notifications_update_dates
before update on notifications
for each row
execute function update_dates();

create trigger notifications_insert_dates
before insert on notifications
for each row
execute function insert_dates();

-- Create trigger function to prevent changing any column except 'read'
create or replace function notifications_restrict_column_changes()
returns trigger
set search_path = ''
as $$
begin
  IF (old.user_id != new.user_id OR 
      old.type != new.type OR 
      old.link != new.link OR 
      old.created_at != new.created_at) THEN
    raise exception 'Only the "read" column can be updated in notifications';
  END IF;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger notifications_restrict_changes
before update on notifications
for each row
execute function notifications_restrict_column_changes();

-- Enable RLS
alter table notifications enable row level security;

-- Allow read access for own notifications only
create policy notifications_select on notifications
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Disallow creation for all users

-- Allow update for own notifications only
create policy notifications_update on notifications
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Disallow deletion for all users

-- ============================================================================
-- Schema file: ./schemas/public/trades.sql
-- ============================================================================

-- Create trade status enum
create type trade_status as enum (
  'pending', 'accepted', 'declined', 'aborted', 'completed'
);

-- Create trade activity type enum
create type trade_activity_type as enum (
  'edited',
  'created',
  'accepted',
  'declined',
  'aborted',
  'completed',
  'disputed',
  'resolved',
  'countered'
);

-- Create trades table
create table trades (
  id uuid primary key default gen_random_uuid(),
  original_id uuid references trades(id) on delete cascade default null,
  status trade_status not null,
  sender_id uuid references users(id) on delete set null default null,
  sender_disputed boolean default false,
  sender_vaultless boolean default false,
  sender_total integer default 0 check (sender_total >= 0),
  receiver_id uuid references users(id) on delete set null default null,
  receiver_disputed boolean default false,
  receiver_vaultless boolean default false,
  receiver_total integer default 0 check (receiver_total >= 0),
  criteria jsonb default null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table trades is 'Trade offers between users';

-- Create trigger function to validate trade creation
create or replace function trades_validate_creation()
returns trigger
set search_path = ''
as $$
begin
  -- Check if original trade exists and is valid for counter-offer
  if new.original_id is not null then
    if not exists (
      select 1 from public.trades
      where id = new.original_id
      and status = 'pending'
      and receiver_id = new.sender_id
    ) then
      raise exception 'Invalid original trade for counter-offer';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to validate status changes
create or replace function trades_validate_status_change()
returns trigger
set search_path = ''
as $$
begin
  -- Status change validations
  if new.status != old.status then
    case new.status
      when 'aborted' then
        if old.status != 'accepted' then
          raise exception 'Can only abort accepted trades';
        end if;
      when 'accepted' then
        if old.status != 'pending' or (select auth.uid()) != new.receiver_id then
          raise exception 'Only receiver can accept pending trades';
        end if;
      when 'declined' then
        if old.status != 'pending' or (select auth.uid()) != new.receiver_id then
          raise exception 'Only receiver can decline pending trades';
        end if;
      when 'completed' then
        if old.status not in ('accepted', 'pending') or 
          -- Enforce both vaultless flags to be equal.
          new.sender_vaultless <> new.receiver_vaultless or
          -- If both are false then check that all selected trade apps have a vault entry assigned.
          (
            new.sender_vaultless = false and 
            exists (
              select 1 from public.trade_apps
              where trade_id = new.id
                and selected = true
                and vault_entry_id is null
            )
          ) or
          -- If both are false then check that all assigned vault entries have a value for both sender and receiver.
          (
            new.sender_vaultless = false and 
            exists (
              select 1 from public.vault_entries ve
              join public.trade_apps ta on ta.vault_entry_id = ve.id
              where ta.trade_id = new.id
                and ta.selected = true
                and ve.trade_id is null
                and (
                  not exists (
                    select 1 from public.vault_values vv
                    where vv.vault_entry_id = ve.id
                      and vv.receiver_id = new.sender_id
                  ) or 
                  not exists (
                    select 1 from public.vault_values vv
                    where vv.vault_entry_id = ve.id
                      and vv.receiver_id = new.receiver_id
                  )
                )
            )
          ) or
          -- Verify that the count of selected sender trade apps equals the expected sender_total.
          not exists (
            select 1 from public.trade_apps
            where trade_id = new.id
              and user_id = new.sender_id
              and selected = true
            group by trade_id
            having count(*) = new.sender_total
          ) or
          -- Verify that the count of selected receiver trade apps equals the expected receiver_total.
          not exists (
            select 1 from public.trade_apps
            where trade_id = new.id
              and user_id = new.receiver_id
              and selected = true
            group by trade_id
            having count(*) = new.receiver_total
          )
        then
            raise exception 'Invalid conditions for completing trade';
        end if;
    else
        raise exception 'Invalid status change';
    end case;
    end if;
  return new;
end;
$$ language plpgsql security definer;

-- Create trigger function to validate dispute changes
create or replace function trades_validate_dispute_change()
returns trigger
set search_path = ''
as $$
begin
  if (new.sender_disputed != old.sender_disputed or new.receiver_disputed != old.receiver_disputed)
    and old.status != 'completed' then
    raise exception 'Can only dispute completed trades';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to prevent certain field changes
create or replace function trades_prevent_changes()
returns trigger
set search_path = ''
as $$
begin
  -- sender_id cannot change
  if new.sender_id != old.sender_id
  -- receiver_id cannot change
  or new.receiver_id != old.receiver_id
  -- original_id cannot change
  or new.original_id != old.original_id
  -- sender cannot change receiver_disputed or receiver_vaultless
  or ((select auth.uid()) = new.sender_id and (
    new.receiver_disputed != old.receiver_disputed or new.receiver_vaultless != old.receiver_vaultless
    ))
  -- receiver can only change status, receiver_disputed, or receiver_vaultless
  or ((select auth.uid()) = new.receiver_id and (
    new.sender_disputed != old.sender_disputed or
    new.sender_vaultless != old.sender_vaultless or
    new.sender_total != old.sender_total or
    new.receiver_total != old.receiver_total or
    new.criteria != old.criteria
  ))
    then
    raise exception 'Change not allowed';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to handle notifications for trades
create or replace function trades_handle_notifications()
returns trigger
set search_path = ''
as $$
begin
  -- For new trades, create a notification for the receiver if enabled
  if tg_op = 'INSERT' and new.receiver_id is not null then
    -- Only send notification if the user has enabled 'new_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.receiver_id
      and 'new_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.receiver_id, 'new_trade', '/trade/' || new.id);
    end if;
  end if;

  -- For updates, create a notification for the sender if trade is accepted and if enabled
  if tg_op = 'UPDATE' and new.status = 'accepted' and new.sender_id is not null then
    -- Only send notification if the user has enabled 'accepted_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.sender_id
      and 'accepted_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.sender_id, 'accepted_trade', '/trade/' || new.id);
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- Create trigger function to handle trade activity
create or replace function trades_handle_activity()
returns trigger
set search_path = ''
as $$
begin
  -- For new trades
  if tg_op = 'INSERT' then
    -- Record creation
    insert into public.trade_activity (trade_id, user_id, type)
    values (new.id, new.sender_id, 'created');
    
    -- Record counter if applicable
    if new.original_id is not null then
      insert into public.trade_activity (trade_id, user_id, type)
      values (new.id, new.sender_id, 'countered');
      
      -- abort original trade
      update trades set status = 'aborted' where id = new.original_id;
    end if;
  
  -- For updates
  elsif tg_op = 'UPDATE' then
    -- Status changes
    if new.status != old.status then
      insert into public.trade_activity (trade_id, user_id, type)
      values (new.id, (select auth.uid()), new.status::text::public.trade_activity_type);
    
    -- Dispute changes
    elsif (new.sender_disputed != old.sender_disputed or new.receiver_disputed != old.receiver_disputed) then
      if new.sender_disputed or new.receiver_disputed then
        insert into public.trade_activity (trade_id, user_id, type)
        values (new.id, (select auth.uid()), 'disputed');
      else
        insert into public.trade_activity (trade_id, user_id, type)
        values (new.id, (select auth.uid()), 'resolved');
      end if;
    
    -- Other changes
    else
      insert into public.trade_activity (trade_id, user_id, type)
      values (new.id, (select auth.uid()), 'edited');
    end if;
  end if;
  
  return new;
end;
$$ language plpgsql security definer;

-- Create trigger function to handle if a trade is completed
create or replace function trades_handle_completed()
returns trigger
set search_path = ''
as $$
declare
  v_new_vault_entry public.vault_entries%rowtype;
  v_vault_entry public.vault_entries%rowtype;
begin
  -- Skip if the trade is not completed or if vaultless, we are done
  if new.status != 'completed' or new.sender_vaultless = true then
    return new;
  end if;
  -- We assume that the trade is valid (checked in the status change trigger)

  -- Create received vault entries for each selected app
  for v_vault_entry in
    select * from public.vault_entries
    where id in (
      select vault_entry_id from public.trade_apps
      where trade_id = new.id
      and selected = true
    )
    and trade_id is null
  loop
    -- Create new vault entry
    insert into public.vault_entries (
      user_id,
      type,
      app_id,
      trade_id
    ) values (
      case 
        when v_vault_entry.user_id = new.sender_id then new.receiver_id
        else new.sender_id
      end,
      v_vault_entry.type,
      v_vault_entry.app_id,
      new.id
    ) returning * into v_new_vault_entry;
    
    -- Copy vault value from original entry to the new entry
    insert into public.vault_values (
      vault_entry_id,
      receiver_id,
      value
    )
    select 
      v_new_vault_entry.id as vault_entry_id,
      receiver_id,
      value
    from public.vault_values
    where vault_entry_id = v_vault_entry.id
    and receiver_id = v_new_vault_entry.user_id;

    -- Update the original entry with the completed trade ID (marking it as sent)
    update public.vault_entries
    set trade_id = new.id
    where id = v_vault_entry.id;
  end loop;
  return new;
end;
$$ language plpgsql security definer;

-- Create triggers
create trigger trades_validate_creation_trigger
before insert on trades
for each row
execute function trades_validate_creation();

create trigger trades_validate_status_change_trigger
before update of status on trades
for each row
execute function trades_validate_status_change();

create trigger trades_validate_dispute_change_trigger
before update of sender_disputed, receiver_disputed on trades
for each row
execute function trades_validate_dispute_change();

create trigger trades_prevent_changes_trigger
before update of sender_id, receiver_id on trades
for each row
execute function trades_prevent_changes();

create trigger trades_handle_activity_trigger
after insert or update on trades
for each row
execute function trades_handle_activity();

create trigger trades_handle_notifications_trigger
after insert or update on trades
for each row
execute function trades_handle_notifications();

create trigger trades_handle_completed_trigger
after update of status on trades
for each row
execute function trades_handle_completed();

-- Add date management triggers
create trigger trades_update_dates
before update on trades
for each row
execute function update_dates();

create trigger trades_insert_dates
before insert on trades
for each row
execute function insert_dates();

-- Enable RLS
alter table trades enable row level security;

-- Allow read access for all users
create policy trades_select on trades
for select
to authenticated, anon
using (true);

-- Allow creation with multiple conditions:
-- 1. User must be the sender
-- 2. Sender and receiver must be different
-- 3. Status must be pending
-- 4. Either receiver or criteria must be set, or both
create policy trades_insert on trades
for insert
to authenticated
with check (
  (select auth.uid()) = sender_id
  and sender_id != receiver_id
  and status = 'pending'
  and (receiver_id is not null or criteria is not null)
);

-- Allow update when user is sender or receiver
create policy trades_update on trades
for update
to authenticated
using (
  ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id)
)
with check (
  ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id)
);

-- Allow deletion with multiple conditions:
-- 1. User must be the sender
-- 2. Trade must be pending
create policy trades_delete on trades
for delete
to authenticated
using (
  (select auth.uid()) = sender_id
  and status = 'pending'
);

-- ============================================================================
-- Schema file: ./schemas/public/collection_relations.sql
-- ============================================================================

-- Create collection_relations table
create table collection_relations (
  collection_id text not null references collections(id) on delete cascade,
  parent_id text not null references collections(id) on delete cascade,
  primary key (collection_id, parent_id),
  check (collection_id != parent_id)
);

-- Add table comment
comment on table collection_relations is 'Many-to-many relationships between collections';

-- Enable RLS
alter table collection_relations enable row level security;

-- Allow read for public collections and own collections
create policy collection_relations_select on collection_relations
for select
to authenticated, anon
using (
  exists (select 1 from collections c where c.id = collection_id and (not c.private or c.user_id = (select auth.uid())))
  and
  exists (select 1 from collections p where p.id = parent_id and (not p.private or p.user_id = (select auth.uid())))
);

-- Allow creation when user owns the parent collection and child is public
create policy collection_relations_insert on collection_relations
for insert
to authenticated
with check (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid()
  )
  and
  exists (
    select 1 from collections
    where id = collection_id and not private
  )
);

-- Allow update when user owns the parent collection and new child is public
create policy collection_relations_update on collection_relations
for update
to authenticated
using (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid())
)
with check (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid())
  and exists (
    select 1 from collections
    where id = collection_id and not private
  )
);

-- Allow deletion when user owns the parent collection
create policy collection_relations_delete on collection_relations
for delete
to authenticated
using (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid()
  )
);

-- Create trigger function to prevent adding parents to master collections
create or replace function prevent_master_collection_parent()
returns trigger
set search_path = ''
as $$
begin
  if exists (select 1 from public.collections where id = new.collection_id and master = true) then
    raise exception 'Cannot add parent to a master collection';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger prevent_master_collection_parent_trigger
before insert or update on collection_relations
for each row
execute function prevent_master_collection_parent();

-- ============================================================================
-- Schema file: ./schemas/public/collection_apps.sql
-- ============================================================================

-- Create collection_apps_source enum
create type collection_apps_source as enum (
  'user',
  'sync'
);

-- Create collection_apps table
create table collection_apps (
  collection_id text not null references collections(id) on delete cascade,
  app_id integer not null references apps(id) on delete cascade,
  source collection_apps_source not null default 'user',
  created_at timestamptz default now(),
  primary key (collection_id, app_id)
);

-- Add table comment
comment on table collection_apps is 'Apps included in collections';

-- Create function to bulk remove apps from collections
create or replace function bulk_remove_collection_apps(p_collection_id text, p_apps integer[])
returns void
set search_path = ''
as $$
begin
  delete from public.collection_apps
  where collection_id = p_collection_id
  and app_id = any(p_apps);
end;
$$ language plpgsql security invoker;

-- Create function to sync/diff apps in a collection
create or replace function sync_collection_apps(p_collection_id text, p_apps integer[])
returns void
set search_path = ''
as $$
declare
  apps_to_remove integer[];
  apps_to_add integer[];
begin
  -- Find sync apps currently in the collection that are not in the new list
  select array_agg(app_id) into apps_to_remove
  from public.collection_apps
  where collection_id = p_collection_id
    and source = 'sync'
    and app_id <> all(p_apps);

  if apps_to_remove is not null then
    perform public.bulk_remove_collection_apps(p_collection_id, apps_to_remove);
  end if;

  -- Find app ids in the new list that are not already present in the collection (regardless of source)
  select array_agg(new_app.new_app_id) into apps_to_add
  from unnest(p_apps) as new_app(new_app_id)
  where not exists (
    select 1
    from public.collection_apps
    where collection_id = p_collection_id
      and app_id = new_app.new_app_id
  );

  if apps_to_add is not null then
    perform public.bulk_insert(
      'public.collection_apps'::text,
      (
      select jsonb_agg(
        jsonb_build_object(
          'collection_id', p_collection_id,
          'app_id', new_app.new_app_id,
          'source', 'sync'
        )
      )
      from unnest(apps_to_add) as new_app(new_app_id)
      )
    );
  end if;
end;
$$ language plpgsql security invoker
set statement_timeout to '120s';

-- Create function to get all apps in a user's master collections
create or replace function get_master_collections_apps(p_user_id uuid)
returns table (
  tradelist json,
  wishlist json,
  library json,
  blacklist json
)
set search_path = ''
as $$
with recursive collection_hierarchy as (
  -- Find the user's master collections for the specified types
  select id, type
  from public.collections
  where user_id = p_user_id
    and master = true
    and type in ('tradelist', 'wishlist', 'library', 'blacklist')

  union all

  -- Recursively find all child collections through collection_relations
  select cr.collection_id, ch.type
  from public.collection_relations cr
  inner join collection_hierarchy ch on cr.parent_id = ch.id
)
select
  -- Aggregate app_ids for each type into a JSON array
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'tradelist')) as tradelist,
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'wishlist')) as wishlist,
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'library')) as library,
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'blacklist')) as blacklist;
$$ language sql stable security invoker;

-- Create function to clean app collections
create or replace function clean_app_collections()
returns void
set search_path = ''
as $$
declare
  v_app public.apps%rowtype;
  item text;
begin
  -- Reset counter fields for all apps
  update public.apps
  set libraries = 0,
      wishlists = 0,
      tradelists = 0,
      blacklists = 0;
      
  -- Update counters based on collection_apps data
  -- Update library count
  update public.apps a
  set libraries = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'library' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update wishlist count
  update public.apps a
  set wishlists = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'wishlist' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update tradelist count
  update public.apps a
  set tradelists = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'tradelist' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update blacklist count
  update public.apps a
  set blacklists = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'blacklist' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;

  -- Remove all app-type collections
  delete from public.collection_apps
  where collection_id in (
    select id from public.collections
    where type = 'app'
    and user_id is null
  );

  -- Recreate app collections for each app
  for v_app in select * from public.apps loop
    -- Type collection
    if v_app.type is not null then
      perform public.add_collection_app('type-' || public.slugify(v_app.type::text), v_app.id, initcap(v_app.type::text) || ' (type)');
    end if;

    -- Developer collections
    if v_app.developers is not null then
      foreach item in array v_app.developers loop
        perform public.add_collection_app('developer-' || public.slugify(item), v_app.id, initcap(item) || ' (developer)');
      end loop;
    end if;

    -- Publisher collections
    if v_app.publishers is not null then
      foreach item in array v_app.publishers loop
        perform public.add_collection_app('publisher-' || public.slugify(item), v_app.id, initcap(item) || ' (publisher)');
      end loop;
    end if;

    -- Tag collections
    if v_app.tags is not null then
      foreach item in array v_app.tags loop
        perform public.add_collection_app('tag-' || public.slugify(item), v_app.id, initcap(item) || ' (tag)');
      end loop;
    end if;

    -- Language collections
    if v_app.languages is not null then
      foreach item in array v_app.languages loop
        perform public.add_collection_app('language-' || public.slugify(item), v_app.id, initcap(item) || ' (language)');
      end loop;
    end if;

    -- Platform collections
    if v_app.platforms is not null then
      foreach item in array v_app.platforms loop
        perform public.add_collection_app('platform-' || public.slugify(item), v_app.id, initcap(item) || ' (platform)');
      end loop;
    end if;

    -- Other collections
    if v_app.free is true or v_app.retail_price = 0 then
      perform public.add_collection_app('free', v_app.id, 'Free');
    end if;

    if v_app.plus_one is true then
      perform public.add_collection_app('plus-one', v_app.id, 'Plus One');
    end if;

    if v_app.exfgls is true then
      perform public.add_collection_app('exfgls', v_app.id, 'Excluded from Library Sharing');
    end if;

    if v_app.steamdeck in ('Playable', 'Verified') then
      perform public.add_collection_app('steamdeck', v_app.id, 'SteamDeck Compatible');
    end if;

    if v_app.cards > 0 then
      perform public.add_collection_app('with-cards', v_app.id, 'With Cards');
    end if;

    if v_app.achievements > 0 then
      perform public.add_collection_app('with-achievements', v_app.id, 'With Achievements');
    end if;

    if v_app.bundles > 0 then
      perform public.add_collection_app('bundled', v_app.id, 'Bundled');
    end if;

    if v_app.giveaways > 0 then
      perform public.add_collection_app('givenaway', v_app.id, 'Givenaway');
    end if;

    if v_app.removed_at is not null then
      perform public.add_collection_app('removed', v_app.id, 'Removed');
    end if;

    if v_app.removed_as is not null then
      perform public.add_collection_app('removed-' || public.slugify(v_app.removed_as), v_app.id, initcap(v_app.removed_as));
    end if;
  end loop;
end;
$$ language plpgsql security definer;

-- Create trigger
create trigger collection_apps_ensure_app_exists
before insert on collection_apps
for each row
execute function ensure_app_exists();

-- Create trigger function to update app statistics on collection changes
create or replace function collection_apps_update_app_stats()
returns trigger
set search_path = ''
as $$
declare
  v_collection_data record;
  increment integer;
begin
  -- Determine if we're incrementing (insert) or decrementing (delete)
  increment := case when tg_op = 'INSERT' then 1 else -1 end;
  
  -- Get the collection type and master status in a single query
  select type, master into v_collection_data
  from public.collections
  where id = case when tg_op = 'INSERT' then new.collection_id else old.collection_id end;
  
  -- Only update stats for master collections of specific types
  if v_collection_data.type in ('library', 'wishlist', 'tradelist', 'blacklist') and v_collection_data.master = true then
    -- Update the appropriate counter in the apps table
    execute format('
      update public.apps
      set %Is = coalesce(%Is, 0) + %L
      where id = %L
      and coalesce(%Is, 0) + %L >= 0', -- Ensure count doesn't go below zero
      v_collection_data.type, v_collection_data.type, increment,
      case when tg_op = 'INSERT' then new.app_id else old.app_id end,
      v_collection_data.type, increment
    );
  end if;
  
  return null; -- This is an AFTER trigger, so the return value is ignored
end;
$$ language plpgsql security definer;

-- Create triggers to update app stats on collection app changes
create trigger collection_apps_after_insert
after insert on collection_apps
for each row
execute function collection_apps_update_app_stats();

create trigger collection_apps_after_delete
after delete on collection_apps
for each row
execute function collection_apps_update_app_stats();

-- Add date management triggers
create trigger collection_apps_update_dates
before update on collection_apps
for each row
execute function update_dates();

create trigger collection_apps_insert_dates
before insert on collection_apps
for each row
execute function insert_dates();

-- Enable RLS
alter table collection_apps enable row level security;

-- Allow read access for public collections and own collections
create policy collection_apps_select on collection_apps
for select
to authenticated, anon
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and (
        not private
        or user_id = (select auth.uid())
      )
  )
);

-- Allow creation for own collections only
create policy collection_apps_insert on collection_apps
for insert
to authenticated
with check (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);

-- Disallow update for all users

-- Allow deletion for own collections only
create policy collection_apps_delete on collection_apps
for delete
to authenticated
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);

-- ============================================================================
-- Schema file: ./schemas/public/preferences.sql
-- ============================================================================

-- Create widget type enum
create type widget as enum (
  'welcome', 'stats', 'trade_activity', 'users_online'
);

-- Create preferences table
create table preferences (
  user_id uuid primary key references users(id) on delete cascade,
  app_links jsonb default '[
    {"title":"Homepage","url":"{website}"},
    {"title":"Steam Store","url":"https://store.steampowered.com/app/{appid}"},
    {"title":"Steam Community","url":"https://steamcommunity.com/app/{appid}"},
    {"title":"SteamDB","url":"https://steamdb.info/app/{appid}/"},
    {"title":"GG.deals","url":"https://gg.deals/steam/app/{appid}/"}
  ]'::jsonb,
  app_columns text[] default array['title', 'type', 'retail_price', 'market_price', 'plus_one', 'cards', 'achievements', 'tradelists', 'wishlists']::text[],
  dark_mode boolean default true,
  dashboard_widgets widget[] default array['welcome', 'users_online', 'stats', 'trade_activity']::widget[],
  enabled_notifications notification[] default array['new_trade', 'accepted_trade', 'new_vault_entry', 'unread_messages']::notification[],
  incoming_criteria jsonb default '{
    "collections": {"only":[],"except":[]},
    "tags": {"only":[],"except":[]},
    "apps": {"only":[],"except":[]}
  }'::jsonb,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table preferences is 'User preferences and settings';

-- Create trigger function to validate app_columns columns
create or replace function preferences_validate_app_columns()
returns trigger
set search_path = ''
as $$
begin
  -- Check if all values in app_columns exist as column names in the apps table
  if exists (
    select 1 
    from unnest(new.app_columns) as col 
    where not exists (
      select 1 
      from information_schema.columns 
      where table_schema = 'public'
      and table_name = 'apps' 
      and column_name = col
    )
  ) then
    raise exception 'app_columns array contains invalid column names';
  end if;
  
  return new;
end;
$$ language plpgsql security definer;

-- Create trigger
create trigger preferences_validate_app_columns_trigger
before insert or update on preferences
for each row
execute function preferences_validate_app_columns();

-- Add date management triggers
create trigger preferences_update_dates
before update on preferences
for each row
execute function update_dates();

create trigger preferences_insert_dates
before insert on preferences
for each row
execute function insert_dates();

-- Enable RLS
alter table preferences enable row level security;

-- Allow read access for all
create policy preferences_select 
on preferences
for select
to authenticated, anon
using (true);

-- Allow creation for yourself only
create policy preferences_insert
on preferences
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Allow update for yourself only
create policy preferences_update
on preferences
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Disallow deletion for all users

-- ============================================================================
-- Schema file: ./schemas/public/reviews.sql
-- ============================================================================

-- Create reviews table
create table reviews (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references users(id) on delete cascade check (subject_id != user_id),
  user_id uuid not null references users(id) on delete cascade check (user_id != subject_id),
  body text default null check (body is null or (length(body) between 1 and 5000)),
  speed integer not null check (speed between 1 and 5),
  communication integer not null check (communication between 1 and 5),
  helpfulness integer not null check (helpfulness between 1 and 5),
  fairness integer not null check (fairness between 1 and 5),
  updated_at timestamptz default null,
  created_at timestamptz default now(),
  unique (subject_id, user_id)
);

-- Add table comment
comment on table reviews is 'User reviews from trading partners';

-- Create trigger function to prevent changing subject_id
create or replace function reviews_prevent_subject_id_change()
returns trigger
set search_path = ''
as $$
begin
  if old.subject_id != new.subject_id then
    raise exception 'Cannot change subject_id in reviews';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger reviews_prevent_subject_id_change_trigger
before update on reviews
for each row
execute function reviews_prevent_subject_id_change();

-- Add date management triggers
create trigger reviews_update_dates
before update on reviews
for each row
execute function update_dates();

create trigger reviews_insert_dates
before insert on reviews
for each row
execute function insert_dates();

-- Enable RLS
alter table reviews enable row level security;

-- Allow read access for all users
create policy reviews_select on reviews
for select
to authenticated, anon
using (true);

-- Allow creation with multiple conditions:
-- 1. Reviewer must be the authenticated user
-- 2. Cannot review self
-- 3. Must have completed a trade with the user
create policy reviews_insert on reviews
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and user_id != subject_id
  and exists (
    select 1 from trades
    where
      status = 'completed'
      and (
        (sender_id = user_id and receiver_id = subject_id)
        or
        (sender_id = subject_id and receiver_id = user_id)
      )
  )
);

-- Allow update for own reviews only
create policy reviews_update on reviews
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Allow deletion for own reviews only
create policy reviews_delete on reviews
for delete
to authenticated
using ((select auth.uid()) = user_id);

-- ============================================================================
-- Schema file: ./schemas/public/trade_activity.sql
-- ============================================================================

-- Create trade_activity table
create table trade_activity (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  type trade_activity_type not null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table trade_activity is 'Activity log for trades';

-- Enable realtime for this table
alter publication supabase_realtime add table trade_activity;

-- Add date management triggers
create trigger trade_activity_update_dates
before update on trade_activity
for each row
execute function update_dates();

create trigger trade_activity_insert_dates
before insert on trade_activity
for each row
execute function insert_dates();

-- Enable RLS
alter table trade_activity enable row level security;

-- Allow read access for all users
create policy trade_activity_select on trade_activity
for select
to authenticated, anon
using (true);

-- Disallow creation for all users
-- Disallow updates for all users
-- Disallow deletion for all users

-- ============================================================================
-- Schema file: ./schemas/public/trade_messages.sql
-- ============================================================================

-- Create trade_messages table
create table trade_messages (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  user_id uuid references users(id) on delete set null default null,
  body text not null check (length(body) between 1 and 5000),
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table trade_messages is 'Messages between users in a trade';

-- Enable realtime for this table
alter publication supabase_realtime add table trade_messages;

-- Create index on created_at for faster queries
create index if not exists idx_trade_messages_created_at 
  on trade_messages(created_at);

-- Create trigger function to prevent user_id and trade_id changes
create or replace function trade_messages_prevent_changes()
returns trigger
set search_path = ''
as $$
begin
  if new.trade_id != old.trade_id or new.user_id != old.user_id then
    raise exception 'Cannot change trade_id or user_id';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create function to check and send unread message notifications
create or replace function process_unread_message_notifications()
returns void
set search_path = ''
as $$
begin
  -- Insert notifications for unread messages from the last minute
  -- This query:
  -- 1. Finds messages from the last minute
  -- 2. Determines the recipient (the other user in the trade)
  -- 3. Checks if they've viewed the trade since the latest message
  -- 4. Checks if notifications are enabled for that user
  -- 5. Groups by trade_id and recipient to send only one notification per trade
  insert into public.notifications (user_id, type, link)
  select 
    distinct recipient_id, 
    'unread_messages'::public.notification, 
    '/trade/' || trade_id
  from (
    -- Get messages from the last minute and identify recipients
    select
      tm.trade_id,
      case 
        when tm.user_id = t.sender_id then t.receiver_id
        else t.sender_id
      end as recipient_id,
      max(tm.created_at) as latest_message_time
    from public.trade_messages tm
    join public.trades t on t.id = tm.trade_id
    where tm.created_at > now() - interval '1 minute'
    group by tm.trade_id, recipient_id
  ) as recent_messages
  where 
    -- Only send if notifications are enabled for this user
    exists (
      select 1 
      from public.preferences
      where user_id = recipient_id
      and 'unread_messages' = any(enabled_notifications)
    )
    -- Only send if user hasn't viewed the trade since the latest message
    and (
      not exists (
        select 1
        from public.trade_views tv
        where tv.trade_id = recent_messages.trade_id 
        and tv.user_id = recent_messages.recipient_id
      ) 
      or exists (
        select 1
        from public.trade_views tv
        where tv.trade_id = recent_messages.trade_id 
        and tv.user_id = recent_messages.recipient_id
        and tv.updated_at < recent_messages.latest_message_time
      )
    );
end;
$$ language plpgsql security definer;

-- Schedule the cron job to run every 5 minutes
select cron.schedule('process_unread_messages', '* * * * *', $$
  select public.process_unread_message_notifications()
$$);

-- Create triggers
create trigger trade_messages_prevent_changes_trigger
before update on trade_messages
for each row
execute function trade_messages_prevent_changes();

-- Add date management triggers
create trigger trade_messages_update_dates
before update on trade_messages
for each row
execute function update_dates();

create trigger trade_messages_insert_dates
before insert on trade_messages
for each row
execute function insert_dates();

-- Enable RLS
alter table trade_messages enable row level security;

-- Allow read access for all users
create policy trade_messages_select on trade_messages
for select
to authenticated, anon
using (true);

-- Allow creation for own messages only
create policy trade_messages_insert on trade_messages
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Allow update for own messages within 5 minutes
create policy trade_messages_update on trade_messages
for update
to authenticated
using (
  (select auth.uid()) = user_id
  and created_at > now() - interval '5 minutes'
)
with check ((select auth.uid()) = user_id);

-- Allow deletion for own messages within 5 minutes
create policy trade_messages_delete on trade_messages
for delete
to authenticated
using (
  (select auth.uid()) = user_id
  and created_at > now() - interval '5 minutes'
);

-- ============================================================================
-- Schema file: ./schemas/public/trade_views.sql
-- ============================================================================

-- Create trade_views table
create table trade_views (
  trade_id uuid references trades(id) on delete cascade,
  user_id uuid references users(id) on delete cascade,
  updated_at timestamptz default null,
  created_at timestamptz default now(),
  primary key (trade_id, user_id)
);

-- Add table comment
comment on table trade_views is 'Tracks the first and last trade view for each user';

-- Create trigger function to prevent user_id and trade_id changes
create or replace function trade_views_prevent_changes()
returns trigger
set search_path = ''
as $$
begin
  if new.trade_id != old.trade_id or new.user_id != old.user_id then
    raise exception 'Cannot change trade_id or user_id';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger trade_views_prevent_changes_trigger
before update on trade_views
for each row
execute function trade_views_prevent_changes();

-- Add date management triggers
create trigger trade_views_update_dates
before update on trade_views
for each row
execute function update_dates();

create trigger trade_views_insert_dates
before insert on trade_views
for each row
execute function insert_dates();

-- Enable RLS
alter table trade_views enable row level security;

-- Allow read access for all users
create policy trade_views_select on trade_views
for select
to authenticated, anon
using (true);

-- Allow creation for own views only
create policy trade_views_insert on trade_views
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Allow update for own views only
create policy trade_views_update on trade_views
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Disallow deletion for all users

-- ============================================================================
-- Schema file: ./schemas/public/vault_entries.sql
-- ============================================================================

-- Create vault entry type enum
create type vault_entry_type as enum (
  'key',
  'gift',
  'link',
  'curator'
);

-- Create vault_entries table
create table vault_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  app_id integer not null references apps(id) on delete cascade,
  trade_id uuid default null references trades(id) on delete cascade,
  type vault_entry_type not null,
  revealed_at timestamptz default null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table vault_entries is 'Received and own vault entries';

-- Create trigger function to prevent id, user_id, app_id, trade_id changes
create or replace function vault_entries_prevent_changes()
returns trigger
set search_path = ''
as $$
begin
  if new.id != old.id or new.user_id != old.user_id or new.app_id != old.app_id or new.trade_id != old.trade_id then
    raise exception 'Cannot change id, user_id, app_id, or trade_id';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to handle notifications when vault entries are created
create or replace function vault_entries_handle_notifications()
returns trigger
set search_path = ''
as $$
begin
  -- Only process if trade_id is set
  if new.trade_id is not null then
    -- Only send notification if the user has enabled 'new_vault_entry' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.user_id
      and 'new_vault_entry' = ANY(enabled_notifications)
    ) then
      -- Create notification for the user who added the entry
      insert into public.notifications (user_id, type, link)
      values (new.user_id, 'new_vault_entry', '/vault?tab=received&appid=' || new.app_id);
    end if;
  end if;
  
  return new;
end;
$$ language plpgsql security definer;

-- Create triggers
create trigger vault_entries_ensure_app_exists
before insert on vault_entries
for each row
execute function ensure_app_exists();

create trigger vault_entries_prevent_changes_trigger
before update on vault_entries
for each row
execute function vault_entries_prevent_changes();

create trigger vault_entries_handle_notifications_trigger
after insert on vault_entries
for each row
execute function vault_entries_handle_notifications();

-- Add date management triggers
create trigger vault_entries_update_dates
before update on vault_entries
for each row
execute function update_dates();

create trigger vault_entries_insert_dates
before insert on vault_entries
for each row
execute function insert_dates();

-- Enable RLS
alter table vault_entries enable row level security;

-- Allow read access for own vault entries only
create policy vault_entries_select on vault_entries
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Allow creation for own vault entries only
create policy vault_entries_insert on vault_entries
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Allow update for my own vault entries only
create policy vault_entries_update on vault_entries
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Allow deletion for own vault entries only
create policy vault_entries_delete on vault_entries
for delete
to authenticated
using ((select auth.uid()) = user_id);

-- ============================================================================
-- Schema file: ./schemas/public/vault_values.sql
-- ============================================================================

-- Create vault_values table
create table vault_values (
  vault_entry_id uuid references vault_entries(id) on delete cascade,
  receiver_id uuid references users(id) on delete cascade,
  value text not null,
  created_at timestamptz default now(),
  primary key (vault_entry_id, receiver_id)
);

-- Add table comment
comment on table vault_values is 'Encrypted values associated with vault entries and designated receivers';

-- Function to get vault entries for a user
create or replace function get_vault_entries(p_user_id uuid)
returns table (
  app_id integer,
  trade_id uuid,
  type public.vault_entry_type,
  value text,
  revealed_at timestamptz,
  updated_at timestamptz,
  created_at timestamptz
)
set search_path = ''
as $$
begin
  return query
  select
    ve.app_id,
    ve.trade_id,
    ve.type,
    vv.value,
    ve.revealed_at,
    ve.updated_at,
    ve.created_at
  from public.vault_entries ve
  join public.vault_values vv on vv.vault_entry_id = ve.id
  where ve.user_id = p_user_id
    and vv.receiver_id = p_user_id;
end;
$$ language plpgsql security invoker;

-- Add date management triggers
create trigger vault_values_update_dates
before update on vault_values
for each row
execute function update_dates();

create trigger vault_values_insert_dates
before insert on vault_values
for each row
execute function insert_dates();

-- Enable RLS
alter table vault_values enable row level security;

-- Allow read access for own vault entries only
create policy vault_values_select on vault_values
for select
to authenticated, anon
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Allow creation for own vault entries only
create policy vault_values_insert on vault_values
for insert
to authenticated
with check (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Disallow update for all users

-- Allow deletion for own collections only
create policy vault_values_delete on vault_values
for delete
to authenticated
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- ============================================================================
-- Schema file: ./schemas/public/collection_tags.sql
-- ============================================================================

-- Create collection_tags table
create table collection_tags (
  collection_id text not null references collections(id) on delete cascade,
  app_id integer not null references apps(id) on delete cascade,
  tag_id integer not null references tags(id) on delete cascade,
  body text default null,
  created_at timestamptz default now(),
  primary key (collection_id, app_id, tag_id)
);

-- Add table comment
comment on table collection_tags is 'Tags associated with apps in collections';

-- Create trigger
create trigger collection_tags_ensure_app_exists
before insert on collection_tags
for each row
execute function ensure_app_exists();

-- Add date management triggers
create trigger collection_tags_update_dates
before update on collection_tags
for each row
execute function update_dates();

create trigger collection_tags_insert_dates
before insert on collection_tags
for each row
execute function insert_dates();

-- Enable RLS
alter table collection_tags enable row level security;

-- Allow read access for public collections and own collections
create policy collection_tags_select on collection_tags
for select
to authenticated, anon
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and (
        not private
        or user_id = (select auth.uid())
      )
  )
);

-- Allow creation for own collections only
create policy collection_tags_insert on collection_tags
for insert
to authenticated
with check (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);

-- Allow update for own collections only
create policy collection_tags_update on collection_tags
for update
to authenticated
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);

-- Allow deletion for own collections only
create policy collection_tags_delete on collection_tags
for delete
to authenticated
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);

-- ============================================================================
-- Schema file: ./schemas/public/vault_tags.sql
-- ============================================================================

-- Create vault_tags table
create table vault_tags (
  vault_entry_id uuid not null references vault_entries(id) on delete cascade,
  tag_id integer not null references tags(id) on delete cascade,
  body text default null,
  created_at timestamptz default now(),
  primary key (vault_entry_id, tag_id)
);

-- Add table comment
comment on table vault_tags is 'Tags associated with vault entries';

-- Add date management triggers
create trigger vault_tags_update_dates
before update on vault_tags
for each row
execute function update_dates();

create trigger vault_tags_insert_dates
before insert on vault_tags
for each row
execute function insert_dates();

-- Enable RLS
alter table vault_tags enable row level security;

-- Allow read access for own vault tags only
create policy vault_tags_select on vault_tags
for select
to authenticated
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Allow creation for own vault tags only
create policy vault_tags_insert on vault_tags
for insert
to authenticated
with check (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Allow update for own vault tags only
create policy vault_tags_update on vault_tags
for update
to authenticated
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Allow deletion for own vault tags only
create policy vault_tags_delete on vault_tags
for delete
to authenticated
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- ============================================================================
-- Schema file: ./schemas/public/trade_apps.sql
-- ============================================================================

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

-- ============================================================================
-- Schema file: ./schemas/public/views.sql
-- ============================================================================

-- Materialized view to store site-wide statistics
create materialized view site_statistics as
select  
  -- Overall counts  
  (select count(*) from users) as total_users,  
  (select count(*) from trades) as total_trades,  
  (select count(*) from vault_entries) as total_vault_entries,  

  -- Total traded volume (sum of sender_total and receiver_total)  
  (
    select sum(sender_total + receiver_total) from trades
    where status = 'completed'
  ) as total_traded_volume,  

  -- Count of trades where a dispute occurred  
  (
    select count(*) from trades
    where sender_disputed or receiver_disputed
  ) as disputed_trades,  

  -- Trade counts by status  
  (
    select count(*) from trades
    where status = 'pending'
  ) as trades_pending,  
  (
    select count(*) from trades
    where status = 'accepted'
  ) as trades_accepted,  
  (
    select count(*) from trades
    where status = 'declined'
  ) as trades_declined,  
  (
    select count(*) from trades
    where status = 'aborted'
  ) as trades_aborted,  
  (
    select count(*) from trades
    where status = 'completed'
  ) as trades_completed,  

  -- Vault entry counts by type  
  (
    select floor(count(*) / 2.0) from vault_entries
    where trade_id is not null
  ) as vault_entries_received,  
  (
    select count(*) from vault_entries
    where trade_id is null
  ) as vault_entries_mine,  

  -- Top regions by user count (most popular countries)  
  (  
    select region  
    from (  
      select
        region,
        count(*) as region_count  
      from users  
      where region is not null  
      group by region  
      order by region_count desc, region asc  
      limit 1 offset 0  
    ) as top_regions  
  ) as top_region1,  
  (  
    select region  
    from (  
      select
        region,
        count(*) as region_count  
      from users  
      where region is not null  
      group by region  
      order by region_count desc, region asc  
      limit 1 offset 1  
    ) as top_regions  
  ) as top_region2,  
  (  
    select region  
    from (  
      select
        region,
        count(*) as region_count  
      from users  
      where region is not null  
      group by region  
      order by region_count desc, region asc  
      limit 1 offset 2  
    ) as top_regions  
  ) as top_region3,  

  -- Average trades per user  
  case  
    when (select count(*) from users) > 0  
      then (select count(*)::numeric from trades) / (select count(*) from users)  
    else 0  
  end as avg_trades;

-- Cron job to refresh the materialized view every 30 minutes
select cron.schedule('refresh_site_statistics', '*/30 * * * *', $$
  refresh materialized view site_statistics;
$$);

-- Materialized view for app facets (unique tags, languages, platforms, etc.)
create materialized view app_facets as
select
  -- Get unique tags from all apps
  array(
    select distinct unnest(tags)
    from apps
    where tags is not null
    order by unnest(tags)
  ) as tags,
  
  -- Get unique languages from all apps
  array(
    select distinct unnest(languages)
    from apps
    where languages is not null
    order by unnest(languages)
  ) as languages,
  
  -- Get unique platforms from all apps
  array(
    select distinct unnest(platforms)
    from apps
    where platforms is not null
    order by unnest(platforms)
  ) as platforms,
  
  -- Get unique steamdeck compatibility statuses
  array(
    select distinct steamdeck
    from apps
    where steamdeck is not null
    order by steamdeck
  ) as steamdeck,
  
  -- Get unique removal categories
  array(
    select distinct removed_as
    from apps
    where removed_as is not null
    order by removed_as
  ) as removed_as,
  
  -- Get unique developers
  array(
    select distinct unnest(developers)
    from apps
    where developers is not null
    order by unnest(developers)
  ) as developers,
  
  -- Get unique publishers
  array(
    select distinct unnest(publishers)
    from apps
    where publishers is not null
    order by unnest(publishers)
  ) as publishers;

-- Cron job to refresh the app_facets view every day at midnight
select cron.schedule('refresh_app_facets', '0 0 * * *', $$
  refresh materialized view app_facets;
$$);

-- Materialized view to store user-specific statistics
create materialized view user_statistics as
with user_completed_trades as (
  select id, sender_id, receiver_id
  from trades
  where status = 'completed'
)
select
  u.id as user_id,
  
  -- master wishlist apps (recursive: master collection with master=true and type 'wishlist' and all its descendants)
  (
    select count(*)
    from collection_apps as ca
    where ca.collection_id in (
      with recursive rec as (
        select id
        from collections
        where
          master = true
          and user_id = u.id
          and type = 'wishlist'
        union all
        select cr.collection_id
        from collection_relations cr
        inner join rec r on cr.parent_id = r.id
      )
      select id from rec
    )
  ) as master_wishlist_apps,
  
  -- master tradelist apps
  (
    select count(*)
    from collection_apps as ca
    where ca.collection_id in (
      with recursive rec as (
        select id
        from collections
        where
          master = true
          and user_id = u.id
          and type = 'tradelist'
        union all
        select cr.collection_id
        from collection_relations cr
        inner join rec r on cr.parent_id = r.id
      )
      select id from rec
    )
  ) as master_tradelist_apps,
  
  -- master blacklist apps
  (
    select count(*)
    from collection_apps as ca
    where ca.collection_id in (
      with recursive rec as (
        select id
        from collections
        where
          master = true
          and user_id = u.id
          and type = 'blacklist'
        union all
        select cr.collection_id
        from collection_relations cr
        inner join rec r on cr.parent_id = r.id
      )
      select id from rec
    )
  ) as master_blacklist_apps,
  
  -- master library apps
  (
    select count(*)
    from collection_apps as ca
    where ca.collection_id in (
      with recursive rec as (
        select id
        from collections
        where
          master = true
          and user_id = u.id
          and type = 'library'
        union all
        select cr.collection_id
        from collection_relations cr
        inner join rec r on cr.parent_id = r.id
      )
      select id from rec
    )
  ) as master_library_apps,
  
  -- reviews statistics
  (
    select count(*)
    from reviews
    where subject_id = u.id
  ) as reviews_received,
  (
    select count(*)
    from reviews
    where user_id = u.id
  ) as reviews_given,
  (
    select count(*)
    from reviews
    where subject_id = u.id or user_id = u.id
  ) as total_reviews,
  (
    select avg(speed)
    from reviews
    where subject_id = u.id
  ) as avg_speed,
  (
    select avg(communication)
    from reviews
    where subject_id = u.id
  ) as avg_communication,
  (
    select avg(helpfulness)
    from reviews
    where subject_id = u.id
  ) as avg_helpfulness,
  (
    select avg(fairness)
    from reviews
    where subject_id = u.id
  ) as avg_fairness,
  (
    select id
    from reviews
    where user_id = u.id
    order by created_at desc
    limit 1
  ) as last_given_review_id,
  (
    select id
    from reviews
    where subject_id = u.id
    order by created_at desc
    limit 1
  ) as last_received_review_id,
  
  -- vault entries statistics
  (
    select count(*)
    from vault_entries ve
    left join user_completed_trades t on ve.trade_id = t.id
    where ve.user_id = u.id
      and (ve.trade_id is null or t.sender_id = u.id)
  ) as vault_entries_mine,
  (
    select count(*)
    from vault_entries ve
    join user_completed_trades t on ve.trade_id = t.id
    where ve.user_id = u.id
      and t.receiver_id = u.id
  ) as vault_entries_received,
  (
    select ve.app_id
    from vault_entries ve
    join user_completed_trades t on ve.trade_id = t.id
    where ve.user_id = u.id
      and t.receiver_id = u.id
    order by ve.created_at desc
    limit 1
  ) as latest_received_app_id,
  
  -- trade statistics for trades involving the user
  (
    select count(*)
    from trades
    where (sender_id = u.id or receiver_id = u.id)
      and status = 'pending'
  ) as trades_pending,
  (
    select count(*)
    from trades
    where (sender_id = u.id or receiver_id = u.id)
      and status = 'accepted'
  ) as trades_accepted,
  (
    select count(*)
    from trades
    where (sender_id = u.id or receiver_id = u.id)
      and status = 'declined'
  ) as trades_declined,
  (
    select count(*)
    from trades
    where (sender_id = u.id or receiver_id = u.id)
      and status = 'aborted'
  ) as trades_aborted,
  (
    select count(*)
    from trades
    where (sender_id = u.id or receiver_id = u.id)
      and status = 'completed'
      and (sender_disputed = false and receiver_disputed = false)
  ) as trades_completed,
  
  -- for completed trades, count distinct counterparties
  (
    select count(distinct case when sender_id = u.id then receiver_id else sender_id end)
    from trades
    where (sender_id = u.id or receiver_id = u.id)
      and status = 'completed'
  ) as completed_trades_distinct_users,
  
  -- total trades countered (trades with non-null original_id)
  (
    select count(*)
    from trades
    where (sender_id = u.id or receiver_id = u.id)
      and original_id is not null
  ) as trades_countered,
  
  -- total trades disputed (where either party flagged a dispute)
  (
    select count(*)
    from trades
    where (sender_id = u.id and receiver_disputed)
       or (receiver_id = u.id and sender_disputed)
  ) as trades_disputed,
  (
    select id
    from trades
    where (sender_id = u.id or receiver_id = u.id)
    order by created_at desc
    limit 1
  ) as latest_trade_id,
  
  -- total collections count
  (
    select count(*)
    from collections
    where user_id = u.id
  ) as total_collections
from users u;

-- Cron job to refresh the materialized view every 5 minutes
select cron.schedule('refresh_user_statistics', '*/5 * * * *', $$
  refresh materialized view user_statistics;
$$);

-- Materialized view to store trade partner statistics
create materialized view trade_partners as
select
  least(sender_id, receiver_id) as user_id,
  greatest(sender_id, receiver_id) as partner_id,
  count(*) as total_completed_trades
from trades
where status = 'completed'
group by least(sender_id, receiver_id), greatest(sender_id, receiver_id);

-- Cron job to refresh the materialized view every 5 minutes
select cron.schedule('refresh_trade_partners', '*/5 * * * *', $$
  refresh materialized view trade_partners;
$$);

