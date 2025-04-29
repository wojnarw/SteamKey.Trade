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
  primary key (collection_id, app_id)
);

-- Add table comment
comment on table collection_apps is 'Apps included in collections';

-- Add indexes
create index collection_apps_collection_id_idx on public.collection_apps using btree (collection_id);

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
  collection_type_map jsonb;
  column_name text;
begin
  -- Determine if we're incrementing (insert) or decrementing (delete)
  increment := case when tg_op = 'INSERT' then 1 else -1 end;
  
  -- Get the collection type and master status in a single query
  select type, master into v_collection_data
  from public.collections
  where id = case when tg_op = 'INSERT' then new.collection_id else old.collection_id end;
  
  -- Define the mapping of collection types to column names
  collection_type_map := '{
    "library": "libraries",
    "wishlist": "wishlists",
    "tradelist": "tradelists", 
    "blacklist": "blacklists"
  }'::jsonb;
  
  -- Only update stats for master collections of specific types
  if v_collection_data.type in ('library', 'wishlist', 'tradelist', 'blacklist') and v_collection_data.master = true then
    -- Get the column name from the mapping
    column_name := collection_type_map->>v_collection_data.type::text;
    
    -- Update the appropriate counter in the apps table
    execute format('
      update public.apps
      set %I = coalesce(%I, 0) + %L
      where id = %L
      and coalesce(%I, 0) + %L >= 0', -- Ensure count doesn't go below zero
      column_name, column_name, increment,
      case when tg_op = 'INSERT' then new.app_id else old.app_id end,
      column_name, increment
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