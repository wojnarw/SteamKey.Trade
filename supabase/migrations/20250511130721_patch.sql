-- Update default for new users
alter table "public"."preferences" alter column "enabled_notifications" set default ARRAY['new_trade'::notification, 'accepted_trade'::notification, 'new_vault_entry'::notification, 'unread_messages'::notification, 'disputed_trade'::notification, 'resolved_trade'::notification];

-- Enable the new notification types for existing users
UPDATE "public"."preferences" 
SET "enabled_notifications" = array_append(array_append("enabled_notifications", 'disputed_trade'::notification), 'resolved_trade'::notification)
WHERE NOT ('disputed_trade'::notification = ANY("enabled_notifications")) 
   OR NOT ('resolved_trade'::notification = ANY("enabled_notifications"));

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.trades_handle_notifications()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- For new trades, create a notification for the receiver
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

  -- For updates, create a notification for the sender if trade is accepted
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
  
  -- For updates, create a notification for the receiver if trade got disputed by the sender
  if tg_op = 'UPDATE' and new.sender_disputed and not old.sender_disputed then
    -- Only send notification if the user has enabled 'disputed_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.receiver_id
      and 'disputed_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.receiver_id, 'disputed_trade', '/trade/' || new.id);
    end if;
  end if;

  -- For updates, create a notification for the sender if trade got disputed by the receiver
  if tg_op = 'UPDATE' and old.sender_disputed and not new.sender_disputed then
    -- Only send notification if the user has enabled 'resolved_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.receiver_id
      and 'resolved_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.receiver_id, 'resolved_trade', '/trade/' || new.id);
    end if;
  end if;

  -- For updates, create a notification for the sender if trade got disputed by the receiver
  if tg_op = 'UPDATE' and new.receiver_disputed and not old.receiver_disputed then
    -- Only send notification if the user has enabled 'disputed_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.sender_id
      and 'disputed_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.sender_id, 'disputed_trade', '/trade/' || new.id);
    end if;
  end if;

  -- For updates, create a notification for the sender if trade got resolved by the receiver
  if tg_op = 'UPDATE' and old.receiver_disputed and not new.receiver_disputed then
    -- Only send notification if the user has enabled 'resolved_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.sender_id
      and 'resolved_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.sender_id, 'resolved_trade', '/trade/' || new.id);
    end if;
  end if;

  return new;
end;
$function$
;
