set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.is_sent(ve vault_entries)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    -- if not traded yet, it's also not sent
    case
      when ve.trade_id is null then false
      -- exists a trade_app row for this trade+app where this entry is listed
      when exists (
        select 1
          from public.trade_apps ta
         where ta.trade_id = ve.trade_id
           and ta.app_id = ve.app_id
           and ve.id = any(ta.vault_entries)
           and ta.user_id = (select auth.uid())
      ) then true
      else false
    end
$function$
;


