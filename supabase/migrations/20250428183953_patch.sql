set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.call_edge_function(p_name text, p_body jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    timeout_milliseconds := 3600000
  );
  
  return;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.collection_apps_update_app_stats()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    column_name := collection_type_map->>v_collection_data.type;
    
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
$function$
;


