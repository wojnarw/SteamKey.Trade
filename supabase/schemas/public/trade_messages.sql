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