set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.updater_dequeue(p_count integer)
 RETURNS integer[]
 LANGUAGE sql
 SET search_path TO ''
AS $function$
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
),
additional as (
  select id::text as value
  from public.apps
  where id not in (select value::int from deleted)
  order by updated_at asc nulls first
  limit p_count - (select count(*) from deleted)
)
select coalesce(array_agg(value::int), array[]::int[])
from (
  select value from deleted
  union all
  select value from additional
) combined;
$function$
;

CREATE OR REPLACE FUNCTION public.updater_enqueue(p_appids integer[])
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
 SET statement_timeout TO '300s'
AS $function$
begin
  insert into public.updater_queue (type, value)
  select 'app_update', unnest(p_appids)::text
  on conflict do nothing;
end;
$function$
;


