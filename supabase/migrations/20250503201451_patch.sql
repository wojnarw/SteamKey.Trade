drop policy "trade_apps_insert" on "public"."trade_apps";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.trades_handle_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- For new trades
  if tg_op = 'INSERT' then
    -- Record creation
    insert into public.trade_activity (trade_id, user_id, type)
    values (new.id, new.sender_id, 'created');
    
    -- Record counter if applicable
    if new.original_id is not null then
      insert into public.trade_activity (trade_id, user_id, type)
      values (new.original_id, new.sender_id, 'countered');
      
      -- abort original trade
      update public.trades set status = 'declined' where id = new.original_id;
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
$function$
;

create policy "trade_apps_insert"
on "public"."trade_apps"
as permissive
for insert
to authenticated
with check (((EXISTS ( SELECT 1
   FROM trades
  WHERE ((trades.id = trade_apps.trade_id) AND (trades.sender_id = ( SELECT auth.uid() AS uid)) AND (trades.status = 'pending'::trade_status)))) AND (collection_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM collections
  WHERE ((collections.id = trade_apps.collection_id) AND (collections.user_id = collections.user_id))))));



