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