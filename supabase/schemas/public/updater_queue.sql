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