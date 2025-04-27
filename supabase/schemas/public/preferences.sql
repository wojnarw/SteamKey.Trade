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